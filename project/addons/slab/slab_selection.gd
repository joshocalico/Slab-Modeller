@tool
extends RefCounted

signal changed
signal hover_changed

enum Mode { OBJECT, VERTEX, EDGE, FACE }

const SOLID_CLASS := "SlabSolid"

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
		ids = PackedInt64Array()
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

var hover_solid: Node3D = null

var hover_id: int = 0

var solid: Node3D:
	get:
		return objects[0] if not objects.is_empty() else null
	set(value):
		set_objects([value] if value != null else [])


static func is_solid(node: Object) -> bool:
	return node != null and is_instance_valid(node) and node.is_class(SOLID_CLASS)


static func owning_solid(node: Object) -> Node3D:
	if node == null or not is_instance_valid(node):
		return null
	var current: Node = node as Node
	while current != null:
		if is_solid(current):
			return current
		current = current.get_parent()
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
	changed.emit()


func set_ids(value: PackedInt64Array) -> void:
	if value == ids:
		return
	ids = value
	changed.emit()


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


func mode_label() -> String:
	return MODE_LABELS[mode]


func describe() -> String:
	drop_invalid()
	if objects.is_empty():
		return "No solid selected."
	if mode == Mode.OBJECT:
		if objects.size() == 1:
			return "%s selected." % objects[0].name
		return "%d solids selected." % objects.size()
	var nouns: Array = MODE_NOUNS[mode]
	var who: String = objects[0].name
	if ids.is_empty():
		return "%s, %s mode, none selected." % [who, mode_label()]
	var noun: String = nouns[0] if ids.size() == 1 else nouns[1]
	return "%s, %d %s." % [who, ids.size(), noun]
