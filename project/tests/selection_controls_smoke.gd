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
	controls.get_node("AxesChoice").item_selected.emit(2)
	passed = passed and selection.orientation == Selection.Orientation.FACE
	controls.get_node("XRaySelection").toggled.emit(true)
	passed = passed and selection.xray
	selection.set_ids(PackedInt64Array([10, 20]))
	passed = passed and selection.active_id == 20
	selection.clear_ids()
	passed = passed and selection.active_id == 0
	print("selection_controls_smoke: ", "PASS" if passed else "FAIL")
	controls.free()
	quit(0 if passed else 1)
