extends "res://tests/panel_editor_smoke.gd"

# Rendered acceptance for the production inspector/canvas layout. It never saves the fixture.
# scripts/godot --editor --path project --script res://tests/paint_layout_study.gd
func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("Requires --editor")
		return
	var editor := Engine.get_singleton("EditorInterface")
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		await process_frame
	await create_timer(1.5).timeout
	editor.open_scene_from_path("res://demo/modeller_lab.tscn")
	editor.set_main_screen_editor("3D")
	var stable := 0
	var deadline := Time.get_ticks_msec() + 15000
	while stable < 20:
		await process_frame
		var scene: Node = editor.get_edited_scene_root()
		stable = stable + 1 if scene != null and scene.scene_file_path == "res://demo/modeller_lab.tscn" else 0
		if Time.get_ticks_msec() > deadline:
			_fail("Paint layout fixture did not remain current")
			return
	var solid: Node3D = editor.get_edited_scene_root().get_node("Box2")
	editor.get_selection().clear()
	editor.get_selection().add_node(solid)
	editor.edit_node(solid)
	await create_timer(0.5).timeout
	var plugin := _plugin(root)
	var panel: Control = plugin.get("_panel")
	plugin.call("make_bottom_panel_item_visible", panel)
	await create_timer(0.3).timeout
	var selection: RefCounted = plugin.get("_selection")
	selection.set_objects([solid])
	await _click(_mode(panel, 3))
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9:
			selection.set_ids(PackedInt64Array([face]))
			break
	await _click(_button_named(panel, "UV"))
	var picker: Node = panel.find_child("PaintMaterialPicker", true, false)
	var material := ResourceLoader.load("res://demo/signal_foundry/materials/teal_steel.tres") as StandardMaterial3D
	if material == null:
		material = ResourceLoader.load("res://demo/signal_foundry/materials/brick.tres") as StandardMaterial3D
	if picker != null and material != null:
		picker.set("edited_resource", material)
		picker.emit_signal("resource_changed", material)
	await create_timer(0.4).timeout
	var canvas: Control = panel.find_child("PaintCanvas", true, false)
	var material_canvas := _rect_data(canvas)
	var inspector_scroll: ScrollContainer = panel.find_child("PaintInspector", true, false)
	var inspector: VBoxContainer = panel.find_child("PaintInspectorFields", true, false)
	var apply: Button = _button_named(inspector, "Apply UV")
	var inspector_rect := inspector_scroll.get_global_rect()
	var apply_rect := apply.get_global_rect() if apply != null else Rect2()
	var apply_vertical := apply != null and apply.is_visible_in_tree() and apply_rect.position.y >= inspector_rect.position.y and apply_rect.end.y <= inspector_rect.end.y
	var apply_horizontal := apply != null and apply.is_visible_in_tree() and apply_rect.position.x >= inspector_rect.position.x and apply_rect.end.x <= inspector_rect.end.x
	var result := {
		"window": get_root().size,
		"panel": _rect_data(panel),
		"material_canvas": material_canvas,
		"material_inspector": _rect_data(inspector_scroll),
		"inspector_content_height": inspector.get_combined_minimum_size().y,
		"vertical_scroll_required": inspector.get_combined_minimum_size().y > inspector_rect.size.y,
		"apply_uv_visible_vertical": apply_vertical,
		"apply_uv_visible_horizontal": apply_horizontal,
		"picker_width": panel.find_child("PaintMaterialPickerWrap", true, false).get_global_rect().size.x,
	}
	await _capture(editor, {"capture_prefix": "/tmp/slab-paint-layout-material"}, "after")
	await _click(_button_named(panel, "Pixel"))
	await _click(_button_named(panel, "Make Unique"))
	var paint: RefCounted = panel.get("_paint")
	if paint.material() != null and paint.is_owned(paint.material()):
		paint.begin_stroke()
		paint.dab_pixel(Vector2(24, 24))
		paint.dab_pixel(Vector2(48, 36))
		paint.end_stroke()
	await create_timer(0.3).timeout
	result["pixel_canvas"] = _rect_data(canvas)
	result["pixel_inspector"] = _rect_data(inspector_scroll)
	result["pixel_brush_visible"] = panel.get("_paint_brush").is_visible_in_tree()
	var action_wrapper: Control = panel.find_child("PaintActions", true, false)
	var save: Button = _button_named(panel, "Save Paint")
	var help: Label = panel.find_child("PaintHelp", true, false)
	result["pixel_save_enabled"] = save.visible and not save.disabled
	result["pixel_save_inside_actions"] = action_wrapper.get_global_rect().grow(1.0).encloses(save.get_global_rect())
	result["pixel_help_inside_actions"] = action_wrapper.get_global_rect().grow(1.0).encloses(help.get_global_rect())
	await _capture(editor, {"capture_prefix": "/tmp/slab-paint-layout-pixel"}, "after")
	print("SLAB_PAINT_LAYOUT_STUDY ", JSON.stringify(result))
	quit(1 if failures else 0)


func _rect_data(control: Control) -> Dictionary:
	var rect := control.get_global_rect()
	return {"x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y}
