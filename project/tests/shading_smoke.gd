extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const TestUndo := preload("res://tests/slab_test_undo.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
	print("%s %s" % ["PASS" if value else "FAIL", label])

func normals(solid: Node3D) -> PackedVector3Array:
	var mesh: ArrayMesh = solid.call("build_mesh")
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]

func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3.ONE)
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	var faces: PackedInt64Array = solid.call("get_faces")
	selection.set_ids(faces)
	var undo := TestUndo.new()
	var actions := Actions.new(selection, undo)
	var original: PackedByteArray = solid.get("data")
	var flat := normals(solid)
	actions.run("shade_smooth")
	var smooth: PackedByteArray = solid.get("data")
	var blended := normals(solid)
	check(smooth != original and undo.actions.size() == 1, "smooth faces commit one atomic edit")
	check(blended != flat, "smooth shading changes actual emitted normals")
	check(selection.ids == faces, "shading preserves selected face identities")
	var all_smooth := true
	for face in faces:
		all_smooth = all_smooth and bool(solid.call("face_uv", face).smooth)
	check(all_smooth, "every selected face becomes smooth")
	undo.undo()
	check(solid.get("data") == original and normals(solid) == flat, "Undo restores exact data and flat normals")
	undo.redo()
	check(solid.get("data") == smooth and normals(solid) == blended, "Redo restores exact smooth normals")
	actions.run("shade_smooth")
	check(undo.actions.size() == 1, "repeating Smooth adds no redundant Undo entry")
	selection.set_ids(PackedInt64Array([faces[0]]))
	actions.run("shade_flat")
	check(not bool(solid.call("face_uv", faces[0]).smooth) and bool(solid.call("face_uv", faces[1]).smooth),
		"Flat affects only selected faces")
	undo.undo()
	selection.mode = Selection.Mode.EDGE
	var edges: PackedInt64Array = solid.call("get_edges")
	selection.set_ids(edges)
	var before_hard := undo.actions.size()
	actions.run("hard_edges")
	var hard: PackedByteArray = solid.get("data")
	check(undo.actions.size() == before_hard + 1 and solid.call("get_hard_edges").size() == edges.size(),
		"Hard Edge marks all selected boundaries in one action")
	check(normals(solid) == flat, "hard boundaries restore the box's face normals while faces remain smooth")
	check(solid.call("get_uv_seams").is_empty(), "hard edges do not introduce UV seams")
	undo.undo()
	check(solid.get("data") == smooth and normals(solid) == blended, "Hard Edge Undo restores smooth emitted normals")
	undo.redo()
	check(solid.get("data") == hard, "Hard Edge Redo restores exact persistent marks")
	selection.set_ids(PackedInt64Array([edges[0]]))
	actions.run("soft_edges")
	check(not solid.call("get_hard_edges").has(edges[0]) and solid.call("get_hard_edges").has(edges[1]),
		"Soft Edge removes only selected hard marks")
	var copy: Node3D = ClassDB.instantiate("SlabSolid")
	copy.set("data", solid.get("data"))
	check(copy.call("get_hard_edges") == solid.call("get_hard_edges") and normals(copy) == normals(solid),
		"serialized data reload preserves shading flags and emitted normals")
	var packed := PackedScene.new()
	check(packed.pack(solid) == OK and ResourceSaver.save(packed, "user://slab_shading_smoke.tscn") == OK,
		"shading authoring saves in a native scene")
	var reloaded := ResourceLoader.load("user://slab_shading_smoke.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := reloaded.instantiate() as Node3D
	check(reopened.get("data") == solid.get("data") and normals(reopened) == normals(solid),
		"scene reopen restores exact shading and rendered normals")
	reopened.free()
	var saved: PackedByteArray = solid.get("data")
	selection.set_ids(PackedInt64Array())
	var before_empty := undo.actions.size()
	actions.run("hard_edges")
	check(solid.get("data") == saved and undo.actions.size() == before_empty, "empty selection cannot mark every edge")
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([faces[0]]))
	check(not actions.disabled_reason(actions.find("hard_edges")).is_empty(), "edge controls require Edge mode")
	actions.operation_active = true
	check(not actions.disabled_reason(actions.find("shade_flat")).is_empty(), "shading cannot interrupt an active geometry preview")
	# Imported custom normals must yield to an explicit edge shading command.
	var authored := ClassDB.instantiate("SlabSolid") as Node3D
	root.add_child(authored)
	var input: ArrayMesh = solid.call("build_mesh")
	var flat_input: Dictionary = preload("res://addons/slab/slab_mesh_attributes.gd").flatten(input)
	for i in flat_input.attributes.normals.size():
		flat_input.attributes.normals[i] = Vector3.UP
	var morph_positions := PackedVector3Array()
	var morph_normals := PackedVector3Array()
	for i in flat_input.vertices.size():
		morph_positions.append(Vector3(0.2, 0, 0))
		morph_normals.append(Vector3(0.1, 0, 0))
	flat_input.attributes.blend_shapes = [{"name": "Offset", "positions": morph_positions, "normals": morph_normals}]
	check(authored.call("import_from_mesh", flat_input.vertices, flat_input.indices, flat_input.uvs, flat_input.slots, flat_input.attributes).error == OK,
		"custom-normal mesh imports")
	var authored_before: PackedByteArray = authored.get("data")
	check(normals(authored)[0].distance_to(Vector3.UP) < 0.0001, "imported authored normals initially control emission")
	check(authored.call("mark_hard_edges", authored.call("get_edges"), true) == OK, "hard edges accept imported mesh")
	var non_up := false
	for normal in normals(authored): non_up = non_up or normal.distance_to(Vector3.UP) > 0.1
	check(non_up, "hard edges replace authored directions with geometric face normals")
	var shaded: ArrayMesh = authored.call("build_mesh")
	var morph_shading_cleared := true
	for surface in shaded.get_surface_count():
		var shapes: Array = shaded.surface_get_blend_shape_arrays(surface)
		var arrays: Array = shaded.surface_get_arrays(surface)
		check(shaded.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED, "morph targets store absolute directions")
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			morph_shading_cleared = morph_shading_cleared and shapes[0][Mesh.ARRAY_NORMAL][vertex].distance_to(arrays[Mesh.ARRAY_NORMAL][vertex]) < 0.0001
			check((shapes[0][Mesh.ARRAY_VERTEX][vertex] - arrays[Mesh.ARRAY_VERTEX][vertex]).is_equal_approx(Vector3(0.2, 0, 0)), "edge shading retains morph position offset")
	check(morph_shading_cleared, "recomputed edge shading replaces morph directions with new base normals")

	authored.set("data", authored_before)
	check(normals(authored)[0].distance_to(Vector3.UP) < 0.0001, "restoring prior data restores authored normals")
	authored.free()
	copy.free()
	solid.free()
	print("shading_smoke failures=", failures)
	quit(1 if failures else 0)
