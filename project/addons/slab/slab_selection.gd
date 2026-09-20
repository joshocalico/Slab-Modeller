@tool
extends RefCounted

signal changed
signal hover_changed
signal settings_changed
signal mode_requested

enum Mode { OBJECT, VERTEX, EDGE, FACE }
enum Pivot { SELECTION, ACTIVE, CUSTOM }
enum Orientation { WORLD, LOCAL, FACE }

var pivot_mode: int = Pivot.SELECTION
var orientation: int = Orientation.WORLD
var custom_pivot_world := Vector3.ZERO
var xray: bool = false
var active_id: int = 0
var isolated: bool = false
var _hidden_solids: Dictionary = {}

enum Falloff { SMOOTH, LINEAR }

var soft_select: bool = false
var soft_radius: float = 0.5
var soft_falloff: int = Falloff.SMOOTH


func configure_pivot(value: int, position: Variant = null) -> void:
	if value < Pivot.SELECTION or value > Pivot.CUSTOM:
		return
	pivot_mode = value
	if position is Vector3:
		custom_pivot_world = position
	settings_changed.emit()


func configure_orientation(value: int) -> void:
	if value < Orientation.WORLD or value > Orientation.FACE:
		return
	orientation = value
	settings_changed.emit()


func set_xray(value: bool) -> void:
	if xray == value:
		return
	xray = value
	set_hover(null, 0)
	settings_changed.emit()


func set_soft_select(value: bool) -> void:
	if soft_select == value:
		return
	soft_select = value
	settings_changed.emit()


func set_soft_radius(value: float) -> void:
	value = maxf(0.01, value)
	if is_equal_approx(soft_radius, value):
		return
	soft_radius = value
	settings_changed.emit()


func set_soft_falloff(value: int) -> void:
	if value < Falloff.SMOOTH or value > Falloff.LINEAR:
		return
	if soft_falloff == value:
		return
	soft_falloff = value
	settings_changed.emit()


func soft_select_allowed() -> bool:
	return mode != Mode.OBJECT


func enter_isolation(scene_root: Node) -> bool:
	if objects.is_empty() or scene_root == null:
		return false
	if isolated:
		return true
	_hidden_solids.clear()
	var target_set: Dictionary = {}
	for obj in objects:
		if is_instance_valid(obj):
			target_set[obj] = true
	for node in scene_root.find_children("*", SOLID_CLASS, true, false):
		if not target_set.has(node) and node.visible:
			_hidden_solids[node] = true
			node.visible = false
	isolated = true
	settings_changed.emit()
	return true


func exit_isolation() -> void:
	if not isolated:
		return
	for node in _hidden_solids:
		if is_instance_valid(node):
			node.visible = true
	_hidden_solids.clear()
	isolated = false
	settings_changed.emit()


func toggle_isolation(scene_root: Node) -> bool:
	if isolated:
		exit_isolation()
		return false
	return enter_isolation(scene_root)


const SOLID_CLASS := "SlabSolid"
const EXTERNAL_MESH_CLASS := "SlabExternalMesh"

const MODE_LABELS: Dictionary = {
	Mode.OBJECT: "Object",
	Mode.VERTEX: "Vertex",
	Mode.EDGE: "Edge",
	Mode.FACE: "Face",
}

const MODE_NOUNS: Dictionary = {
	Mode.OBJECT: ["solid", "solids"],
	Mode.VERTEX: ["vertex", "vertices"],
	Mode.EDGE: ["edge", "edges"],
	Mode.FACE: ["face", "faces"],
}

var mode: int = Mode.OBJECT:
	set(value):
		if value == mode or not MODE_LABELS.has(value):
			return
		mode = value
		if orientation == Orientation.FACE and mode != Mode.FACE:
			orientation = Orientation.WORLD
		ids = PackedInt64Array()
		active_id = 0
		hover_id = 0
		changed.emit()
		hover_changed.emit()

var objects: Array[Node3D] = []

var ids: PackedInt64Array = PackedInt64Array()

var preview_solid: Node3D = null
var preview_lines := PackedVector3Array()
var array_preview_solid: Node3D = null
var array_preview_transforms: Array[Transform3D] = []
var snap_align_preview: Dictionary = {}
var operation_preview: Dictionary = {}

var hover_solid: Node3D = null

var hover_id: int = 0

var solid: Node3D:
	get:
		return objects[0] if not objects.is_empty() else null
	set(value):
		set_objects([value] if value != null else [])


func request_mode(value: int) -> void:
	if not MODE_LABELS.has(value):
		return
	# An explicit mode choice also leaves a tool when the mode is unchanged.
	mode_requested.emit()
	mode = value


static func is_solid(node: Object) -> bool:
	return node != null and is_instance_valid(node) and node.is_class(SOLID_CLASS)


static func is_external_mesh(node: Object) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.is_class(EXTERNAL_MESH_CLASS):
		return true
	if node is Node and node.has_meta("slab_external_mesh"):
		return true
	return false


static func is_slab_object(node: Object) -> bool:
	return is_solid(node) or is_external_mesh(node)


static func owning_solid(node: Object) -> Node3D:
	if node == null or not is_instance_valid(node):
		return null
	var current: Node = node as Node
	while current != null:
		if is_slab_object(current):
			return current
		current = current.get_parent()
	return null


# Native editor selection may point at Slab's hidden render/collision nodes,
# but an authored child remains an independent scene object.
static func editor_owning_solid(node: Object) -> Node3D:
	if node == null or not is_instance_valid(node) or not node is Node:
		return null
	if is_slab_object(node):
		return node as Node3D
	var current := node as Node
	var crossed_internal := false
	while current.get_parent() != null:
		var parent := current.get_parent()
		if not parent.get_children().has(current):
			crossed_internal = true
		if is_slab_object(parent):
			return (parent as Node3D) if crossed_internal else null
		current = parent
	return null


func drop_invalid() -> void:
	var kept: Array[Node3D] = []
	for node in objects:
		if node != null and is_instance_valid(node):
			kept.append(node)
	objects = kept
	if hover_solid != null and not is_instance_valid(hover_solid):
		hover_solid = null
		hover_id = 0


func set_objects(nodes: Array) -> void:
	var kept: Array[Node3D] = []
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		var solid: Node3D = owning_solid(node)
		if solid != null and not kept.has(solid):
			kept.append(solid)
	if kept == objects:
		return
	objects = kept
	ids = PackedInt64Array()
	active_id = 0
	changed.emit()


func set_editor_objects(nodes: Array) -> void:
	var kept: Array[Node3D] = []
	for node in nodes:
		var solid := editor_owning_solid(node)
		if solid != null and not kept.has(solid):
			kept.append(solid)
	set_objects(kept)


func set_ids(value: PackedInt64Array) -> void:
	if value == ids:
		return
	ids = value
	active_id = ids[ids.size() - 1] if not ids.is_empty() else 0
	changed.emit()


func restore_ids_for(target: Node3D, target_mode: int, value: PackedInt64Array) -> void:
	# Undoing a mesh edit must not put its handles onto another selected solid.
	if solid == target and mode == target_mode:
		set_ids(value)


func toggle_id(id: int, additive: bool) -> void:
	if not additive:
		set_ids(PackedInt64Array([id]) if id != 0 else PackedInt64Array())
		return
	var next := PackedInt64Array(ids)
	var at := next.find(id)
	if at == -1:
		next.append(id)
	else:
		next.remove_at(at)
	set_ids(next)


func clear_ids() -> void:
	set_ids(PackedInt64Array())


func set_hover(next_solid: Variant, next_id: int) -> void:
	var solid: Node3D = null
	if next_solid != null and is_instance_valid(next_solid) and next_solid is Node3D:
		solid = next_solid
	var id: int = next_id if solid != null else 0
	if hover_solid != null and not is_instance_valid(hover_solid):
		hover_solid = null
		hover_id = 0
	if hover_solid == solid and hover_id == id:
		return
	hover_solid = solid
	hover_id = id
	hover_changed.emit()


func count() -> int:
	return objects.size() if mode == Mode.OBJECT else ids.size()


func has_only_external_meshes() -> bool:
	drop_invalid()
	if objects.is_empty():
		return false
	for obj in objects:
		if obj != null and is_instance_valid(obj) and is_solid(obj):
			return false
	return true


func has_any_external_mesh() -> bool:
	drop_invalid()
	for obj in objects:
		if obj != null and is_instance_valid(obj) and is_external_mesh(obj):
			return true
	return false


func first_external_mesh() -> Node3D:
	drop_invalid()
	for obj in objects:
		if obj != null and is_instance_valid(obj) and is_external_mesh(obj):
			return obj
	return null


func mode_label() -> String:
	return MODE_LABELS[mode]


func describe() -> String:
	drop_invalid()
	if objects.is_empty():
		return "No solid selected."
	if mode == Mode.OBJECT:
		if objects.size() == 1:
			var obj: Node3D = objects[0]
			if is_external_mesh(obj):
				return "%s (External mesh) selected." % obj.name
			return "%s selected." % obj.name
		var external_count: int = 0
		for obj in objects:
			if is_external_mesh(obj):
				external_count += 1
		if external_count == objects.size():
			return "%d external meshes selected." % objects.size()
		if external_count > 0:
			return "%d objects selected (%d external)." % [objects.size(), external_count]
		return "%d solids selected." % objects.size()
	var nouns: Array = MODE_NOUNS[mode]
	var who: String = objects[0].name
	if ids.is_empty():
		var article := "an" if mode == Mode.EDGE else "a"
		return "%s · Click %s %s in the viewport to select it." % [who, article, nouns[0]]
	var noun: String = nouns[0] if ids.size() == 1 else nouns[1]
	return "%s, %d %s." % [who, ids.size(), noun]


func compact_description() -> String:
	drop_invalid()
	if objects.is_empty():
		return "No solid selected"
	if objects.size() > 1:
		var external_count: int = 0
		for obj in objects:
			if is_external_mesh(obj):
				external_count += 1
		if external_count == objects.size():
			return "%d external meshes" % objects.size()
		if external_count > 0:
			return "%d objects (%d external)" % [objects.size(), external_count]
		return "%d solids selected" % objects.size()
	var who: String = objects[0].name
	if mode == Mode.OBJECT:
		if is_external_mesh(objects[0]):
			return "%s (External mesh)" % who
		return who
	var nouns: Array = MODE_NOUNS[mode]
	if ids.is_empty():
		return "No %s selected · %s" % [nouns[0], who]
	var noun: String = nouns[0] if ids.size() == 1 else nouns[1]
	return "%d %s · %s" % [ids.size(), noun, who]
