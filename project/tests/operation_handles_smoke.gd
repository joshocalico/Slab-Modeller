extends SceneTree

const Handles := preload("res://addons/slab/slab_operation_handles.gd")
const Undo := preload("res://tests/slab_test_undo.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("ok " if ok else "FAIL ", message)


func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(7, 8, 10), Vector3.ZERO, Vector3.UP)
	var top := _top_face(solid)
	var before: PackedByteArray = solid.get("data")
	var handles := Handles.new()

	check(handles.begin(Handles.Kind.EXTRUDE, solid, PackedInt64Array([top]), 0.75), "selected face starts an extrusion handle")
	var shape: Dictionary = handles.geometry()
	check(shape.get("label", "").contains("0.750 m") and (shape.get("segments") as PackedVector3Array).size() == 2,
		"extrusion supplies arrow geometry and a numeric label")
	var tip_screen := camera.unproject_position(shape["tip"])
	check(handles.hit_test(camera, tip_screen, 16.0), "extrusion arrow is screen-pickable")
	check(solid.get("data") == before and not handles.preview_data.is_empty() and not handles.preview_lines.is_empty(),
		"extrusion preview supplies full result wire without changing live data")
	check(not handles.result_ids.is_empty(), "extrusion preview returns stable cap selection ids")
	handles.set_amount(1.125)
	check(handles.geometry().get("label", "").contains("1.125 m"), "exact amount updates preview and label")
	handles.set_amount(-1.0)
	shape = handles.geometry()
	check((shape["tip"] - shape["anchor"]).dot(Vector3.UP) < 0.0, "negative extrusion arrow points inward")
	handles.cancel()
	check(solid.get("data") == before, "cancel changes no geometry")

	var undo := Undo.new()
	check(handles.begin(Handles.Kind.EXTRUDE, solid, PackedInt64Array([top]), 1.0), "extrusion restarts")
	var cap_ids := handles.result_ids.duplicate()
	var confirmation: Dictionary = handles.confirm(undo)
	check(not confirmation.is_empty(), "extrusion confirmation applies validated preview")
	var extruded: PackedByteArray = solid.get("data")
	check(extruded != before and undo.actions.size() == 1, "extrusion is one undo action")
	check(not cap_ids.is_empty() and solid.call("is_alive", cap_ids[0]), "returned cap selection survives confirmation")
	undo.undo()
	check(solid.get("data") == before, "extrusion undo restores exact source")
	undo.redo()
	check(solid.get("data") == extruded, "extrusion redo restores result")

	undo.undo()
	check(handles.begin(Handles.Kind.INSET, solid, PackedInt64Array([top]), 0.4), "face starts an inset-width handle")
	shape = handles.geometry()
	check((shape.get("segments") as PackedVector3Array).size() == 2 and shape.get("label", "").contains("Inset"),
		"inset supplies bidirectional width geometry")
	check(solid.get("data") == before and int(handles.preview().get("error", -1)) == OK, "inset preview is atomic and valid")
	handles.cancel()

	var edge: int = solid.call("get_edges")[0]
	check(handles.begin(Handles.Kind.BEVEL, solid, PackedInt64Array([edge]), 0.25, 3), "edge starts a bevel-width handle")
	check(not handles.preview_lines.is_empty() and solid.get("data") == before, "bevel uses validated kernel preview without mutation")
	handles.cancel()

	var all_edges: PackedInt64Array = solid.call("get_edges")
	var all_preview: Dictionary = solid.call("preview_bevel", all_edges, 0.05, 1)
	check(int(all_preview.get("error", -1)) == 5,
		"kernel retains its all-edge box validation, error=%s" % all_preview.get("error", -1))
	check(handles.begin(Handles.Kind.BEVEL, solid, all_edges, 0.05, 1),
		"symmetric all-edge bevel gets an editor handle frame")
	check(handles.active and handles.error == int(all_preview.get("error", -1)),
		"editor frame exposes the kernel result for the complete edge set")
	handles.cancel()

	camera.free()
	solid.free()
	print("operation_handles_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func _top_face(solid: Node3D) -> int:
	var best := 0
	var up := -2.0
	for face in PackedInt64Array(solid.call("get_faces")):
		var y: float = (solid.call("face_normal", face) as Vector3).y
		if y > up:
			up = y
			best = face
	return best
