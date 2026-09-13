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
