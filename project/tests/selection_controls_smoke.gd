extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Controls := preload("res://addons/slab/slab_selection_controls.gd")

func _initialize() -> void:
	var selection := Selection.new()
	var controls := Controls.new()
	controls.setup(selection)
	root.add_child(controls)
	var passed := selection.pivot_mode == Selection.Pivot.SELECTION and not selection.xray
	controls.get_node("PivotChoice").item_selected.emit(2)
	controls.get_node("CustomPivot/PivotX").value = 2.125
	controls.get_node("CustomPivot/PivotX").value_changed.emit(2.125)
	passed = passed and selection.pivot_mode == Selection.Pivot.CUSTOM
	passed = passed and is_equal_approx(selection.custom_pivot_world.x, 2.125)
	selection.configure_pivot(Selection.Pivot.CUSTOM, Vector3(3.5, -1.25, 8.0))
	passed = passed and is_equal_approx(controls.get_node("CustomPivot/PivotX").value, 3.5)
	passed = passed and is_equal_approx(controls.get_node("CustomPivot/PivotY").value, -1.25)
	passed = passed and is_equal_approx(controls.get_node("CustomPivot/PivotZ").value, 8.0)
	controls.get_node("AxesChoice").item_selected.emit(2)
	passed = passed and selection.orientation == Selection.Orientation.FACE
	controls.get_node("XRaySelection").toggled.emit(true)
	passed = passed and selection.xray
	selection.set_ids(PackedInt64Array([10, 20]))
	passed = passed and selection.active_id == 20
	selection.clear_ids()
	passed = passed and selection.active_id == 0
	passed = passed and _test_isolation(selection)
	print("selection_controls_smoke: ", "PASS" if passed else "FAIL")
	controls.free()
	quit(0 if passed else 1)


func _test_isolation(selection: Selection) -> bool:
	if not ClassDB.class_exists("SlabSolid"):
		print("SlabSolid class not available; skipping isolation tests")
		return true
	var scene := Node3D.new()
	root.add_child(scene)
	var solid_a: Node3D = ClassDB.instantiate("SlabSolid")
	solid_a.name = "IsolateTestA"
	solid_a.call("make_box", Vector3.ONE)
	scene.add_child(solid_a)
	var solid_b: Node3D = ClassDB.instantiate("SlabSolid")
	solid_b.name = "IsolateTestB"
	solid_b.call("make_box", Vector3.ONE)
	solid_b.position.x = 3.0
	scene.add_child(solid_b)
	var solid_c: Node3D = ClassDB.instantiate("SlabSolid")
	solid_c.name = "IsolateTestC"
	solid_c.call("make_box", Vector3.ONE)
	solid_c.position.x = 6.0
	scene.add_child(solid_c)

	var passed := true
	passed = passed and solid_a.visible and solid_b.visible and solid_c.visible
	if not passed:
		print("FAIL: Initial solids should be visible")

	selection.set_objects([solid_a])
	passed = passed and not selection.isolated
	if not passed:
		print("FAIL: Selection should not be isolated initially")

	var entered := selection.enter_isolation(scene)
	passed = passed and entered and selection.isolated
	if not passed:
		print("FAIL: enter_isolation should succeed and set isolated=true")
	passed = passed and solid_a.visible
	if not passed:
		print("FAIL: Selected solid should remain visible after isolation")
	passed = passed and not solid_b.visible and not solid_c.visible
	if not passed:
		print("FAIL: Non-selected solids should be hidden after isolation")

	var top_face: int = 0
	for face_id in solid_a.call("get_faces"):
		if solid_a.call("face_normal", face_id).y > 0.9:
			top_face = face_id
			break
	var data_before: PackedByteArray = solid_a.get("data")
	var err: int = solid_a.call("extrude_faces", PackedInt64Array([top_face]), 0.5)
	var data_after: PackedByteArray = solid_a.get("data")
	passed = passed and err == OK and data_after != data_before
	if not passed:
		print("FAIL: Modelling ops should work on isolated solid, err=%d" % err)

	selection.exit_isolation()
	passed = passed and not selection.isolated
	if not passed:
		print("FAIL: exit_isolation should set isolated=false")
	passed = passed and solid_a.visible and solid_b.visible and solid_c.visible
	if not passed:
		print("FAIL: All solids should be visible after exiting isolation")

	var toggled := selection.toggle_isolation(scene)
	passed = passed and toggled and selection.isolated
	if not passed:
		print("FAIL: toggle_isolation should enter isolation")
	toggled = selection.toggle_isolation(scene)
	passed = passed and not toggled and not selection.isolated
	if not passed:
		print("FAIL: toggle_isolation should exit isolation")
	passed = passed and solid_a.visible and solid_b.visible and solid_c.visible
	if not passed:
		print("FAIL: All solids visible after toggle exit")

	selection.enter_isolation(scene)
	selection.set_objects([solid_b])
	selection.exit_isolation()
	passed = passed and solid_a.visible and solid_b.visible and solid_c.visible
	if not passed:
		print("FAIL: Changing selection and exiting should restore all solids")

	scene.free()
	return passed
