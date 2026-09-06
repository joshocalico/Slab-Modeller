@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabShapes := preload("res://addons/slab/slab_shapes.gd")
const SlabTopology := preload("res://addons/slab/slab_topology.gd")

signal reported(text: String)

const SECTION_CREATE := "Create"
const SECTION_SELECTION := "Selection"
const SECTION_ORDER: Array = [SECTION_CREATE, "Object", "Vertex", "Edge", "Face", SECTION_SELECTION]

const BOOLEAN_UNION := 0
const BOOLEAN_SUBTRACT := 1
const BOOLEAN_INTERSECT := 2

var amount: float = 0.5
var uv_scale := Vector2.ONE
var uv_offset := Vector2.ZERO
var uv_rotation_degrees: float = 0.0
var material_slot: int = 0

var shapes: RefCounted

var _selection: RefCounted
var _undo: EditorUndoRedoManager
var _rows: Array[Dictionary] = []


func _init(selection: RefCounted = null, undo: EditorUndoRedoManager = null) -> void:
	_selection = selection if selection != null else SlabSelection.new()
	_undo = undo
	shapes = SlabShapes.new()
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
			fields = shapes.fields()
		out.append({ "heading": heading, "rows": rows, "fields": fields })
	return out


static func section_of(row: Dictionary) -> String:
	var modes: Array = row["modes"]
	if modes.size() > 1:
		return SECTION_SELECTION
	if modes[0] == SlabSelection.Mode.OBJECT and row["min_count"] == 0:
		return SECTION_CREATE
	return SlabSelection.MODE_LABELS[modes[0]]


func disabled_reason(row: Dictionary) -> String:
	var modes: Array = row["modes"]
	if not modes.has(_selection.mode):
		return "%s needs %s mode." % [row["label"], _mode_list(modes)]
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


func run_shortcut(keycode: int) -> bool:
	for row in _rows:
		if row["shortcut"] != keycode or disabled_reason(row) != "":
			continue
		_apply(row, row["handler"].call())
		return true
	return false


func _apply(row: Dictionary, plan: Dictionary) -> void:
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
	var err: int = target.callv(method, args)
	if err != OK:
		_report("%s failed. Mesh error %d." % [row["label"], err])
		return
	var after: PackedByteArray = target.get("data")
	_undo.create_action("Slab %s" % row["label"], UndoRedo.MERGE_DISABLE, target)
	_undo.add_do_property(target, "data", after)
	_undo.add_undo_property(target, "data", before)
	_undo.commit_action(false)
	_report(_selection.describe())


func _create_solid(row: Dictionary, target: Node3D, method: String, args: Array) -> void:
	var err: int = target.callv(method, args)
	if err != OK:
		target.free()
		_report("%s failed. Mesh error %d." % [row["label"], err])
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		target.free()
		_report("Open a scene before creating a solid.")
		return
	var parent: Node = _create_parent(root)
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


func _amount_op(method: String) -> Dictionary:
	return { "method": method, "args": [_selection.ids, amount] }


func _solid_op(method: String) -> Dictionary:
	return { "method": method, "args": [] }


func _uv_op() -> Dictionary:
	return { "method": "set_face_uv", "args": [_selection.ids, uv_scale, uv_offset, deg_to_rad(uv_rotation_degrees)] }


func _uv_scaled(factor: float) -> Dictionary:
	uv_scale = Vector2(clampf(uv_scale.x * factor, 0.01, 64.0), clampf(uv_scale.y * factor, 0.01, 64.0))
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
	return { "method": "insert_loop", "args": [_selection.ids[0], 0.5] }


func _boolean_op(mode: int) -> Dictionary:
	return { "method": "boolean_with", "args": [_selection.objects[1], mode] }


func _mirror_op(axis: Vector3) -> Dictionary:
	return { "method": "mirror", "args": [axis] }


func _bake_op() -> Dictionary:
	return { "run": _bake }


func _bake(target: Node3D) -> String:
	var mesh_node := target.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_node == null or mesh_node.mesh == null:
		return "%s has no mesh to bake yet." % target.name
	var path := "res://baked_%s.tres" % target.name.to_snake_case()
	var err := ResourceSaver.save(mesh_node.mesh, path)
	if err != OK:
		return "Bake failed. Error %d." % err
	return "Baked %s." % path


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


func _pick_loop(target: Node3D) -> String:
	_selection.set_ids(SlabTopology.edge_loop(target, _selection.ids[0]))
	return _selection.describe()


func _pick_ring(target: Node3D) -> String:
	_selection.set_ids(SlabTopology.edge_ring(target, _selection.ids[0]))
	return _selection.describe()


func _row(id: String, label: String, icon: String, modes: Array, min_count: int, tooltip: String, shortcut: int, handler: Callable) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"icon": icon,
		"modes": modes,
		"min_count": min_count,
		"tooltip": tooltip,
		"shortcut": shortcut,
		"handler": handler,
	}


func _build() -> Array[Dictionary]:
	var object: Array = [SlabSelection.Mode.OBJECT]
	var vertex: Array = [SlabSelection.Mode.VERTEX]
	var edge: Array = [SlabSelection.Mode.EDGE]
	var face: Array = [SlabSelection.Mode.FACE]
	var elements: Array = [SlabSelection.Mode.VERTEX, SlabSelection.Mode.EDGE, SlabSelection.Mode.FACE]

	var table: Array = []
	for entry in shapes.entries():
		table.append(_row(entry["id"], entry["label"], entry["icon"], object, 0, entry["tooltip"], 0, shapes.plan.bind(entry["id"])))
	table.append_array([
		_row("boolean_union", "Union", "CSGCombiner3D", object, 2, "Adds the second solid into the first.", 0, _boolean_op.bind(BOOLEAN_UNION)),
		_row("boolean_subtract", "Subtract", "CSGBox3D", object, 2, "Cuts the second solid out of the first.", 0, _boolean_op.bind(BOOLEAN_SUBTRACT)),
		_row("boolean_intersect", "Intersect", "CSGMesh3D", object, 2, "Keeps only the overlap of two solids.", 0, _boolean_op.bind(BOOLEAN_INTERSECT)),
		_row("mirror_x", "Mirror X", "MirrorX", object, 1, "Mirrors the solid across its local X axis.", 0, _mirror_op.bind(Vector3(-1.0, 1.0, 1.0))),
		_row("mirror_y", "Mirror Y", "MirrorY", object, 1, "Mirrors the solid across its local Y axis.", 0, _mirror_op.bind(Vector3(1.0, -1.0, 1.0))),
		_row("mirror_z", "Mirror Z", "Back", object, 1, "Mirrors the solid across its local Z axis.", 0, _mirror_op.bind(Vector3(1.0, 1.0, -1.0))),
		_row("center_pivot", "Center Pivot", "EditorPivot", object, 1, "Moves the origin to the middle of the solid.", 0, _solid_op.bind("center_pivot")),
		_row("snap_to_grid", "Snap To Grid", "SnapGrid", object, 1, "Rounds every vertex onto the grid step.", 0, _solid_op.bind("snap_to_grid")),
		_row("bake_module", "Bake Module", "MeshInstance3D", object, 1, "Saves the built mesh next to the project.", 0, _bake_op),

		_row("weld_vertices", "Weld", "Snap", vertex, 2, "Merges vertices closer than the amount field.", KEY_J, _amount_op.bind("weld_vertices")),
		_row("collapse_vertices", "Collapse", "Group", vertex, 2, "Collapses the selection to one vertex.", KEY_Y, _ids_op.bind("collapse_vertices")),
		_row("connect_vertices", "Connect", "CurveLinear", vertex, 2, "Cuts an edge between the selected vertices.", KEY_K, _ids_op.bind("connect_vertices")),

		_row("bevel_edges", "Bevel", "ToolRotate", edge, 1, "Rounds the edge by the amount field.", KEY_B, _amount_op.bind("bevel_edges")),
		_row("bridge_edges", "Bridge", "CurveIn", edge, 2, "Builds a face between two open edges.", KEY_G, _ids_op.bind("bridge_edges")),
		_row("connect_edges", "Connect", "CurveOut", edge, 2, "Cuts a new edge between edge midpoints.", KEY_K, _ids_op.bind("connect_edges")),
		_row("insert_loop", "Insert Loop", "AnimationTrackGroup", edge, 1, "Inserts an edge loop across the first edge.", KEY_L, _loop_op),
		_row("dissolve_edges", "Dissolve", "Remove", edge, 1, "Removes the edge and merges its faces.", KEY_X, _ids_op.bind("dissolve_edges")),

		_row("extrude_faces", "Extrude", "ToolMove", face, 1, "Pulls the face out by the amount field.", KEY_E, _amount_op.bind("extrude_faces")),
		_row("inset_faces", "Inset", "ToolScale", face, 1, "Shrinks a copy of the face inside itself.", KEY_I, _amount_op.bind("inset_faces")),
		_row("delete_faces", "Delete", "Remove", face, 1, "Deletes the selected faces.", KEY_DELETE, _ids_op.bind("delete_faces")),
		_row("flip_faces", "Flip Normals", "Loop", face, 1, "Reverses which way the faces point.", KEY_N, _ids_op.bind("flip_faces")),
		_row("subdivide_faces", "Subdivide", "GridLayout", face, 1, "Splits each face into four.", KEY_U, _ids_op.bind("subdivide_faces")),
		_row("merge_faces", "Merge", "GroupViewport", face, 2, "Joins coplanar faces into one.", KEY_M, _ids_op.bind("merge_faces")),
		_row("set_face_material", "Set Material", "StandardMaterial3D", face, 1, "Assigns the material slot field to the faces.", 0, _material_op),
		_row("uv_apply", "Apply UV", "ImageTexture", face, 1, "Writes the UV scale, offset and rotation fields.", 0, _uv_op),
		_row("uv_scale_up", "UV Larger", "ZoomMore", face, 1, "Doubles the UV scale and applies it.", 0, _uv_scaled.bind(2.0)),
		_row("uv_scale_down", "UV Smaller", "ZoomLess", face, 1, "Halves the UV scale and applies it.", 0, _uv_scaled.bind(0.5)),
		_row("uv_rotate", "UV Rotate", "ToolRotate", face, 1, "Turns the UV by ninety degrees.", 0, _uv_turned.bind(90.0)),
		_row("uv_reset", "UV Reset", "Reload", face, 1, "Returns the UV to scale one and no rotation.", 0, _uv_cleared),

		_row("select_all", "Select All", "ListSelect", elements, 0, "Selects every element in the current mode.", KEY_A, _select_op.bind(_pick_all)),
		_row("select_none", "Select None", "Clear", elements, 1, "Clears the element selection.", KEY_D, _select_op.bind(_pick_none)),
		_row("select_invert", "Invert", "GuiChecked", elements, 1, "Swaps selected elements for unselected ones.", 0, _select_op.bind(_pick_inverted)),
		_row("select_grow", "Grow", "Add", elements, 1, "Adds the neighbours of the selection.", 0, _select_op.bind(_pick_grown)),
		_row("select_loop", "Select Loop", "Path3D", edge, 1, "Follows the edge loop around the solid.", 0, _select_op.bind(_pick_loop)),
		_row("select_ring", "Select Ring", "AnimationTrackList", edge, 1, "Follows the parallel edges across quads.", 0, _select_op.bind(_pick_ring)),
	])
	var out: Array[Dictionary] = []
	out.assign(table)
	return out
