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

	_check_face_bevel_perimeter()
	_check_edge_bevel_regression()
	print("bevel_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func _check_face_bevel_perimeter() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	var undo := Undo.new()
	var host = Host.over(root).stub_undo(undo)
	var session := SlabViewport.new(host)
	var selection: RefCounted = session.state()
	selection.solid = solid
	selection.mode = Selection.Mode.FACE
	var actions := Actions.new(selection, undo)
	var reports: Array[String] = []
	actions.reported.connect(func(message: String) -> void: reports.append(message))
	session.bind_actions(actions)

	var top := 0
	for face_id in solid.call("get_faces"):
		if solid.call("face_normal", face_id).y > 0.9:
			top = int(face_id)
			break
	selection.set_ids(PackedInt64Array([top]))
	var before: PackedByteArray = solid.get("data")
	var before_faces: int = solid.call("face_count")

	actions.bevel_amount = 0.1
	actions.bevel_segments = 2
	actions.run("bevel_edges")
	check(actions.operation_active, "Face mode Bevel starts an operation")
	check(not (selection.operation_preview.get("preview_lines", PackedVector3Array()) as PackedVector3Array).is_empty(),
		"Face→Bevel shows perimeter preview lines")
	check(solid.get("data") == before, "Face→Bevel preview does not mutate geometry")

	session.handle(null, key(KEY_ESCAPE))
	check(not actions.operation_active and solid.get("data") == before, "Face→Bevel Escape cancels without changes")

	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	actions.run("bevel_edges")
	session.handle(null, key(KEY_ENTER))
	check(not actions.operation_active, "Face→Bevel Enter completes the operation")
	check(solid.get("data") != before, "Face→Bevel Apply changes geometry")
	check(int(solid.call("face_count")) > before_faces, "Face→Bevel adds faces for the rounded perimeter")
	check(selection.mode == Selection.Mode.FACE, "Face→Bevel Apply stays in Face mode")
	check(selection.ids.size() == 1 and selection.ids[0] == top, "Face→Bevel Apply preserves face selection")

	var beveled: PackedByteArray = solid.get("data")
	undo.undo()
	check(solid.get("data") == before, "Face→Bevel undo restores original geometry")
	check(selection.mode == Selection.Mode.FACE, "Face→Bevel undo stays in Face mode")
	check(selection.ids.size() == 1 and selection.ids[0] == top, "Face→Bevel undo restores face selection")

	undo.redo()
	check(solid.get("data") == beveled, "Face→Bevel redo restores beveled geometry")
	check(selection.mode == Selection.Mode.FACE, "Face→Bevel redo stays in Face mode")
	solid.free()

	var solid2: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid2)
	solid2.call("make_box", Vector3(2, 2, 2))
	selection.solid = solid2
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array(solid2.call("get_faces")))
	reports.clear()
	actions.run("bevel_edges")
	check(not actions.operation_active, "Face→Bevel on all faces (no boundary) refuses to start")
	check(not reports.is_empty() and reports[-1].contains("no boundary edges"),
		"Face→Bevel with empty boundary reports clear refusal, got: %s" % (reports[-1] if not reports.is_empty() else "none"))
	solid2.free()


func _check_edge_bevel_regression() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var undo := Undo.new()
	var host = Host.over(root).stub_undo(undo)
	var session := SlabViewport.new(host)
	var selection: RefCounted = session.state()
	selection.solid = solid
	selection.mode = Selection.Mode.EDGE
	var actions := Actions.new(selection, undo)
	session.bind_actions(actions)

	var edge: int = solid.call("get_edges")[0]
	selection.set_ids(PackedInt64Array([edge]))
	var before: PackedByteArray = solid.get("data")

	actions.bevel_amount = 0.15
	actions.bevel_segments = 1
	actions.run("bevel_edges")
	check(actions.operation_active, "Edge mode Bevel still starts an operation (regression check)")
	check(not (selection.operation_preview.get("preview_lines", PackedVector3Array()) as PackedVector3Array).is_empty(),
		"Edge→Bevel still shows preview lines (regression check)")

	session.handle(null, key(KEY_ENTER))
	check(not actions.operation_active and solid.get("data") != before, "Edge→Bevel still applies geometry (regression check)")
	solid.free()
