extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabShapes := preload("res://addons/slab/slab_shapes.gd")

const REQUIRED_KEYS: PackedStringArray = [
	"id", "label", "icon", "modes", "min_count", "tooltip", "shortcut", "handler",
]

const FIELD_KEYS: PackedStringArray = ["key", "label", "min", "max", "step", "value", "tooltip"]

const DEFAULTS: Dictionary = {
	&"size_x": 2.0, &"size_y": 2.0, &"size_z": 2.0,
	&"stair_steps": 8.0, &"cylinder_sides": 16.0, &"arch_segments": 8.0,
	&"arch_thickness": 0.25, &"arch_arc": 180.0,
}

const RANGES: Dictionary = {
	&"stair_steps": [1.0, 32.0], &"cylinder_sides": [3.0, 32.0], &"arch_segments": [4.0, 32.0],
	&"arch_arc": [15.0, 360.0], &"arch_thickness": [0.05, 8.0],
	&"size_x": [0.05, 64.0], &"size_y": [0.05, 64.0], &"size_z": [0.05, 64.0],
}

const SELECTION_IDS: Array = ["select_all", "select_none", "select_invert", "select_grow", "snap_vertex"]

const SECTIONS_BY_MODE: Dictionary = {
	SlabSelection.Mode.OBJECT: {
		"Create": ["make_box", "make_plane", "make_stair", "make_cylinder", "make_arch", "make_poly_shape", "make_sweep"],
		"Object": [
			"boolean_union", "boolean_subtract", "boolean_intersect", "plane_cut", "array", "mirror_x", "mirror_y", "mirror_z",
			"center_pivot", "snap_to_grid",
		],
	},
	SlabSelection.Mode.VERTEX: {
		"Vertex": ["weld_vertices", "collapse_vertices", "connect_vertices"],
		"Selection": SELECTION_IDS,
	},
	SlabSelection.Mode.EDGE: {
		"Edge": ["bevel_edges", "bridge_edges", "connect_edges", "insert_loop", "dissolve_edges", "mark_uv_seam", "clear_uv_seam", "select_loop", "select_ring"],
		"Selection": SELECTION_IDS,
	},
	SlabSelection.Mode.FACE: {
		"Face": [
			"extrude_faces", "inset_faces", "delete_faces", "flip_faces", "subdivide_faces", "merge_faces", "select_coplanar", "align_face",
		],
		"UV": [
			"set_face_material", "uv_apply", "uv_scale_up", "uv_scale_down", "uv_rotate", "uv_reset", "uv_unwrap",
		],
		"Selection": SELECTION_IDS,
	},
}

var _fails := 0


func _init() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var rows: Array[Dictionary] = actions.rows()

	_expect(rows.size() >= 30, "registry has at least 30 rows, got %d" % rows.size())

	var seen: Dictionary = {}
	var valid_modes: Array = SlabSelection.Mode.values()
	for row in rows:
		var id: String = row.get("id", "")
		for key in REQUIRED_KEYS:
			_expect(row.has(key), "row %s has key %s" % [id, key])
		_expect(not seen.has(id), "row id %s is unique" % id)
		seen[id] = true
		_expect(row["modes"] is Array and not row["modes"].is_empty(), "row %s lists at least one mode" % id)
		for mode in row["modes"]:
			_expect(valid_modes.has(mode), "row %s mode %s is a Mode value" % [id, mode])
		_expect(row["handler"] is Callable and row["handler"].is_valid(), "row %s handler is a valid Callable" % id)
		_expect(row["min_count"] is int and row["min_count"] >= 0, "row %s min_count is a count" % id)
		_expect(row["shortcut"] is int, "row %s shortcut is a keycode" % id)

	_expect(actions.find("extrude_faces").has("id"), "find returns the extrude row")
	_expect(actions.find("array").has("id"), "find returns the array row")
	_expect(actions.array_count == 2 and actions.array_linear_step == Vector3(2, 0, 0), "array settings have useful exact defaults")
	_expect(actions.find("no_such_action").is_empty(), "find returns nothing for an unknown id")

	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([11, 22, 33]))
	_expect(selection.ids.size() == 3, "face selection holds three ids")
	selection.mode = SlabSelection.Mode.EDGE
	_expect(selection.ids.is_empty(), "changing mode clears the ids")
	_expect(selection.count() == 0, "count follows the cleared ids")
	_expect(selection.solid == null, "a fresh selection has no solid")
	_expect(selection.describe() == "No solid selected.", "status line reads as plain words")

	var blocked: String = actions.disabled_reason(actions.find("extrude_faces"))
	_expect(blocked == "Extrude needs Face mode.", "wrong mode disables extrude, got %s" % blocked)

	_check_catalog(actions, rows)
	_check_fields(actions.shapes)
	_check_phrasing(actions)
	_check_plans(SlabShapes.new())
	_check_mode_sections(actions, rows)
	_check_count_disable_wording(actions, selection)
	_check_shortcuts_without_a_panel(actions, selection)

	print("panel_smoke rows=%d" % rows.size())
	_finish()


func _check_mode_sections(actions: RefCounted, rows: Array[Dictionary]) -> void:
	var placed: Dictionary = {}
	for mode in SECTIONS_BY_MODE:
		var label: String = SlabSelection.MODE_LABELS[mode]
		var expected: Dictionary = SECTIONS_BY_MODE[mode]
		var sections: Array[Dictionary] = actions.command_sections_for(mode)
		var headings: Array = sections.map(func(section: Dictionary) -> String: return section["heading"])
		_expect(headings == expected.keys(), "%s mode shows %s, got %s" % [label, expected.keys(), headings])
		for section in sections:
			var heading: String = section["heading"]
			var ids: Array = section["rows"].map(func(row: Dictionary) -> String: return row["id"])
			_expect(ids == expected.get(heading, []), "%s mode lists %s under %s, got %s" % [label, expected.get(heading, []), heading, ids])
			for row in section["rows"]:
				_expect(row["modes"].has(mode), "%s is shown in %s mode only because it allows that mode" % [row["id"], label])
				placed[row["id"]] = true
			if heading == SlabActions.SECTION_CREATE:
				_expect(section["fields"].is_empty(), "Create fields live on the settings strip, not in the section")
			else:
				_expect(section["fields"].is_empty(), "the %s section carries no fields" % heading)
	for row in rows:
		_expect(placed.has(row["id"]), "%s is shown in at least one mode" % row["id"])
	_expect(SlabActions.section_of(actions.find("select_loop")) == "Edge", "Select Loop is an Edge row")
	_expect(SlabActions.section_of(actions.find("select_ring")) == "Edge", "Select Ring is an Edge row")


func _check_count_disable_wording(actions: RefCounted, selection: RefCounted) -> void:
	selection.mode = SlabSelection.Mode.FACE
	selection.clear_ids()
	var extrude: Dictionary = actions.find("extrude_faces")
	var merge: Dictionary = actions.find("merge_faces")
	var blocked: String = actions.disabled_reason(extrude)
	_expect(blocked == "Extrude needs 1 face.", "no face disables extrude by count, got %s" % blocked)
	selection.set_ids(PackedInt64Array([5]))
	_expect(actions.disabled_reason(extrude) == "", "one face enables extrude")
	blocked = actions.disabled_reason(merge)
	_expect(blocked == "Merge needs 2 faces.", "one face disables merge by count, got %s" % blocked)


func _check_shortcuts_without_a_panel(actions: RefCounted, selection: RefCounted) -> void:
	selection.mode = SlabSelection.Mode.FACE
	selection.clear_ids()
	var said: Array[String] = []
	actions.reported.connect(func(text: String) -> void: said.append(text))
	_expect(actions.run_shortcut(KEY_A), "Select All dispatches from the registry with no panel built")
	_expect(said.size() == 1 and said[0] == "No solid selected.", "the dispatch reports the missing solid, got %s" % [said])
	_expect(not actions.run_shortcut(KEY_B), "Bevel does not dispatch in Face mode")
	_expect(not actions.run_shortcut(KEY_E), "Extrude does not dispatch with no face selected")


func _check_catalog(actions: RefCounted, rows: Array[Dictionary]) -> void:
	var create_ids: Array[String] = []
	for row in rows:
		if SlabActions.section_of(row) == SlabActions.SECTION_CREATE:
			create_ids.append(row["id"])
	var catalog_ids: Array[String] = []
	for key in SlabShapes.CATALOG:
		catalog_ids.append(String(key))
	_expect(create_ids == catalog_ids, "Create rows are the catalog in order, got %s" % [create_ids])

	var claimed: Dictionary = {}
	for id in SlabShapes.CATALOG:
		var entry: Dictionary = SlabShapes.CATALOG[id]
		for key in entry["params"]:
			_expect(SlabShapes.PARAMS.has(key), "%s reads a declared parameter %s" % [id, key])
			claimed[key] = true
	for key in SlabShapes.PARAMS:
		_expect(claimed.has(key), "parameter %s is read by at least one shape" % key)

	_expect(actions.shapes.fields_for(&"make_stair").size() == 4, "Stair shows width, height, depth, and steps")
	_expect(actions.shapes.fields_for(&"make_box").size() == 3, "Box shows width, height, and depth")
	var stair_keys: Array = actions.shapes.fields_for(&"make_stair").map(func(field: Dictionary) -> StringName: return field["key"])
	_expect(stair_keys.has(&"stair_steps") and not stair_keys.has(&"arch_arc"), "Stair fields do not include Arc")
	_expect(not SlabShapes.CATALOG[&"make_arch"]["params"].has(&"size_y"), "arch does not read Height")
	_expect(not SlabShapes.CATALOG[&"make_plane"]["params"].has(&"size_y"), "plane does not read Height")

	for id in SlabShapes.CATALOG:
		var row: Dictionary = actions.find(id)
		_expect(row["handler"].call().has("method"), "%s plans a method at defaults" % id)


func _check_fields(shapes: RefCounted) -> void:
	var fields: Array[Dictionary] = shapes.fields()
	_expect(fields.size() == SlabShapes.PARAMS.size(), "one field per parameter, got %d" % fields.size())
	for field in fields:
		var key: StringName = field["key"]
		for name in FIELD_KEYS:
			_expect(field.has(name), "field %s has key %s" % [key, name])
		_expect(is_equal_approx(field["value"], DEFAULTS[key]), "%s defaults to %s, got %s" % [key, DEFAULTS[key], field["value"]])
		var bounds: Array = RANGES[key]
		_expect(is_equal_approx(field["min"], bounds[0]) and is_equal_approx(field["max"], bounds[1]),
			"%s ranges %s..%s, got %s..%s" % [key, bounds[0], bounds[1], field["min"], field["max"]])
		_expect(field["tooltip"] != "", "%s has a tooltip" % key)

	shapes.set_value(&"stair_steps", 99.0)
	_expect(shapes.value_of(&"stair_steps") == 32.0, "set_value clamps high, got %s" % shapes.value_of(&"stair_steps"))
	shapes.set_value(&"stair_steps", -4.0)
	_expect(shapes.value_of(&"stair_steps") == 1.0, "set_value clamps low, got %s" % shapes.value_of(&"stair_steps"))
	shapes.set_value(&"arch_arc", 400.0)
	_expect(shapes.value_of(&"arch_arc") == 360.0, "arc clamps to 360, got %s" % shapes.value_of(&"arch_arc"))
	shapes.set_value(&"no_such_key", 5.0)
	_expect(shapes.fields().size() == SlabShapes.PARAMS.size(), "an unknown key does not grow the store")
	shapes.set_value(&"stair_steps", 8.0)
	shapes.set_value(&"arch_arc", 180.0)

	var height_tip: String = ""
	for field in fields:
		if field["key"] == &"size_y":
			height_tip = field["tooltip"]
	_expect(height_tip.contains("Arch") and height_tip.contains("Plane") and height_tip.contains("ignore"),
		"the Height tooltip names Arch and Plane as ignoring it, got %s" % height_tip)


func _check_phrasing(actions: RefCounted) -> void:
	var shapes: RefCounted = actions.shapes
	var stair: String = shapes.describe(&"make_stair")
	_expect(stair.contains("8 steps"), "stair describes 8 steps, got %s" % stair)
	shapes.set_value(&"stair_steps", 20.0)
	stair = shapes.describe(&"make_stair")
	_expect(stair.contains("20 steps") and not stair.contains("8"), "stair describes 20 steps and no stale 8, got %s" % stair)
	shapes.set_value(&"stair_steps", 8.0)

	var arch_row: Dictionary = actions.find("make_arch")
	_expect(actions.tooltip_of(arch_row).contains("180 degrees"), "arch tooltip carries 180 degrees")
	shapes.set_value(&"arch_arc", 90.0)
	_expect(actions.tooltip_of(arch_row).contains("90 degrees"), "arch tooltip follows the arc field")
	shapes.set_value(&"arch_arc", 180.0)
	_expect(actions.tooltip_of(arch_row).begins_with(arch_row["tooltip"]), "arch tooltip starts with the row's sentence")
	_expect(actions.tooltip_of(actions.find("extrude_faces")).contains("connected face region"),
		"Extrude tooltip describes connected regions")
	_expect(actions.tooltip_of(actions.find("inset_faces")).contains("connected coplanar face region"),
		"Inset tooltip states its coplanar region limit")
	_expect(shapes.describe(&"extrude_faces") == "", "describe is empty for a non-shape id")
	_expect(SlabActions.describe_error(SlabActions.ERR_NOT_CLOSED, "delete_faces").contains("open solid"),
		"delete explains the closed-solid rule")
	_expect(SlabActions.describe_error(SlabActions.ERR_SELF_INTERSECTION).contains("cross or overlap"),
		"an intersecting edit explains the embedding rule")
	_expect(SlabActions.describe_error(SlabActions.ERR_SELF_INTERSECTION, "extrude_faces").contains("opposite wall"),
		"refused extrusion explains how to avoid crossing the opposite wall")
	_expect(not SlabActions.describe_error(SlabActions.ERR_SELF_INTERSECTION, "bevel_edges").contains("Inset"),
		"other tools do not prescribe an unrelated inset workflow")
	_expect(not SlabActions.describe_error(SlabActions.ERR_NOT_CLOSED, "delete_faces").contains("Mesh error"),
		"delete does not fall back to a bare error number")
	_expect(SlabActions.ERR_SELF_INTERSECTION == 16, "SELF_INTERSECTION stays last at 16")
	_expect(SlabActions.describe_error(SlabActions.ERR_ADJACENT_SELECTION).contains("share"),
		"adjacent selection names the shared-edge rule")
	_expect(not SlabActions.describe_error(SlabActions.ERR_ADJACENT_SELECTION).contains("faces that do not touch"),
		"adjacent selection is not face-only")
	_expect(SlabActions.describe_error(SlabActions.ERR_COORD_OUT_OF_RANGE).contains("allowed range"),
		"coord errors name a range, not only a vertex")
	_expect(SlabActions.describe_error(SlabActions.ERR_TWIN_MISMATCH).contains("twin"),
		"twin mismatch names the twin")
	_expect(SlabActions.describe_error(SlabActions.ERR_DEGENERATE_FACE).contains("line or point"),
		"collapsed faces explain the geometric problem in plain language")
	for code in range(1, SlabActions.ERR_SELF_INTERSECTION + 1):
		_expect(not SlabActions.describe_error(code).contains("Mesh error"),
			"code %d has a named phrase, got %s" % [code, SlabActions.describe_error(code)])
	_expect(SlabActions.describe_error(99).contains("Mesh error 99"), "unknown codes still print the number")


func _check_plans(shapes: RefCounted) -> void:
	var arch: Dictionary = shapes.plan(&"make_arch")
	_expect(arch.get("method", "") == "make_arch", "arch plan calls make_arch")
	var args: Array = arch.get("args", [])
	_expect(args.size() == 5, "arch plan passes five args, got %d" % args.size())
	if args.size() == 5:
		_expect(is_equal_approx(args[0], 2.0) and is_equal_approx(args[1], 2.0), "arch plan passes width then depth")
		_expect(args[2] == 8 and is_equal_approx(args[3], 0.25), "arch plan passes segments and thickness")
		_expect(is_equal_approx(args[4], PI), "arch plan passes the arc in radians, got %s" % args[4])

	shapes.set_value(&"arch_thickness", 2.0)
	var refused: Dictionary = shapes.plan(&"make_arch")
	_expect(refused.has("status") and not refused.has("method"), "a thick arch is refused in words, got %s" % [refused])
	shapes.set_value(&"arch_thickness", 0.25)

	var cylinder: Dictionary = shapes.plan(&"make_cylinder")
	_expect(is_equal_approx(cylinder["args"][0], 1.0), "cylinder radius is half the width")
	_expect(shapes.plan(&"make_plane")["args"][0] == Vector2(2.0, 2.0), "plane takes width and depth")
	_expect(shapes.plan(&"no_such_shape").is_empty(), "an unknown id plans nothing")


func _expect(ok: bool, what: String) -> void:
	if ok:
		return
	push_error("FAIL " + what)
	print("FAIL ", what)
	_fails += 1


func _finish() -> void:
	if _fails != 0:
		push_error(str(_fails) + " failures")
		quit(1)
	else:
		print("panel_smoke ok")
		quit(0)
