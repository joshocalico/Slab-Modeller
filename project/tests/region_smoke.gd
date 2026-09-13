extends SceneTree

const Actions := preload("res://addons/slab/slab_actions.gd")
const Selection := preload("res://addons/slab/slab_selection.gd")
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
	check(solid.call("make_box", Vector3(4, 3, 4)) == OK, "region box builds")
	var top: int = _top_face(solid)
	check(solid.call("subdivide_faces", PackedInt64Array([top])) == OK, "top subdivides into four")
	var caps := _up_faces(solid, 5.0)
	check(caps.size() == 4, "four connected cap faces are selected")

	var host: RefCounted = preload("res://tests/slab_test_host.gd").over(root)
	var session := preload("res://addons/slab/slab_viewport.gd").new(host)
	var selection: RefCounted = session.state()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	var undo := Undo.new()
	host.stub_undo(undo)
	var actions := Actions.new(selection, undo)
	session.bind_actions(actions)
	selection.set_ids(PackedInt64Array([caps[0]]))
	actions.run("select_coplanar")
	check(selection.ids.size() == 4, "Select Coplanar expands one subdivided top face to its connected four-face plane")
	var before_inset: PackedByteArray = solid.get("data")
	actions.inset_amount = 0.45
	actions.run("inset_faces")
	actions.operation_apply_requested.emit()
	var after_inset: PackedByteArray = solid.get("data")
	check(after_inset != before_inset, "Inset edits the connected region")
	check(selection.ids.size() == 4 and _all_faces_alive(solid, selection.ids), "Inset refreshes all four cap handles")
	var inset_ids := PackedInt64Array(selection.ids)

	actions.extrude_amount = -2.4
	actions.run("extrude_faces")
	actions.operation_apply_requested.emit()
	var after_extrude: PackedByteArray = solid.get("data")
	check(after_extrude != after_inset, "negative Extrude pulls the inset region into a room")
	check(selection.ids.size() == 4 and _all_faces_alive(solid, selection.ids), "Extrude refreshes all four cap handles")
	var extruded_ids := PackedInt64Array(selection.ids)
	check(undo.actions.size() == 2, "Inset and Extrude create two undo actions")
	undo.undo()
	check(solid.get("data") == after_inset and selection.ids == inset_ids, "undo restores inset bytes and handles")
	undo.redo()
	check(solid.get("data") == after_extrude and selection.ids == extruded_ids, "redo restores extrusion bytes and handles")

	var opposite: PackedInt64Array = _opposite_faces(solid)
	selection.set_ids(opposite)
	var before_refusal: PackedByteArray = solid.get("data")
	var reports: Array[String] = []
	actions.reported.connect(func(text: String) -> void: reports.append(text))
	actions.extrude_amount = 0.5
	actions.run("extrude_faces")
	actions.operation_apply_requested.emit()
	check(solid.get("data") == before_refusal, "disconnected region leaves geometry unchanged")
	check(not reports.is_empty() and reports.back().contains("selection cannot run"), "disconnected region reports an invalid selection")

	print("region_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func _top_face(solid: Node3D) -> int:
	var best: int = 0
	var up := -2.0
	for face in PackedInt64Array(solid.call("get_faces")):
		var y: float = (solid.call("face_normal", face) as Vector3).y
		if y > up:
			up = y
			best = face
	return best


func _up_faces(solid: Node3D, area_under: float) -> PackedInt64Array:
	var out := PackedInt64Array()
	for face in PackedInt64Array(solid.call("get_faces")):
		var normal: Vector3 = solid.call("face_normal", face)
		var corners: PackedVector3Array = solid.call("face_corners", face)
		var twice_area := Vector3.ZERO
		for i in corners.size():
			twice_area += corners[i].cross(corners[(i + 1) % corners.size()])
		var area := twice_area.length() * 0.5
		if normal.y > 0.99 and area < area_under:
			out.append(face)
	return out


func _opposite_faces(solid: Node3D) -> PackedInt64Array:
	var top: int = 0
	var bottom: int = 0
	for face in PackedInt64Array(solid.call("get_faces")):
		var y: float = (solid.call("face_normal", face) as Vector3).y
		if y > 0.99:
			top = face
		elif y < -0.99:
			bottom = face
	return PackedInt64Array([top, bottom])


func _all_faces_alive(solid: Node3D, faces: PackedInt64Array) -> bool:
	for face in faces:
		if (solid.call("face_uv", face) as Dictionary).is_empty():
			return false
	return true
