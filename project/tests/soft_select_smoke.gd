extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Controls := preload("res://addons/slab/slab_selection_controls.gd")
const SoftSelect := preload("res://addons/slab/slab_soft_select.gd")
const ElementXform := preload("res://addons/slab/slab_element_xform.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_soft_select_state()
	_test_soft_select_object_mode_disabled()
	_test_weight_computation()
	_test_weighted_transform()
	_test_soft_select_off_hard_only()
	_test_chrome_sync()
	_test_isolate_coexistence()
	print("soft_select_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("ok " if ok else "FAIL ", message)


func _test_soft_select_state() -> void:
	var selection := Selection.new()
	check(not selection.soft_select, "soft_select starts off")
	check(is_equal_approx(selection.soft_radius, 0.5), "soft_radius default is 0.5")
	check(selection.soft_falloff == Selection.Falloff.SMOOTH, "soft_falloff default is SMOOTH")
	selection.set_soft_select(true)
	check(selection.soft_select, "set_soft_select enables")
	selection.set_soft_select(false)
	check(not selection.soft_select, "set_soft_select disables")
	selection.set_soft_radius(1.5)
	check(is_equal_approx(selection.soft_radius, 1.5), "set_soft_radius changes radius")
	selection.set_soft_radius(0.0)
	check(selection.soft_radius >= 0.01, "soft_radius clamps to minimum")
	selection.set_soft_falloff(Selection.Falloff.LINEAR)
	check(selection.soft_falloff == Selection.Falloff.LINEAR, "set_soft_falloff changes falloff")
	selection.set_soft_falloff(-1)
	check(selection.soft_falloff == Selection.Falloff.LINEAR, "invalid falloff is rejected")


func _test_soft_select_object_mode_disabled() -> void:
	var selection := Selection.new()
	check(selection.mode == Selection.Mode.OBJECT, "default mode is Object")
	check(not selection.soft_select_allowed(), "soft_select not allowed in Object mode")
	selection.mode = Selection.Mode.VERTEX
	check(selection.soft_select_allowed(), "soft_select allowed in Vertex mode")
	selection.mode = Selection.Mode.EDGE
	check(selection.soft_select_allowed(), "soft_select allowed in Edge mode")
	selection.mode = Selection.Mode.FACE
	check(selection.soft_select_allowed(), "soft_select allowed in Face mode")
	selection.mode = Selection.Mode.OBJECT
	check(not selection.soft_select_allowed(), "soft_select not allowed after returning to Object mode")


func _test_weight_computation() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		print("SlabSolid class not available; skipping weight tests")
		return
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var top_face: int = 0
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9:
			top_face = face
			break
	check(top_face != 0, "found top face of box")
	var top_verts: PackedInt64Array = solid.call("face_vertices", top_face)
	var neighbor_verts: PackedInt64Array = PackedInt64Array()
	for face in solid.call("get_faces"):
		if face != top_face:
			for v in solid.call("face_vertices", face):
				if not top_verts.has(v) and neighbor_verts.find(v) == -1:
					neighbor_verts.append(v)
	check(not neighbor_verts.is_empty(), "box has neighbor vertices outside top face")
	var weights: Dictionary = SoftSelect.compute_weights(solid, Selection.Mode.FACE,
		PackedInt64Array([top_face]), 2.5, Selection.Falloff.SMOOTH)
	check(not weights.is_empty(), "weight computation returns weights")
	for v in top_verts:
		check(weights.has(v) and is_equal_approx(weights[v], 1.0),
			"selected face vertices have weight 1.0")
	var has_partial := false
	for v in neighbor_verts:
		if weights.has(v) and weights[v] < 1.0 and weights[v] > 0.0:
			has_partial = true
			break
	check(has_partial, "some neighbors have partial weights within radius")
	var weights_zero_radius: Dictionary = SoftSelect.compute_weights(solid, Selection.Mode.FACE,
		PackedInt64Array([top_face]), 0.0, Selection.Falloff.SMOOTH)
	check(weights_zero_radius.is_empty(), "zero radius returns empty weights")
	var weights_empty: Dictionary = SoftSelect.compute_weights(solid, Selection.Mode.FACE,
		PackedInt64Array(), 1.0, Selection.Falloff.SMOOTH)
	check(weights_empty.is_empty(), "empty selection returns empty weights")
	solid.free()


func _test_weighted_transform() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		print("SlabSolid class not available; skipping transform tests")
		return
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var data_before: PackedByteArray = solid.get("data")
	var top_face: int = 0
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9:
			top_face = face
			break
	var hard_verts: PackedInt64Array = ElementXform.vertices(solid, Selection.Mode.FACE,
		PackedInt64Array([top_face]))
	var neighbor_verts: PackedInt64Array = PackedInt64Array()
	for face in solid.call("get_faces"):
		if face != top_face:
			for v in solid.call("face_vertices", face):
				if not hard_verts.has(v) and neighbor_verts.find(v) == -1:
					neighbor_verts.append(v)
	var weights: Dictionary = SoftSelect.compute_weights(solid, Selection.Mode.FACE,
		PackedInt64Array([top_face]), 2.5, Selection.Falloff.SMOOTH)
	check(not weights.is_empty(), "weights computed for transform test")
	var has_partial_weight := false
	for v in neighbor_verts:
		if weights.has(v) and weights[v] > 0.0 and weights[v] < 1.0:
			has_partial_weight = true
			break
	check(has_partial_weight, "transform test has partial-weight neighbors")
	var hard_center_before := Vector3.ZERO
	for v in hard_verts:
		hard_center_before += solid.vertex_position(v)
	hard_center_before /= float(hard_verts.size())
	var neighbor_center_before := Vector3.ZERO
	for v in neighbor_verts:
		neighbor_center_before += solid.vertex_position(v)
	neighbor_center_before /= float(neighbor_verts.size())
	var xform := Transform3D.IDENTITY.translated(Vector3(0, 0.5, 0))
	var err: int = ElementXform.transform_weighted(solid, xform, weights)
	check(err == OK, "weighted transform returns OK")
	var data_after: PackedByteArray = solid.get("data")
	check(data_after != data_before, "weighted transform changes geometry")
	var hard_center_after := Vector3.ZERO
	for v in hard_verts:
		hard_center_after += solid.vertex_position(v)
	hard_center_after /= float(hard_verts.size())
	var neighbor_center_after := Vector3.ZERO
	for v in neighbor_verts:
		neighbor_center_after += solid.vertex_position(v)
	neighbor_center_after /= float(neighbor_verts.size())
	var hard_delta_y: float = hard_center_after.y - hard_center_before.y
	var neighbor_delta_y: float = neighbor_center_after.y - neighbor_center_before.y
	check(hard_delta_y > 0.4, "full-weight vertices move by approximately full amount")
	check(neighbor_delta_y > 0.0, "partial-weight neighbors do move")
	check(neighbor_delta_y < hard_delta_y * 0.5,
		"partial-weight neighbors move less than full-weight vertices")
	solid.free()


func _test_soft_select_off_hard_only() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		print("SlabSolid class not available; skipping soft select off test")
		return
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var top_face: int = 0
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9:
			top_face = face
			break
	var hard_verts: PackedInt64Array = ElementXform.vertices(solid, Selection.Mode.FACE,
		PackedInt64Array([top_face]))
	var neighbor_verts: PackedInt64Array = PackedInt64Array()
	for face in solid.call("get_faces"):
		if face != top_face:
			for v in solid.call("face_vertices", face):
				if not hard_verts.has(v) and neighbor_verts.find(v) == -1:
					neighbor_verts.append(v)
	var neighbor_positions_before: Array[Vector3] = []
	for v in neighbor_verts:
		neighbor_positions_before.append(solid.vertex_position(v))
	var xform := Transform3D.IDENTITY.translated(Vector3(0, 0.5, 0))
	var err: int = ElementXform.transform(solid, Selection.Mode.FACE,
		PackedInt64Array([top_face]), xform)
	check(err == OK, "hard-only transform returns OK")
	var neighbors_unchanged := true
	for i in neighbor_verts.size():
		var pos_after: Vector3 = solid.vertex_position(neighbor_verts[i])
		if not pos_after.is_equal_approx(neighbor_positions_before[i]):
			neighbors_unchanged = false
			break
	check(neighbors_unchanged, "soft select off: neighbors do not move")
	solid.free()


func _test_chrome_sync() -> void:
	var selection := Selection.new()
	var controls := Controls.new()
	controls.setup(selection)
	root.add_child(controls)
	var soft_btn: Button = controls.get_node("SoftSelect")
	var soft_opts: HBoxContainer = controls.get_node("SoftSelectOptions")
	check(soft_btn != null, "SoftSelect button exists")
	check(soft_opts != null, "SoftSelectOptions container exists")
	check(soft_btn.disabled, "SoftSelect disabled in Object mode")
	check(not soft_opts.visible, "SoftSelectOptions hidden in Object mode")
	check(soft_btn.tooltip_text.contains("Vertex"), "Object mode tooltip mentions element modes")
	selection.mode = Selection.Mode.FACE
	selection.settings_changed.emit()
	check(not soft_btn.disabled, "SoftSelect enabled in Face mode")
	check(not soft_opts.visible, "SoftSelectOptions hidden when soft select off")
	selection.set_soft_select(true)
	check(soft_opts.visible, "SoftSelectOptions visible when soft select on")
	check(soft_btn.button_pressed, "SoftSelect button pressed when enabled")
	var radius: SpinBox = soft_opts.get_node("SoftRadius")
	var falloff: OptionButton = soft_opts.get_node("SoftFalloff")
	check(radius != null, "SoftRadius spin exists")
	check(falloff != null, "SoftFalloff option exists")
	check(is_equal_approx(radius.value, selection.soft_radius), "radius spin shows current radius")
	check(falloff.selected == selection.soft_falloff, "falloff option shows current falloff")
	radius.value = 2.5
	radius.value_changed.emit(2.5)
	check(is_equal_approx(selection.soft_radius, 2.5), "radius spin updates selection")
	falloff.item_selected.emit(Selection.Falloff.LINEAR)
	check(selection.soft_falloff == Selection.Falloff.LINEAR, "falloff option updates selection")
	selection.mode = Selection.Mode.OBJECT
	selection.settings_changed.emit()
	check(soft_btn.disabled, "SoftSelect disabled when returning to Object mode")
	check(not soft_opts.visible, "SoftSelectOptions hidden when returning to Object mode")
	controls.free()


func _test_isolate_coexistence() -> void:
	var selection := Selection.new()
	if not ClassDB.class_exists("SlabSolid"):
		print("SlabSolid class not available; skipping isolation coexistence test")
		return
	var scene := Node3D.new()
	root.add_child(scene)
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.name = "CoexistTest"
	solid.call("make_box", Vector3.ONE)
	scene.add_child(solid)
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	selection.enter_isolation(scene)
	check(selection.isolated, "entered isolation")
	selection.set_soft_select(true)
	check(selection.soft_select, "soft select enabled while isolated")
	check(selection.isolated and selection.soft_select, "isolation and soft select both active")
	selection.set_soft_select(false)
	check(not selection.soft_select, "soft select toggled off")
	check(selection.isolated, "isolation remains after soft select toggle")
	selection.exit_isolation()
	check(not selection.isolated, "exited isolation")
	scene.free()
