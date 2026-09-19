@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabShapes := preload("res://addons/slab/slab_shapes.gd")
const SlabTopology := preload("res://addons/slab/slab_topology.gd")
const SlabOperationHandles := preload("res://addons/slab/slab_operation_handles.gd")
const SlabKeybindProfiles := preload("res://addons/slab/slab_keybind_profiles.gd")

signal reported(text: String)
signal status_reset_requested
signal operation_requested(kind: int)
signal operation_amount_changed(value: float)
signal operation_segments_changed(value: int)
signal operation_apply_requested
signal operation_cancel_requested
signal operation_state_changed
signal op_session_started(op_id: String, title: String, fields: Array)
signal op_session_updated(op_id: String, values: Dictionary, apply_enabled: bool)
signal op_session_ended(op_id: String, reason: String)
var operation_active := false
var operation_amount := 0.5
var _op_session_id := ""
var _op_session_apply_enabled := true
signal loop_requested
signal loop_settings_changed
signal loop_values_updated
signal loop_state_changed
signal loop_apply_requested
signal loop_cancel_requested
signal plane_requested
signal plane_settings_changed
signal plane_state_changed
signal plane_apply_requested
signal plane_cancel_requested
signal array_requested
signal array_settings_changed
signal array_state_changed
signal array_apply_requested
signal array_cancel_requested
signal snap_vertex_requested
signal align_face_requested
signal snap_align_settings_changed
signal snap_align_state_changed
signal snap_align_cancel_requested
signal object_order_changed(nodes: Array)
signal create_placement_requested(row: Dictionary, plan: Dictionary)
signal create_settings_changed

const SECTION_CREATE := "Create"
const SECTION_SELECTION := "Selection"
const SECTION_UV := "UV"
const SECTION_ORDER: Array = [SECTION_CREATE, "Object", "Vertex", "Edge", "Face", SECTION_SELECTION]

const BOOLEAN_UNION := 0
const BOOLEAN_SUBTRACT := 1
const BOOLEAN_INTERSECT := 2
const ARRAY_LINEAR := 0
const ARRAY_RADIAL := 1
const SNAP_NONE := 0
const SNAP_VERTEX := 1
const SNAP_FACE := 2

const AMOUNT_FLOOR := 0.05
const AMOUNT_CEILING := 64.0
const EXTRUDE_FLOOR := -64.0

const ERR_STALE_HANDLE := 1
const ERR_NOT_CLOSED := 2
const ERR_TWIN_MISMATCH := 3
const ERR_NON_MANIFOLD_VERTEX := 4
const ERR_DEGENERATE_FACE := 5
const ERR_LOOP_TOO_SHORT := 6
const ERR_INCONSISTENT_ORIENTATION := 7
const ERR_INVERTED_VOLUME := 8
const ERR_RESULT_EMPTY := 9
const ERR_COORD_OUT_OF_RANGE := 10
const ERR_ADJACENT_SELECTION := 11
const ERR_SNAP_COLLAPSED_TOPOLOGY := 12
const ERR_NO_INTERSECTION := 13
const ERR_CORRUPT_DATA := 14
const ERR_INVALID_SELECTION := 15
const ERR_SELF_INTERSECTION := 16
const ERR_MULTIPLE_BOUNDARY_LOOPS := 17

var loop_count: int = 1
var loop_position: float = 0.5
var loop_active: bool = false
var loop_can_apply: bool = false
var plane_normal := Vector3.RIGHT
var plane_offset: float = 1.0
var plane_keep_positive: bool = false
var plane_cap_material: int = 0
var plane_active: bool = false
var array_active: bool = false
var array_mode: int = ARRAY_LINEAR
var array_count: int = 2
var array_linear_step := Vector3(2, 0, 0)
var array_radial_center := Vector3.ZERO
var array_radial_axis := Vector3.UP
var array_radial_angle_degrees := 45.0
var array_rotate_copies := true
var snap_align_active: bool = false
var snap_align_mode: int = SNAP_NONE
var align_oppose_normals := true
var bevel_segments: int = 1

var amount: float = 0.5
var extrude_amount: float = 0.5
var inset_amount: float = 0.5
var bevel_amount: float = 0.5
var uv_scale := Vector2.ONE
var uv_offset := Vector2.ZERO
var uv_rotation_degrees: float = 0.0
var uv_pixels_per_meter: float = 256.0
var uv_texture_resolution: int = 1024
var material_slot: int = 0

var shapes: RefCounted
var keybind_profiles: RefCounted

var _selection: RefCounted
var _undo: Object
var _rows: Array[Dictionary] = []


func operation_amount_for(kind: int) -> float:
	match kind:
		SlabOperationHandles.Kind.EXTRUDE: return extrude_amount
		SlabOperationHandles.Kind.INSET: return inset_amount
		SlabOperationHandles.Kind.BEVEL: return bevel_amount
	return extrude_amount


func remember_operation_amount(kind: int, value: float) -> void:
	match kind:
		SlabOperationHandles.Kind.EXTRUDE: extrude_amount = value
		SlabOperationHandles.Kind.INSET: inset_amount = value
		SlabOperationHandles.Kind.BEVEL: bevel_amount = value


const OP_SESSION_IDS: Array[String] = ["extrude", "inset", "bevel"]
const OP_SESSION_TITLES: Array[String] = ["Extrude", "Inset", "Bevel"]


func _op_session_kind_to_id(kind: int) -> String:
	if kind >= 0 and kind < OP_SESSION_IDS.size():
		return OP_SESSION_IDS[kind]
	return ""


func _op_session_id_to_kind(op_id: String) -> int:
	return OP_SESSION_IDS.find(op_id)


func op_session_fields_for(op_id: String) -> Array:
	match op_id:
		"extrude":
			return [{"id": "distance", "label": "Distance", "type": "float", "suffix": "m", "min": EXTRUDE_FLOOR, "max": AMOUNT_CEILING, "step": 0.001}]
		"inset":
			return [{"id": "distance", "label": "Distance", "type": "float", "suffix": "m", "min": AMOUNT_FLOOR, "max": AMOUNT_CEILING, "step": 0.001}]
		"bevel":
			return [
				{"id": "distance", "label": "Width", "type": "float", "suffix": "m", "min": AMOUNT_FLOOR, "max": AMOUNT_CEILING, "step": 0.001},
				{"id": "segments", "label": "Segments", "type": "int", "min": 1, "max": 16, "step": 1}
			]
	return []


func op_session_active() -> bool:
	return operation_active and _op_session_id != ""


func op_session_id() -> String:
	return _op_session_id if operation_active else ""


func op_session_title() -> String:
	var kind := _op_session_id_to_kind(_op_session_id)
	if kind >= 0 and kind < OP_SESSION_TITLES.size():
		return OP_SESSION_TITLES[kind]
	return ""


func op_session_fields() -> Array:
	return op_session_fields_for(_op_session_id)


func op_session_values() -> Dictionary:
	if not operation_active:
		return {}
	match _op_session_id:
		"extrude": return {"distance": operation_amount}
		"inset": return {"distance": operation_amount}
		"bevel": return {"distance": operation_amount, "segments": bevel_segments}
	return {}


func op_session_apply_enabled() -> bool:
	return _op_session_apply_enabled


func op_session_remembered(op_id: String) -> Dictionary:
	match op_id:
		"extrude": return {"distance": extrude_amount}
		"inset": return {"distance": inset_amount}
		"bevel": return {"distance": bevel_amount, "segments": bevel_segments}
	return {}


func op_session_set_value(field_id: String, value: Variant) -> void:
	if not operation_active:
		return
	match field_id:
		"distance":
			operation_amount_changed.emit(float(value))
		"segments":
			operation_segments_changed.emit(int(value))


func op_session_apply() -> void:
	if not operation_active or not _op_session_apply_enabled:
		return
	operation_apply_requested.emit()


func op_session_cancel() -> void:
	if not operation_active:
		return
	operation_cancel_requested.emit()


func notify_op_session_start(kind: int) -> void:
	_op_session_id = _op_session_kind_to_id(kind)
	_op_session_apply_enabled = true
	if _op_session_id != "":
		var title := op_session_title()
		var fields: Array = op_session_fields()
		op_session_started.emit(_op_session_id, title, fields)


func notify_op_session_update(apply_enabled: bool) -> void:
	if _op_session_id == "":
		return
	_op_session_apply_enabled = apply_enabled
	var values: Dictionary = op_session_values()
	op_session_updated.emit(_op_session_id, values, apply_enabled)


func notify_op_session_end(reason: String) -> void:
	if _op_session_id == "":
		return
	var ended_id := _op_session_id
	_op_session_id = ""
	_op_session_apply_enabled = true
	op_session_ended.emit(ended_id, reason)


func swap_boolean_operands() -> void:
	if _selection.mode != SlabSelection.Mode.OBJECT or _selection.objects.size() != 2:
		_report("Swap operands needs exactly two solids in Object mode.")
		return
	var swapped: Array[Node3D] = [_selection.objects[1], _selection.objects[0]]
	_selection.set_objects(swapped)
	object_order_changed.emit(swapped)
	_report("Boolean target: %s · Operand: %s." % [swapped[0].name, swapped[1].name])


func _init(selection: RefCounted = null, undo: Object = null) -> void:
	_selection = selection if selection != null else SlabSelection.new()
	_undo = undo
	shapes = SlabShapes.new()
	keybind_profiles = SlabKeybindProfiles.new()
	_rows = _build()


func rows() -> Array[Dictionary]:
	return _rows


func find(id: String) -> Dictionary:
	for row in _rows:
		if row["id"] == id:
			return row
	return {}


# Each element is { "heading": String, "rows": Array[Dictionary], "fields": Array[Dictionary] }.
# "fields" is shapes.fields() on Create and empty elsewhere. Headings with no rows are omitted.
func command_sections_for(mode: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not SlabSelection.MODE_LABELS.has(mode):
		push_error("Unknown mode %d." % mode)
		return out
	for heading in SECTION_ORDER:
		var rows: Array[Dictionary] = []
		for row in _rows:
			if row["modes"].has(mode) and section_of(row) == heading:
				rows.append(row)
		if rows.is_empty():
			continue
		var fields: Array[Dictionary] = []
		if heading == SECTION_CREATE:
			fields = []
		out.append({ "heading": heading, "rows": rows, "fields": fields })
	return out


static func section_of(row: Dictionary) -> String:
	var id: String = str(row.get("id", ""))
	if id.begins_with("uv_") or id == "set_face_material":
		return SECTION_UV
	var modes: Array = row["modes"]
	if id == "bevel_edges":
		return "Edge"
	if modes.size() > 1:
		return SECTION_SELECTION
	if modes[0] == SlabSelection.Mode.OBJECT and row["min_count"] == 0:
		return SECTION_CREATE
	return SlabSelection.MODE_LABELS[modes[0]]


func disabled_reason(row: Dictionary) -> String:
	if operation_active:
		return "Apply or cancel the current preview first."
	var modes: Array = row["modes"]
	if not modes.has(_selection.mode):
		return "%s needs %s mode." % [row["label"], _mode_list(modes)]
	var exact: int = row.get("exact_count", 0)
	if exact > 0 and _selection.count() != exact:
		return "%s needs exactly %s." % [row["label"], _element_count(_selection.mode, exact)]
	var need: int = row["min_count"]
	if _selection.count() < need:
		return "%s needs %s." % [row["label"], _element_count(_selection.mode, need)]
	return ""


func tooltip_of(row: Dictionary) -> String:
	var live: String = shapes.describe(row["id"])
	return row["tooltip"] if live == "" else "%s %s" % [row["tooltip"], live]


func run(id: String) -> void:
	var row := find(id)
	if row.is_empty():
		return
	var blocked := disabled_reason(row)
	if blocked != "":
		_report(blocked)
		return
	_apply(row, row["handler"].call())


func request_create_placement(id: StringName) -> void:
	var row := find(String(id))
	if row.is_empty() or section_of(row) != SECTION_CREATE:
		return
	var plan: Dictionary = row["handler"].call()
	if plan.has("status"):
		_report(plan["status"])
		return
	create_placement_requested.emit(row, plan)


func run_shortcut(keycode: int) -> bool:
	for row in _rows:
		var active_shortcut: int = shortcut_of(row)
		if active_shortcut == 0 or active_shortcut != keycode or disabled_reason(row) != "":
			continue
		_apply(row, row["handler"].call())
		return true
	return false


func shortcut_of(row: Dictionary) -> int:
	var id: String = str(row.get("id", ""))
	if id == "":
		return int(row.get("shortcut", 0))
	var profile_shortcut: int = keybind_profiles.shortcut_for(id)
	if profile_shortcut != 0:
		return profile_shortcut
	return int(row.get("shortcut", 0))


func _apply(row: Dictionary, plan: Dictionary) -> void:
	if plan.has("preview"):
		operation_requested.emit(plan["preview"])
		return
	if plan.has("status"):
		_report(plan["status"])
		return

	var created: bool = plan.has("create")
	var target: Node3D = _instantiate_solid(plan["create"]) if created else _selection.solid
	if target == null:
		_report("SlabSolid is not built yet." if created else "No solid selected.")
		return

	var method: String = plan.get("method", "")
	if method != "" and not target.has_method(method):
		if created:
			target.free()
		_report("%s is not built yet." % row["label"])
		return

	if plan.has("run"):
		_report(plan["run"].call(target))
		return

	if created:
		_create_solid(row, target, method, plan["args"])
		return

	_edit_solid(row, target, method, plan["args"])


func _edit_solid(row: Dictionary, target: Node3D, method: String, args: Array) -> void:
	var before: PackedByteArray = target.get("data")
	var before_ids := PackedInt64Array(_selection.ids)
	var before_elements := SlabTopology.all_ids(target, _selection.mode) if method in ["subdivide_faces", "merge_faces", "connect_edges"] else PackedInt64Array()
	var err: int = target.callv(method, args)
	if err != OK:
		_report("%s failed. %s" % [row["label"], describe_error(err, row["id"])])
		return
	var after: PackedByteArray = target.get("data")
	if after == before:
		_report("%s did not change the solid." % row["label"])
		return
	var after_ids := before_ids
	if method in ["subdivide_faces", "merge_faces", "dissolve_edges", "collapse_vertices", "weld_vertices", "connect_edges", "connect_vertices"]:
		var alive := SlabTopology.all_ids(target, _selection.mode)
		after_ids = PackedInt64Array()
		for id in before_ids:
			if method != "connect_edges" and alive.has(id): after_ids.append(id)
		if method in ["subdivide_faces", "merge_faces", "connect_edges"]:
			for id in alive:
				if not before_elements.has(id): after_ids.append(id)
	if before_ids.size() > 1 and (method == "extrude_faces" or method == "inset_faces"):
		after_ids = PackedInt64Array(target.call("get_last_edited_faces"))
	_selection.set_ids(after_ids)
	if _undo != null:
		_undo.create_action("Slab %s" % row["label"], UndoRedo.MERGE_DISABLE, target)
		_undo.add_do_property(target, "data", after)
		_undo.add_undo_property(target, "data", before)
		if after_ids != before_ids:
			_undo.add_do_method(_selection, "restore_ids_for", target, _selection.mode, after_ids)
			_undo.add_undo_method(_selection, "restore_ids_for", target, _selection.mode, before_ids)
		_undo.commit_action(false)
	_report("%s applied. %s now has %d faces." % [row["label"], target.name, int(target.call("face_count"))])


func _create_solid(row: Dictionary, target: Node3D, method: String, args: Array) -> void:
	var err: int = target.callv(method, args)
	if err != OK:
		target.free()
		_report("%s failed. %s" % [row["label"], describe_error(err, row["id"])])
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		target.free()
		_report("Open a scene before creating a solid.")
		return
	var parent: Node = _create_parent(root)
	if _undo == null:
		target.free()
		_report("Undo is not available.")
		return
	_undo.create_action("Slab %s" % row["label"], UndoRedo.MERGE_DISABLE, root)
	_undo.add_do_method(parent, "add_child", target, true)
	_undo.add_do_method(target, "set_owner", root)
	_undo.add_do_reference(target)
	_undo.add_undo_method(parent, "remove_child", target)
	_undo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(target)
	_report("%s created." % row["label"])


func commit_placed_create(row: Dictionary, target: Node3D, parent: Node, transform: Transform3D) -> void:
	if target == null or not is_instance_valid(target) or parent == null or not is_instance_valid(parent):
		if target != null: target.free()
		_report("Create failed because the scene changed during placement.")
		return
	target.transform = transform
	var root := EditorInterface.get_edited_scene_root()
	if root == null or _undo == null:
		target.free()
		_report("Create failed because the scene or Undo history is unavailable.")
		return
	_undo.create_action("Slab %s" % row["label"], UndoRedo.MERGE_DISABLE, root)
	_undo.add_do_method(parent, "add_child", target, true)
	_undo.add_do_method(target, "set_owner", root)
	_undo.add_do_reference(target)
	_undo.add_undo_method(parent, "remove_child", target)
	_undo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(target)
	_report("%s created." % row["label"])


func _create_parent(root: Node) -> Node:
	var current: Node3D = _selection.solid
	if current != null and current.get_parent() != null:
		return current.get_parent()
	return root


func _instantiate_solid(node_name: String) -> Node3D:
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		return null
	var node := ClassDB.instantiate(SlabSelection.SOLID_CLASS) as Node3D
	if node == null:
		return null
	node.name = node_name
	return node


func _report(text: String) -> void:
	if text != "":
		reported.emit(text)


func _mode_list(modes: Array) -> String:
	var names: Array[String] = []
	for mode in modes:
		names.append(SlabSelection.MODE_LABELS[mode])
	if names.size() == 1:
		return names[0]
	var last: String = names.pop_back()
	return "%s or %s" % [", ".join(names), last]


func _element_count(mode: int, need: int) -> String:
	var nouns: Array = SlabSelection.MODE_NOUNS[mode]
	return "%d %s" % [need, nouns[0] if need == 1 else nouns[1]]


func _ids_op(method: String) -> Dictionary:
	return { "method": method, "args": [_selection.ids] }


func _seam_op(marked: bool) -> Dictionary:
	return { "method": "mark_uv_seams", "args": [_selection.ids, marked] }


func _unwrap_op() -> Dictionary:
	return { "run": _unwrap_target }


func _operation_op(kind: int) -> Dictionary:
	return { "preview": kind }


func _positive_amount() -> float:
	return maxf(absf(amount), AMOUNT_FLOOR)


func _positive_amount_op(method: String) -> Dictionary:
	return { "method": method, "args": [_selection.ids, _positive_amount()] }


func clamp_material_slot() -> void:
	var target: Node3D = _selection.solid
	if target == null:
		material_slot = 0
		return
	var n: int = (target.get("materials") as Array).size()
	if n <= 0:
		material_slot = 0
	else:
		material_slot = clampi(material_slot, 0, n - 1)


static func describe_error(code: int, action_id: String = "") -> String:
	if action_id == "bevel_edges" and code == ERR_NON_MANIFOLD_VERTEX:
		return "This edge arrangement is not supported by Bevel. Try one edge, a simple perimeter, or three edges meeting at one corner."
	if action_id == "merge_faces" and code == ERR_MULTIPLE_BOUNDARY_LOOPS:
		return "These faces surround an opening. Merge a smaller region that does not surround the opening."
	if action_id == "subdivide_faces" and code == ERR_ADJACENT_SELECTION:
		return "Selected faces share an edge. Subdivide separate faces in this operation."
	if action_id in ["connect_vertices", "connect_edges"] and code in [ERR_INVALID_SELECTION, ERR_ADJACENT_SELECTION]:
		return "Choose two elements on one face with endpoints that are not already joined."
	if action_id in ["merge_faces", "dissolve_edges"] and code in [ERR_INVALID_SELECTION, ERR_DEGENERATE_FACE]:
		return "Choose a connected region on one flat surface. Folded or disconnected faces cannot merge."
	if code == ERR_NOT_CLOSED and action_id == "delete_faces":
		return "Deleting this face would leave an open solid. Inset, then extrude the inner cap to hollow a room, or Subtract a second solid to cut a hole."
	if code == ERR_SELF_INTERSECTION:
		if action_id == "extrude_faces":
			return "The extrusion would cross another face. Inset before extruding inward, and stop before the opposite wall."
		return "Faces in the result would cross or overlap. Reduce the edit or move the intersecting parts apart."
	match code:
		ERR_STALE_HANDLE:
			return "That handle is stale. Select the solid again."
		ERR_NOT_CLOSED:
			return "The result would not be a closed solid."
		ERR_TWIN_MISMATCH:
			return "An edge does not meet its twin."
		ERR_NON_MANIFOLD_VERTEX:
			return "Surfaces would meet only at a pinched vertex. Keep a continuous wall around each vertex."
		ERR_DEGENERATE_FACE:
			return "A face would collapse to a line or point. Use a smaller edit or leave more space between vertices."
		ERR_LOOP_TOO_SHORT:
			return "A face would have fewer than three distinct corners. Keep enough corners to enclose an area."
		ERR_INCONSISTENT_ORIENTATION:
			return "Neighbouring faces disagree on direction."
		ERR_INVERTED_VOLUME:
			return "The solid would turn inside out."
		ERR_RESULT_EMPTY:
			return "The result would be empty."
		ERR_COORD_OUT_OF_RANGE:
			return "A value is outside the allowed range."
		ERR_ADJACENT_SELECTION:
			return "That selection shares an edge or repeats an element."
		ERR_SNAP_COLLAPSED_TOPOLOGY:
			return "Welding those vertices would pinch the solid."
		ERR_NO_INTERSECTION:
			return "Those pieces do not meet."
		ERR_CORRUPT_DATA:
			return "The stored mesh is corrupt."
		ERR_INVALID_SELECTION:
			return "That selection cannot run this command."
		ERR_MULTIPLE_BOUNDARY_LOOPS:
			return "The selected region has more than one boundary."
		_:
			return "Mesh error %d." % code


func _solid_op(method: String) -> Dictionary:
	return { "method": method, "args": [] }


func _uv_op() -> Dictionary:
	return { "method": "set_face_uv", "args": [_selection.ids, uv_scale, uv_offset, deg_to_rad(uv_rotation_degrees)] }


func _uv_scaled(factor: float) -> Dictionary:
	uv_scale = Vector2(clampf(uv_scale.x * factor, 0.05, 64.0), clampf(uv_scale.y * factor, 0.05, 64.0))
	return _uv_op()


func _uv_turned(degrees: float) -> Dictionary:
	uv_rotation_degrees = fposmod(uv_rotation_degrees + degrees, 360.0)
	return _uv_op()


func _uv_cleared() -> Dictionary:
	uv_scale = Vector2.ONE
	uv_offset = Vector2.ZERO
	uv_rotation_degrees = 0.0
	return _uv_op()


func _material_op() -> Dictionary:
	return { "method": "set_face_material", "args": [_selection.ids, material_slot] }


func _loop_op() -> Dictionary:
	loop_requested.emit()
	return { "status": "" }


func _boolean_op(mode: int) -> Dictionary:
	return { "method": "boolean_with", "args": [_selection.objects[1], mode] }


func _plane_op() -> Dictionary:
	plane_requested.emit()
	return { "status": "Plane Cut: set a local-space normal and offset, preview the capped result, then Apply or press Enter." }


func _array_op() -> Dictionary:
	array_requested.emit()
	return { "status": "Array: set exact linear spacing or radial centre, axis, and angle. Enter or Apply confirms; Escape cancels." }


func _snap_vertex_op() -> Dictionary:
	snap_vertex_requested.emit()
	return { "status": "Snap to Vertex: the highlighted source vertex will land on the target vertex you click. Escape cancels." }


func _align_face_op() -> Dictionary:
	align_face_requested.emit()
	return { "status": "Align Face: point at a face on another solid, preview the rigid placement, then click to apply. Escape cancels." }


func _mirror_op(axis: Vector3) -> Dictionary:
	return { "method": "mirror", "args": [axis] }


func _select_op(pick: Callable) -> Dictionary:
	return { "method": SlabTopology.query_for(_selection.mode), "run": pick }


func _pick_all(target: Node3D) -> String:
	_selection.set_ids(SlabTopology.all_ids(target, _selection.mode))
	return _selection.describe()


func _pick_none(_target: Node3D) -> String:
	_selection.clear_ids()
	return _selection.describe()


func _pick_inverted(target: Node3D) -> String:
	_selection.set_ids(SlabTopology.invert(target, _selection.mode, _selection.ids))
	return _selection.describe()


func _pick_grown(target: Node3D) -> String:
	_selection.set_ids(SlabTopology.grow(target, _selection.mode, _selection.ids))
	return _selection.describe()


func _pick_coplanar(target: Node3D) -> String:
	_selection.set_ids(SlabTopology.connected_coplanar_faces(target, _selection.ids))
	return _selection.describe()


func _select_face_boundary(target: Node3D) -> String:
	var selected_faces := PackedInt64Array(_selection.ids)
	var boundary := PackedInt64Array()
	for edge in PackedInt64Array(target.call("get_edges")):
		var selected_incidents := 0
		for face in PackedInt64Array(target.call("edge_faces", edge)):
			if selected_faces.has(face): selected_incidents += 1
		if selected_incidents == 1: boundary.append(edge)
	_selection.mode = SlabSelection.Mode.EDGE
	_selection.set_ids(boundary)
	if boundary.is_empty():
		return "The selected faces have no boundary edges."
	return "Selected %d boundary %s." % [boundary.size(), "edge" if boundary.size() == 1 else "edges"]


func _pick_loop(target: Node3D) -> String:
	_selection.set_ids(SlabTopology.edge_loop(target, _selection.ids[0]))
	return _selection.describe()


func _pick_ring(target: Node3D) -> String:
	_selection.set_ids(SlabTopology.edge_ring(target, _selection.ids[0]))
	return _selection.describe()


func _unwrap_target(target: Node3D) -> String:
	var before: PackedByteArray = target.get("data")
	var result: Dictionary = target.call("unwrap_uv", _selection.ids, uv_pixels_per_meter, uv_texture_resolution)
	if bool(result.get("atlas_overflow", false)):
		var suggested: int = int(result.get("suggested_texture_resolution", uv_texture_resolution * 2))
		return "Unwrap atlas is too small. Lower Pixels / metre or raise Texture px to at least %d. The solid was unchanged." % suggested
	var err: int = int(result.get("error", ERR_INVALID_SELECTION))
	if err != OK:
		return "Unwrap failed. %s" % describe_error(err, "uv_unwrap")
	var after: PackedByteArray = target.get("data")
	uv_scale = Vector2.ONE
	uv_offset = Vector2.ZERO
	uv_rotation_degrees = 0.0
	if _undo != null and after != before:
		_undo.create_action("Slab Unwrap UV", UndoRedo.MERGE_DISABLE, target)
		_undo.add_do_property(target, "data", after)
		_undo.add_undo_property(target, "data", before)
		_undo.commit_action(false)
	var automatic := PackedInt64Array(result.get("auto_seams", PackedInt64Array()))
	return "Unwrapped %d island(s); added %d automatic cut(s)." % [int(result.get("islands", 0)), automatic.size()]


func _row(id: String, label: String, icon: String, modes: Array, min_count: int, tooltip: String, shortcut: int, handler: Callable, exact_count: int = 0) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"icon": icon,
		"modes": modes,
		"min_count": min_count,
		"exact_count": exact_count,
		"tooltip": tooltip,
		"shortcut": shortcut,
		"handler": handler,
	}


func _build() -> Array[Dictionary]:
	var object: Array = [SlabSelection.Mode.OBJECT]
	var vertex: Array = [SlabSelection.Mode.VERTEX]
	var edge: Array = [SlabSelection.Mode.EDGE]
	var face: Array = [SlabSelection.Mode.FACE]
	var edge_or_face: Array = [SlabSelection.Mode.EDGE, SlabSelection.Mode.FACE]
	var elements: Array = [SlabSelection.Mode.VERTEX, SlabSelection.Mode.EDGE, SlabSelection.Mode.FACE]

	var table: Array = []
	for entry in shapes.entries():
		table.append(_row(entry["id"], entry["label"], entry["icon"], object, 0, entry["tooltip"], 0, shapes.plan.bind(entry["id"])))
	table.append_array([
		_row("boolean_union", "Union", "CSGCombiner3D", object, 2, "Adds the second solid into the first.", 0, _boolean_op.bind(BOOLEAN_UNION)),
		_row("boolean_subtract", "Subtract", "CSGBox3D", object, 2, "Cuts the second solid out of the first.", 0, _boolean_op.bind(BOOLEAN_SUBTRACT)),
		_row("boolean_intersect", "Intersect", "CSGSphere3D", object, 2, "Keeps only the overlap of two solids.", 0, _boolean_op.bind(BOOLEAN_INTERSECT)),
		_row("plane_cut", "Plane Cut", "PlaneCut", object, 1, "Cuts the solid by an exact local-space plane and closes every section loop with caps.", 0, _plane_op),
		_row("array", "Array", "GridLayout", object, 1, "Previews exact linear or radial copies and creates them as one undo action.", 0, _array_op),
		_row("mirror_x", "Mirror X", "MirrorX", object, 1, "Mirrors the solid across its local X axis.", 0, _mirror_op.bind(Vector3(-1.0, 1.0, 1.0))),
		_row("mirror_y", "Mirror Y", "MirrorY", object, 1, "Mirrors the solid across its local Y axis.", 0, _mirror_op.bind(Vector3(1.0, -1.0, 1.0))),
		_row("mirror_z", "Mirror Z", "Object", object, 1, "Mirrors the solid across its local Z axis.", 0, _mirror_op.bind(Vector3(1.0, 1.0, -1.0))),
		_row("center_pivot", "Center Pivot", "EditorPivot", object, 1, "Moves the origin to the middle of the solid.", 0, _solid_op.bind("center_pivot")),
		_row("snap_to_grid", "Snap To Grid", "SnapGrid", object, 1, "Rounds every vertex onto the grid step.", 0, _solid_op.bind("snap_to_grid")),

		_row("weld_vertices", "Weld", "Snap", vertex, 2, "Merges vertices closer than the amount field.", KEY_J, _positive_amount_op.bind("weld_vertices")),
		_row("collapse_vertices", "Collapse", "Group", vertex, 2, "Collapses the selection to one vertex.", KEY_Y, _ids_op.bind("collapse_vertices")),
		_row("connect_vertices", "Connect", "CurveLinear", vertex, 2, "Splits a shared face between two non-adjacent vertices.", KEY_K, _ids_op.bind("connect_vertices"), 2),

		_row("bevel_edges", "Bevel", "ToolRotate", edge_or_face, 1, "Previews a rounded bevel on selected edges, or on the perimeter of selected faces.", KEY_B, _operation_op.bind(2)),
		_row("connect_edges", "Connect", "CurveOut", edge, 2, "Splits the shared face between the nearest pair of non-adjacent edge endpoints.", KEY_K, _ids_op.bind("connect_edges"), 2),
		_row("insert_loop", "Loop Cut", "AnimationTrackGroup", edge, 0, "Preview loop cuts, then slide or type a percentage. Wheel changes the cut count. Enter confirms; Escape cancels.", KEY_L, _loop_op),
		_row("dissolve_edges", "Dissolve", "Remove", edge, 1, "Removes coplanar internal edges and merges their adjacent faces.", KEY_X, _ids_op.bind("dissolve_edges")),
		_row("mark_uv_seam", "Mark Seam", "MaterialPreviewCube", edge, 1, "Marks selected edges as UV island boundaries.", 0, _seam_op.bind(true)),
		_row("clear_uv_seam", "Clear Seam", "Save", edge, 1, "Removes UV seam marks from selected edges.", 0, _seam_op.bind(false)),

		_row("extrude_faces", "Extrude", "ToolMove", face, 1, "Pulls one face along its normal, or a connected face region in one shared direction. Positive is outward. Negative is inward.", KEY_E, _operation_op.bind(0)),
		_row("inset_faces", "Inset", "ToolScale", face, 1, "Shrinks one face, or one connected coplanar face region, inside its shared boundary.", KEY_I, _operation_op.bind(1)),
		_row("subdivide_faces", "Subdivide", "GridLayout", face, 1, "Splits each selected face into one quad per corner. Selected faces cannot share an edge.", KEY_U, _ids_op.bind("subdivide_faces")),
		_row("merge_faces", "Merge", "GroupViewport", face, 2, "Joins one connected coplanar face region into a single face.", KEY_M, _ids_op.bind("merge_faces")),
		_row("select_coplanar", "Select Coplanar", "PlaneMesh", face, 1, "Selects every connected face on the same plane as the current face selection.", 0, _select_op.bind(_pick_coplanar)),
		_row("select_boundary", "Select Boundary", "Path3D", face, 1, "Switches to Edge mode and selects the perimeter edges of the selected faces.", 0, _select_op.bind(_select_face_boundary)),
		_row("align_face", "Align Face", "SnapGrid", face, 1, "Moves the solid so the selected face centre and normal align to a face you click on another solid.", 0, _align_face_op),
		_row("set_face_material", "Set Material", "StandardMaterial3D", face, 1, "Assigns the active material to the faces.", 0, _material_op),
		_row("uv_apply", "Apply UV", "ImageTexture", face, 1, "Writes the UV scale, offset and rotation fields.", 0, _uv_op),
		_row("uv_scale_up", "Repeat ×2", "ZoomMore", face, 1, "Doubles the UV scale and applies it.", 0, _uv_scaled.bind(2.0)),
		_row("uv_scale_down", "Repeat ÷2", "ZoomLess", face, 1, "Halves the UV scale and applies it.", 0, _uv_scaled.bind(0.5)),
		_row("uv_rotate", "UV Rotate", "ToolRotate", face, 1, "Turns the UV by ninety degrees.", 0, _uv_turned.bind(90.0)),
		_row("uv_reset", "UV Reset", "Reload", face, 1, "Returns the UV to scale one and no rotation.", 0, _uv_cleared),
		_row("uv_unwrap", "Unwrap", "ArrayMesh", face, 1, "Unfolds the selected face region into scaled UV islands using marked and automatic seams.", 0, _unwrap_op),

		_row("select_all", "Select All", "ListSelect", elements, 0, "Selects every element in the current mode.", KEY_A, _select_op.bind(_pick_all)),
		_row("select_none", "Select None", "Clear", elements, 1, "Clears the element selection.", KEY_D, _select_op.bind(_pick_none)),
		_row("select_invert", "Invert", "Duplicate", elements, 1, "Swaps selected elements for unselected ones.", 0, _select_op.bind(_pick_inverted)),
		_row("select_grow", "Grow", "Add", elements, 1, "Adds the neighbours of the selection.", 0, _select_op.bind(_pick_grown)),
		_row("snap_vertex", "Snap to Vertex", "Curve3D", elements, 1, "Moves selected element vertices so the highlighted source vertex coincides with a target vertex on another solid.", 0, _snap_vertex_op),
		_row("select_loop", "Select Loop", "Path3D", edge, 1, "Follows the edge loop around the solid.", 0, _select_op.bind(_pick_loop)),
		_row("select_ring", "Select Ring", "AnimationTrackList", edge, 1, "Follows the parallel edges across quads.", 0, _select_op.bind(_pick_ring)),
	])
	var out: Array[Dictionary] = []
	out.assign(table)
	return out
