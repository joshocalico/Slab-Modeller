extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const Bevel := preload("res://addons/slab/slab_bevel.gd")
const Host := preload("res://tests/slab_test_host.gd")
const Undo := preload("res://tests/slab_test_undo.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("ok " if ok else "FAIL ", message)

func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	return event

func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 3, 2))
	var selection := Selection.new()
	selection.solid = solid
	selection.mode = Selection.Mode.EDGE
	var edge: int = solid.call("get_edges")[0]
	selection.set_ids(PackedInt64Array([edge]))
	var undo := Undo.new()
	var host = Host.over(root).stub_undo(undo)
	var actions := Actions.new(selection, undo)
	var tool := Bevel.new(selection, actions, host)
	var before: PackedByteArray = solid.get("data")
	tool.set_amount(0.3)
	tool.set_segments(4)
	tool.begin()
	check(tool.active and not tool.lines.is_empty(), "ordinary edge starts a rounded bevel preview")
	check(solid.get("data") == before, "ordinary preview does not mutate geometry")
	tool.handle(null, key(KEY_ESCAPE))
	check(not tool.active and solid.get("data") == before and undo.actions.is_empty(), "Escape cancels without geometry or undo")

	tool.begin()
	tool.handle(null, key(KEY_ENTER))
	check(not tool.active and solid.call("face_count") == 10, "Enter applies four rounded bands")
	check(undo.actions.size() == 1, "bevel confirmation creates one undo action")
	var after: PackedByteArray = solid.get("data")
	undo.undo()
	check(solid.get("data") == before, "undo restores exact source bytes")
	undo.redo()
	check(solid.get("data") == after, "redo restores exact beveled bytes")

	undo.undo()
	var vertex: int = solid.call("get_vertices")[0]
	var incident := PackedInt64Array()
	for candidate in solid.call("get_edges"):
		var endpoints: PackedInt64Array = solid.call("edge_vertices", candidate)
		if endpoints.has(vertex): incident.append(candidate)
	selection.solid = solid
	selection.mode = Selection.Mode.EDGE
	selection.set_ids(incident)
	tool.set_segments(3)
	tool.begin()
	check(incident.size() == 3 and not tool.lines.is_empty(), "three-edge corner has a validated preview")
	check(solid.get("data") == before, "joint-corner preview does not mutate geometry")
	tool.cancel()

	selection.set_ids(PackedInt64Array([edge + 99]))
	tool.set_amount(0.25)
	tool.set_segments(4)
	tool.begin()
	check(tool.lines.is_empty(), "stale edge has no misleading preview")
	tool.confirm()
	check(solid.get("data") == before and undo.actions.size() == 1, "failed preview cannot mutate geometry or add undo")

	selection.set_ids(PackedInt64Array([solid.call("get_edges")[0]]))
	tool.set_amount(0.25)
	tool.set_segments(3)
	tool.begin()
	solid.call("make_box", Vector3(3, 3, 3))
	var external: PackedByteArray = solid.get("data")
	tool.confirm()
	check(not tool.active and solid.get("data") == external, "stale preview cannot overwrite external geometry")
	print("bevel_smoke: %d failures" % failures)
	quit(1 if failures else 0)
