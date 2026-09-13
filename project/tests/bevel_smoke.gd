extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
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
	var undo := Undo.new()
	var host = Host.over(root).stub_undo(undo)
	var session := SlabViewport.new(host)
	var selection: RefCounted = session.state()
	selection.solid = solid
	selection.mode = Selection.Mode.EDGE
	var edge: int = solid.call("get_edges")[0]
	selection.set_ids(PackedInt64Array([edge]))
	var actions := Actions.new(selection, undo)
	var reports: Array[String] = []
	actions.reported.connect(func(message: String) -> void: reports.append(message))
	session.bind_actions(actions)
	var before: PackedByteArray = solid.get("data")
	actions.bevel_amount = 0.3
	actions.bevel_segments = 4
	actions.run("bevel_edges")
	check(actions.operation_active and not (selection.operation_preview.get("preview_lines", PackedVector3Array()) as PackedVector3Array).is_empty(), "ordinary edge starts a rounded bevel preview")
	check(solid.get("data") == before, "ordinary preview does not mutate geometry")
	session.handle(null, key(KEY_ESCAPE))
	check(not actions.operation_active and solid.get("data") == before and undo.actions.is_empty(), "Escape cancels without geometry or undo")

	actions.run("bevel_edges")
	session.handle(null, key(KEY_ENTER))
	check(not actions.operation_active and solid.call("face_count") == 10, "Enter applies four rounded bands")
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
	actions.bevel_segments = 3
	actions.run("bevel_edges")
	check(incident.size() == 3 and not (selection.operation_preview.get("preview_lines", PackedVector3Array()) as PackedVector3Array).is_empty(), "three-edge corner has a validated preview")
	check(solid.get("data") == before, "joint-corner preview does not mutate geometry")
	actions.operation_cancel_requested.emit()

	selection.set_ids(solid.call("get_edges"))
	actions.bevel_amount = 0.05
	actions.bevel_segments = 1
	actions.run("bevel_edges")
	check(actions.operation_active and int(selection.operation_preview.get("error", OK)) == Actions.ERR_NON_MANIFOLD_VERTEX,
		"all-edge box bevel reaches kernel validation through a stable handle frame")
	check(not reports.is_empty() and reports[-1].contains("one edge, a simple perimeter, or three edges meeting at one corner"),
		"all-edge refusal reports the kernel reason instead of a shared-direction gate, got %s" % (reports[-1] if not reports.is_empty() else "none"))
	actions.operation_cancel_requested.emit()
	selection.clear_ids()
	actions.run("bevel_edges")
	check(not reports.is_empty() and reports[-1] == "Bevel needs 1 edge.",
		"missing-edge refusal is specific to Bevel, got %s" % (reports[-1] if not reports.is_empty() else "none"))

	selection.set_ids(PackedInt64Array([edge + 99]))
	actions.bevel_amount = 0.25
	actions.bevel_segments = 4
	actions.run("bevel_edges")
	check((selection.operation_preview.get("preview_lines", PackedVector3Array()) as PackedVector3Array).is_empty(), "stale edge has no misleading preview")
	actions.operation_apply_requested.emit()
	check(solid.get("data") == before and undo.actions.size() == 1, "failed preview cannot mutate geometry or add undo")

	selection.set_ids(PackedInt64Array([solid.call("get_edges")[0]]))
	actions.bevel_amount = 0.25
	actions.bevel_segments = 3
	actions.run("bevel_edges")
	solid.call("make_box", Vector3(3, 3, 3))
	var external: PackedByteArray = solid.get("data")
	actions.operation_apply_requested.emit()
	check(not actions.operation_active and solid.get("data") == external, "stale preview cannot overwrite external geometry")
	print("bevel_smoke: %d failures" % failures)
	quit(1 if failures else 0)
