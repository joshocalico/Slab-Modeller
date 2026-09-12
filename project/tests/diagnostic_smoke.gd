extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("ok " if ok else "FAIL ", message)

func _initialize() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 3, 2))
	var top: int = 0
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9:
			top = face
	var before: PackedByteArray = solid.get("data")
	check(solid.call("extrude_faces", PackedInt64Array([top]), -4.0) == 16,
		"piercing extrusion is refused with the established self-intersection code")
	check(solid.get("data") == before, "refused extrusion preserves original geometry")
	var diagnostic: Dictionary = solid.call("get_edit_diagnostic")
	var lines: PackedVector3Array = diagnostic.get("segments", PackedVector3Array())
	check(diagnostic.get("code", 0) == 16 and lines.size() >= 12,
		"refused edit exposes colliding face outlines for the gizmo")
	var below_floor := false
	for point in lines:
		if point.y < -0.5: below_floor = true
	check(below_floor, "highlight uses attempted geometry below the original floor")
	solid.set("data", before)
	check(solid.call("get_edit_diagnostic").is_empty(), "restoring saved data clears obsolete diagnostics")
	solid.call("extrude_faces", PackedInt64Array([top]), -4.0)
	check(solid.call("extrude_faces", PackedInt64Array([top]), 0.5) == OK,
		"a valid outward extrusion still commits")
	check(solid.call("get_edit_diagnostic").is_empty(), "successful edit clears the prior fault highlight")
	var stable: PackedByteArray = solid.get("data")
	var edge: int = solid.call("get_edges")[0]
	var vertex: int = solid.call("get_vertices")[0]
	check(solid.call("bevel_edges", PackedInt64Array([edge + 1]), 0.1, 1) == 1,
		"a stale edge is rejected before the operation")
	diagnostic = solid.call("get_edit_diagnostic")
	check(diagnostic.get("element", 0) == 2 and diagnostic.get("segments", PackedVector3Array()).size() == 2,
		"early edge rejection identifies the current segment at the stale slot")
	check(solid.get("data") == stable, "early edge rejection does not mutate live geometry")
	check(solid.call("move_vertices", PackedInt64Array([vertex + 1]), Vector3.ONE) == 1,
		"a stale vertex is rejected before the operation")
	diagnostic = solid.call("get_edit_diagnostic")
	check(diagnostic.get("element", 0) == 1 and diagnostic.get("segments", PackedVector3Array()).size() >= 6,
		"early vertex rejection replaces the old diagnostic with its incident edge star")
	check(solid.get("data") == stable, "early vertex rejection does not mutate live geometry")
	solid.free()
	print("diagnostic_smoke: %d failures" % failures)
	quit(1 if failures else 0)
