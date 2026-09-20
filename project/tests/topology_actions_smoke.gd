extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const Undo := preload("res://tests/slab_test_undo.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	var top := 0
	var side := 0
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9: top = face
		if solid.call("face_normal", face).x > 0.9: side = face
	selection.set_ids(PackedInt64Array([top]))
	var undo := Undo.new()
	var actions := Actions.new(selection, undo)
	actions.reported.connect(func(message: String) -> void: print("REPORT ", message))
	var before: PackedByteArray = solid.get("data")
	actions.run("subdivide_faces")
	var split: PackedByteArray = solid.get("data")
	var split_ids := PackedInt64Array(selection.ids)
	check(split != before and split_ids.size() == 4, "Subdivide selects all four resulting quads")
	for face in split_ids:
		check(solid.call("face_normal", face).y > 0.9, "result selection stays on the top surface")
	undo.undo()
	check(solid.get("data") == before and selection.ids == PackedInt64Array([top]) and selection.active_id == top, "Undo restores subdivision input geometry and selection")
	undo.redo()
	check(solid.get("data") == split and selection.ids == split_ids and split_ids.has(selection.active_id), "Redo restores subdivision output selection")
	# Reorder the region so the next selected quad may not touch the first.
	if split_ids.size() == 4:
		selection.set_ids(PackedInt64Array([split_ids[0], split_ids[2], split_ids[1], split_ids[3]]))
	var merge_input := PackedInt64Array(selection.ids)
	actions.run("merge_faces")
	var merged: PackedByteArray = solid.get("data")
	var merged_ids := PackedInt64Array(selection.ids)
	check(merged != split and merged_ids.size() == 1, "Merge selects its surviving face")
	check(merged_ids.size() == 1 and not solid.call("face_uv", merged_ids[0]).is_empty(), "Merge selection contains a live face")
	undo.undo()
	check(solid.get("data") == split and selection.ids == merge_input, "Merge Undo restores exact input region selection")
	undo.redo()
	check(solid.get("data") == merged and selection.ids == merged_ids, "Merge Redo restores its result selection")
	if not merged_ids.is_empty():
		selection.set_ids(PackedInt64Array([merged_ids[0], side]))
	var refused_ids := PackedInt64Array(selection.ids)
	var history_size := undo.actions.size()
	actions.run("merge_faces")
	check(solid.get("data") == merged and selection.ids == refused_ids and undo.actions.size() == history_size, "folded Merge refusal preserves data, selection and history")
	_check_connect_dissolve()
	_check_select_boundary()
	_check_weld_collapse()
	_check_concave_prism_ops()
	print("topology_actions_smoke: %d failures" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("ok " if ok else "FAIL ", message)

func _check_connect_dissolve() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	var top := 0
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9: top = face
	var edges: PackedInt64Array = solid.call("face_edges", top)
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.EDGE
	var undo := Undo.new()
	var actions := Actions.new(selection, undo)
	selection.set_ids(PackedInt64Array([edges[0], edges[1], edges[2]]))
	check(actions.disabled_reason(actions.find("connect_edges")).contains("exactly 2"), "Connect explains its exact two-edge requirement")
	selection.set_ids(PackedInt64Array([edges[0], edges[2]]))
	var input_ids := PackedInt64Array(selection.ids)
	var before: PackedByteArray = solid.get("data")
	actions.run("connect_edges")
	var cut: PackedByteArray = solid.get("data")
	var cut_ids := PackedInt64Array(selection.ids)
	check(solid.call("face_count") == 7 and cut_ids.size() == 1 and not edges.has(cut_ids[0]), "Connect selects its new diagonal edge")
	actions.run("dissolve_edges")
	check(solid.call("face_count") == 6 and selection.ids.is_empty(), "Dissolve removes the selected cut without stale selection")
	undo.undo()
	check(solid.get("data") == cut and selection.ids == cut_ids and selection.active_id == cut_ids[0], "Dissolve Undo restores its edge and active selection")
	undo.undo()
	check(solid.get("data") == before and selection.ids == input_ids, "Connect Undo restores its original edge pair")
	var other: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(other)
	other.call("make_box", Vector3.ONE)
	selection.set_objects([other])
	var other_ids := PackedInt64Array([other.call("get_edges")[0]])
	selection.set_ids(other_ids)
	undo.redo()
	check(solid.get("data") == cut and selection.solid == other and selection.ids == other_ids, "redo does not assign topology handles to another selected solid")


func _check_select_boundary() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	var actions := Actions.new(selection, null)
	var reports: Array[String] = []
	actions.reported.connect(func(message: String) -> void: reports.append(message))
	var face: int = solid.call("get_faces")[0]
	selection.set_ids(PackedInt64Array([face]))
	actions.run("select_boundary")
	check(selection.solid == solid and selection.mode == Selection.Mode.EDGE and selection.ids.size() == 4,
		"one face selects its four boundary edges and preserves the target")

	var shared: int = selection.ids[0]
	var incident := PackedInt64Array(solid.call("edge_faces", shared))
	selection.mode = Selection.Mode.FACE
	selection.set_ids(incident)
	actions.run("select_boundary")
	check(selection.mode == Selection.Mode.EDGE and selection.ids.size() == 6 and not selection.ids.has(shared),
		"two adjacent faces select their union boundary without the shared edge")

	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array(solid.call("get_faces")))
	actions.run("select_boundary")
	check(selection.mode == Selection.Mode.EDGE and selection.ids.is_empty(), "all faces produce an empty boundary selection")
	check(not reports.is_empty() and reports[-1].contains("no boundary edges"), "empty face boundary reports a clear refusal")
	solid.free()

	_check_select_boundary_flat_multi_face_region()
	_check_select_boundary_curved_region()
	_check_select_boundary_then_bevel()


func _check_select_boundary_flat_multi_face_region() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	var top := 0
	for face_id in solid.call("get_faces"):
		if solid.call("face_normal", face_id).y > 0.9:
			top = face_id
			break
	solid.call("subdivide_faces", PackedInt64Array([top]))
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	var actions := Actions.new(selection, null)

	var top_faces := PackedInt64Array()
	for face_id in solid.call("get_faces"):
		if solid.call("face_normal", face_id).y > 0.9:
			top_faces.append(face_id)
	check(top_faces.size() == 4, "subdivided top has four coplanar faces")

	selection.set_ids(top_faces)
	actions.run("select_boundary")
	check(selection.mode == Selection.Mode.EDGE, "multi-face boundary switches to Edge mode")
	check(selection.ids.size() == 8, "flat 4-face region has outer perimeter of 8 edges (each original edge split), not internal cross")

	for edge_id in selection.ids:
		var incident := PackedInt64Array(solid.call("edge_faces", edge_id))
		var top_count := 0
		for f in incident:
			if top_faces.has(f):
				top_count += 1
		check(top_count == 1, "each boundary edge touches exactly one selected face (outer perimeter)")
	solid.free()


func _check_select_boundary_curved_region() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_cylinder", 1.0, 2.0, 8)
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	var actions := Actions.new(selection, null)

	var side_faces := PackedInt64Array()
	for face_id in solid.call("get_faces"):
		var n: Vector3 = solid.call("face_normal", face_id)
		if absf(n.y) < 0.1:
			side_faces.append(face_id)
	check(side_faces.size() == 8, "8-sided cylinder has 8 side faces")

	selection.set_ids(side_faces)
	actions.run("select_boundary")
	check(selection.mode == Selection.Mode.EDGE, "curved region boundary switches to Edge mode")
	check(selection.ids.size() == 16, "cylinder side band has top and bottom rings = 16 perimeter edges")

	for edge_id in selection.ids:
		var incident := PackedInt64Array(solid.call("edge_faces", edge_id))
		var side_count := 0
		for f in incident:
			if side_faces.has(f):
				side_count += 1
		check(side_count == 1, "each curved boundary edge touches exactly one selected side face")
	solid.free()


func _check_select_boundary_then_bevel() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	var top := 0
	for face_id in solid.call("get_faces"):
		if solid.call("face_normal", face_id).y > 0.9:
			top = face_id
			break
	var undo := Undo.new()
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	var actions := Actions.new(selection, undo)

	selection.set_ids(PackedInt64Array([top]))
	actions.run("select_boundary")
	check(selection.mode == Selection.Mode.EDGE and selection.ids.size() == 4,
		"roof face boundary selects its 4 perimeter edges")

	var boundary_edges := PackedInt64Array(selection.ids)
	var before: PackedByteArray = solid.get("data")
	var before_faces: int = solid.call("face_count")
	solid.call("bevel_edges", boundary_edges, 0.1, 1)
	var after: PackedByteArray = solid.get("data")
	check(after != before, "Bevel from boundary edges changes geometry")
	check(int(solid.call("face_count")) > before_faces, "Bevel adds faces for the rounded perimeter")
	solid.free()


func _adjacent_vertex_pair(solid: Node3D) -> PackedInt64Array:
	var verts: PackedInt64Array = solid.call("get_vertices")
	for edge in solid.call("get_edges"):
		var ends: PackedVector3Array = solid.call("edge_endpoints", edge)
		var v1 := 0
		var v2 := 0
		for v in verts:
			if solid.call("vertex_position", v).is_equal_approx(ends[0]):
				v1 = v
			if solid.call("vertex_position", v).is_equal_approx(ends[1]):
				v2 = v
		if v1 != 0 and v2 != 0:
			return PackedInt64Array([v1, v2])
	return PackedInt64Array()


func _diagonal_vertex_pair(solid: Node3D) -> PackedInt64Array:
	var top := 0
	for face_id in solid.call("get_faces"):
		if solid.call("face_normal", face_id).y > 0.9:
			top = face_id
			break
	if top == 0:
		return PackedInt64Array()
	var face_verts := PackedInt64Array()
	var vertices: PackedInt64Array = solid.call("get_vertices")
	for edge in solid.call("face_edges", top):
		var ends: PackedVector3Array = solid.call("edge_endpoints", edge)
		for v in vertices:
			var pos: Vector3 = solid.call("vertex_position", v)
			if pos.is_equal_approx(ends[0]) or pos.is_equal_approx(ends[1]):
				if not face_verts.has(v):
					face_verts.append(v)
	if face_verts.size() < 4:
		return PackedInt64Array()
	return PackedInt64Array([face_verts[0], face_verts[2]])


func _check_weld_collapse() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.VERTEX
	var undo := Undo.new()
	var actions := Actions.new(selection, undo)
	var reports: Array[String] = []
	actions.reported.connect(func(message: String) -> void: reports.append(message))
	var pair: PackedInt64Array = _adjacent_vertex_pair(solid)
	check(pair.size() == 2, "weld/collapse fixture has an adjacent pair")
	if pair.size() != 2:
		solid.free()
		return
	selection.set_ids(pair)
	var before: PackedByteArray = solid.get("data")
	actions.amount = 0.5
	actions.run("weld_vertices")
	check(solid.get("data") == before and undo.actions.is_empty(), "Weld at 0.5 m leaves 2 m neighbours and writes no history")
	check(not reports.is_empty() and reports[-1].contains("did not change"), "distant Weld reports a no-op")
	reports.clear()
	actions.amount = 2.5
	actions.run("weld_vertices")
	check(solid.get("data") != before and solid.call("get_vertices").size() == 7, "Weld at 2.5 m merges the adjacent pair")
	undo.undo()
	check(solid.get("data") == before, "Weld Undo restores the original box")

	var diagonal: PackedInt64Array = _diagonal_vertex_pair(solid)
	check(diagonal.size() == 2, "weld refusal fixture has a face diagonal")
	if diagonal.size() == 2:
		selection.set_ids(diagonal)
		var history_size := undo.actions.size()
		actions.amount = 4.0
		reports.clear()
		actions.run("weld_vertices")
		check(solid.get("data") == before and undo.actions.size() == history_size, "pinching Weld preserves data and history")
		check(not reports.is_empty() and reports[-1].contains("pinch"), "pinching Weld explains the refusal")

	selection.set_ids(pair)
	var collapse_before: PackedByteArray = solid.get("data")
	actions.run("collapse_vertices")
	check(solid.get("data") != collapse_before and solid.call("get_vertices").size() < 8, "Collapse of two vertices reduces the count")
	undo.undo()
	check(solid.get("data") == collapse_before, "Collapse Undo restores the original box")
	solid.free()


func _check_concave_prism_ops() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	var poly := PackedVector3Array([
		Vector3(0, 0, 4), Vector3(1, 0, 4), Vector3(1, 0, 1), Vector3(3, 0, 1),
		Vector3(3, 0, 4), Vector3(4, 0, 4), Vector3(4, 0, 0), Vector3(0, 0, 0),
	])
	check(solid.call("make_prism", poly, 2.0) == 0, "concave C prism builds")
	var top := 0
	for face_id in solid.call("get_faces"):
		if solid.call("face_normal", face_id).y > 0.9:
			top = face_id
			break
	check(top != 0, "concave prism has a top face")
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	var undo := Undo.new()
	var actions := Actions.new(selection, undo)
	var reports: Array[String] = []
	actions.reported.connect(func(message: String) -> void: reports.append(message))
	selection.set_ids(PackedInt64Array([top]))
	var before: PackedByteArray = solid.get("data")
	var faces_before: int = solid.call("face_count")
	actions.run("subdivide_faces")
	var subdivided: bool = solid.get("data") != before
	check(subdivided or not reports.is_empty(), "concave Subdivide splits the cap or explains refusal")
	if subdivided:
		check(int(solid.call("face_count")) > faces_before, "concave Subdivide adds faces")
		undo.undo()
		check(solid.get("data") == before, "concave Subdivide Undo restores the prism")

	selection.mode = Selection.Mode.VERTEX
	var pair: PackedInt64Array = _adjacent_vertex_pair(solid)
	check(pair.size() == 2, "concave prism has an adjacent pair")
	if pair.size() != 2:
		solid.free()
		return
	selection.set_ids(pair)
	var verts_before: int = solid.call("get_vertices").size()
	actions.run("collapse_vertices")
	check(solid.call("get_vertices").size() < verts_before, "Collapse reduces vertices on a concave prism")
	undo.undo()
	check(solid.get("data") == before, "concave Collapse Undo restores the prism")
	actions.amount = 4.5
	actions.run("weld_vertices")
	check(solid.get("data") != before and solid.call("get_vertices").size() < verts_before, "Weld merges an adjacent pair on a concave prism")
	solid.free()
