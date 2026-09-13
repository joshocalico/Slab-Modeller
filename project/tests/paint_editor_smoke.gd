extends "res://tests/panel_editor_smoke.gd"

# Rendered editor acceptance. Sends held mouse events through the real GUI.
# scripts/godot --editor --path project --script res://tests/paint_editor_smoke.gd
# The lab scene is never saved.
func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("Requires --editor")
		return
	var editor := Engine.get_singleton("EditorInterface")
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		await process_frame
	# Session restore can reopen the previous scene after the first scan.
	await create_timer(1.5).timeout
	editor.open_scene_from_path("res://demo/modeller_lab.tscn")
	editor.set_main_screen_editor("3D")
	var stable_frames := 0
	var deadline := Time.get_ticks_msec() + 15000
	while stable_frames < 20:
		await process_frame
		var edited: Node = editor.get_edited_scene_root()
		stable_frames = stable_frames + 1 if edited != null and edited.scene_file_path == "res://demo/modeller_lab.tscn" else 0
		if Time.get_ticks_msec() > deadline:
			_fail("Paint fixture did not remain current after session restore")
			return
	await create_timer(1.0).timeout
	var solid: Node3D = editor.get_edited_scene_root().get_node("Box2")
	editor.get_selection().clear()
	editor.get_selection().add_node(solid)
	editor.edit_node(solid)
	await create_timer(0.5).timeout
	var plugin := _plugin(root)
	var panel: Control = plugin.get("_panel")
	plugin.call("make_bottom_panel_item_visible", panel)
	await process_frame
	var selection: RefCounted = plugin.get("_selection")
	selection.set_objects([solid])
	await _click(_mode(panel, 3))
	for id in solid.call("get_faces"):
		if solid.call("face_normal", id).y > 0.9:
			selection.set_ids(PackedInt64Array([id]))
	await _click(_button_named(panel, "Surface Paint"))
	var target_label: Label = panel.get("_paint_face")
	_check(target_label.text.begins_with("%s · 1 face · " % solid.name), "paint_target_names_solid_and_face_count")
	var workspace: Button = panel.find_child("SurfacePaint", true, false)
	_check(workspace.button_pressed and workspace.get_theme_stylebox("hover_pressed").bg_color == panel.ACCENT,
		"paint_workspace_remains_highlighted_while_hovered")
	await _click(_button_named(panel, "Make Unique"))
	_check(_button_named(panel, "Assign").is_visible_in_tree(), "assign_is_visible")
	var picker: Control = panel.find_child("PaintMaterialPicker", true, false)
	var picker_wrap: Control = panel.find_child("PaintMaterialPickerWrap", true, false)
	var resource_button_width := 0.0
	var resource_button: Button
	for child in picker.find_children("*", "Button", true, false):
		if child is Button and child.is_visible_in_tree():
			if child.get_global_rect().size.x > resource_button_width:
				resource_button_width = child.get_global_rect().size.x
				resource_button = child
	_check(picker.is_visible_in_tree() and picker.get_global_rect().size.x >= 200.0, "material_picker_is_visible")
	_check(picker_wrap.get_global_rect().encloses(picker.get_global_rect()), "material_picker_fits_its_slot")
	_check(resource_button_width >= 120.0, "material_picker_resource_button_is_readable")
	var imported := ResourceLoader.load("res://demo/signal_foundry/materials/brick.tres") as StandardMaterial3D
	var before_picker_materials: Array = (solid.get("materials") as Array).duplicate()
	var before_picker_data: PackedByteArray = solid.get("data")
	var before_picker_target: String = target_label.text
	picker.set("edited_resource", imported)
	picker.emit_signal("resource_changed", imported)
	await create_timer(0.2).timeout
	_check(panel.get("_paint").brush_material() == imported, "material picker chooses an imported preview brush")
	_check(solid.get("materials") == before_picker_materials and solid.get("data") == before_picker_data
		and target_label.text == before_picker_target,
		"material picker choice leaves slots, face data, and target context unchanged")
	await _click(resource_button)
	await create_timer(0.2).timeout
	_check(editor.get_inspector().get_edited_object() == imported,
		"clicking the picker resource opens the chosen brush in the Inspector")
	await _click(_button_named(panel, "Assign"))
	var assigned_picker_materials: Array = (solid.get("materials") as Array).duplicate()
	var assigned_picker_data: PackedByteArray = solid.get("data")
	_check(assigned_picker_data != before_picker_data and panel.get("_paint").selected_material_summary() == "Brick",
		"Assign applies the chosen picker brush")
	await _history_shortcut(panel, false)
	_check(solid.get("materials") == before_picker_materials and solid.get("data") == before_picker_data,
		"picker brush assignment Undo restores exact slots and face data")
	await _history_shortcut(panel, true)
	_check(solid.get("materials") == assigned_picker_materials and solid.get("data") == assigned_picker_data,
		"picker brush assignment Redo restores the assignment")
	var editable_preview := StandardMaterial3D.new()
	picker.set("edited_resource", editable_preview)
	picker.emit_signal("resource_changed", editable_preview)
	await create_timer(0.2).timeout
	await _click(resource_button)
	await create_timer(0.2).timeout
	var albedo_editor: Control
	for inspector_control in editor.get_inspector().find_children("*", "Control", true, false):
		if String(inspector_control.tooltip_text) == "property|BaseMaterial3D|albedo_color":
			albedo_editor = inspector_control
			break
	var color_button: ColorPickerButton
	if albedo_editor != null:
		var color_buttons: Array[Node] = albedo_editor.find_children("*", "ColorPickerButton", true, false)
		if not color_buttons.is_empty():
			color_button = color_buttons[0] as ColorPickerButton
	var before_inspector_materials: Array = (solid.get("materials") as Array).duplicate()
	var before_inspector_data: PackedByteArray = solid.get("data")
	var copper := Color("c98239")
	var inspector_edits: Array[String] = []
	var record_inspector_edit := func(property: String) -> void: inspector_edits.append(property)
	editor.get_inspector().property_edited.connect(record_inspector_edit)
	if color_button != null:
		color_button.color = copper
		albedo_editor.call("emit_changed", "albedo_color", copper, "", false)
	await create_timer(0.3).timeout
	editor.get_inspector().property_edited.disconnect(record_inspector_edit)
	var preview_pixel: Color = panel.get("_paint").image().get_pixel(0, 0)
	_check(color_button != null and editable_preview.albedo_color.is_equal_approx(copper),
		"the real Inspector Albedo Color control edits the chosen brush")
	_check(inspector_edits.has("albedo_color"), "the Inspector publishes the Albedo Color property edit")
	_check(preview_pixel.is_equal_approx(copper),
		"Inspector property editing refreshes Paint preview pixels without Resource.emit_changed")
	_check(solid.get("materials") == before_inspector_materials and solid.get("data") == before_inspector_data,
		"Inspector preview editing leaves solid slots and face data unchanged")
	var actions_row: Control = panel.find_child("PaintActions", true, false)
	var thumbnail: TextureRect
	for child in picker.find_children("*", "TextureRect", true, false):
		if child is TextureRect and child.is_visible_in_tree():
			thumbnail = child
			break
	_check(picker_wrap.get_global_rect().encloses(picker.get_global_rect()), "loaded_material_picker_fits_its_slot")
	var paint_inspector: Control = panel.find_child("PaintInspector", true, false)
	_check(paint_inspector.get_global_rect().grow(1.0).encloses(picker_wrap.get_global_rect()), "loaded_material_picker_fits_paint_inspector")
	_check(actions_row.get_global_rect().grow(1.0).encloses(picker_wrap.get_global_rect()), "loaded_material_picker_fits_complete_action_wrapper")
	_check(thumbnail != null and picker.get_global_rect().encloses(thumbnail.get_global_rect()), "loaded_material_thumbnail_is_fully_visible")
	await _capture(editor, {"capture_prefix": "/tmp/slab-paint-picker", "capture_rect": panel.get_global_rect()}, "after")
	var paint: RefCounted = panel.get("_paint")
	var canvas: Control = panel.find_child("PaintCanvas", true, false)
	var distinct_brush := StandardMaterial3D.new()
	distinct_brush.resource_name = "Unwrap identity probe"
	paint.set("_brush_material", distinct_brush)
	var brush_before_unwrap: Material = paint.brush_material()
	var loops_before_unwrap: Array = paint.selected_uv_loops().duplicate(true)
	panel.get("_actions").uv_pixels_per_meter = 16.0
	panel.get("_actions").uv_texture_resolution = 2048
	var unwrap_button: Button = panel.find_child("PaintUnwrap", true, false) as Button
	var paint_inspector_scroll: ScrollContainer = panel.find_child("PaintInspector", true, false)
	paint_inspector_scroll.ensure_control_visible(unwrap_button)
	await process_frame
	await _click(unwrap_button)
	await create_timer(0.2).timeout
	var loops_after_unwrap: Array = paint.selected_uv_loops()
	_check(loops_after_unwrap != loops_before_unwrap, "Unwrap refreshes the canvas from the new UV loops")
	var canvas_lo := Vector2(INF, INF)
	var canvas_hi := Vector2(-INF, -INF)
	for loop: PackedVector2Array in loops_after_unwrap:
		for uv: Vector2 in loop:
			var mapped: Vector2 = canvas.call("_uv_to_canvas", uv)
			canvas_lo = canvas_lo.min(mapped)
			canvas_hi = canvas_hi.max(mapped)
	_check(((canvas_lo + canvas_hi) * 0.5).distance_to(canvas.size * 0.5) <= 2.0,
		"Unwrap reframes the new UV bounds at the canvas centre")
	_check(panel.find_child("PaintMappingState", true, false).text == "Unwrapped mapping",
		"Unwrap refreshes the visible Mapping state")
	_check(brush_before_unwrap != paint.material() and paint.brush_material() == brush_before_unwrap,
		"Unwrap refresh preserves the chosen brush resource")
	paint_inspector_scroll.ensure_control_visible(panel.find_child("PaintMapping", true, false))
	await process_frame
	await _capture(editor, {"capture_prefix": "/tmp/slab-paint-mapping", "capture_rect": panel.get_global_rect()}, "after")
	await _pending_uv_value(panel, solid, selection)
	var before: PackedByteArray = solid.get("data")
	await _uv_gesture(canvas, true)
	_check(solid.get("data") == before and not paint.uv_drag_active and paint.active, "escape_cancels_uv_without_closing_workspace")
	await _uv_gesture(canvas, false)
	var after: PackedByteArray = solid.get("data")
	_check(after != before and not paint.uv_drag_active, "release_commits_uv")
	await _history_shortcut(panel, false)
	_check(solid.get("data") == before, "editor_undo_restores_uv")
	_check(panel.get("_status").text == selection.describe(), "undo_replaces_stale_tool_report_with_current_selection")
	await _history_shortcut(panel, true)
	_check(solid.get("data") == after, "editor_redo_restores_uv")
	await _click(_mode(panel, 3))
	_check(not paint.active and selection.mode == 3, "same_face_mode_button_leaves_paint")
	_check(not workspace.button_pressed and workspace.get_theme_stylebox("normal").bg_color != panel.ACCENT,
		"leaving_paint_clears_workspace_highlight")
	await _click(_button_named(panel, "Surface Paint"))
	await _click(_mode(panel, 2))
	_check(not paint.active and selection.mode == 2 and panel.get("_model_body").visible, "edge_button_returns_to_modelling")
	await _click(_mode(panel, 3))
	for id in solid.call("get_faces"):
		if solid.call("face_normal", id).y > 0.9:
			selection.set_ids(PackedInt64Array([id]))
	await _click(_button_named(panel.find_child("Commands", true, false), "Inset"))
	_check(plugin.get("_actions").operation_active, "mode_transition_fixture_has_preview")
	await _click(_mode(panel, 3))
	_check(not plugin.get("_actions").operation_active and solid.get("data") == after, "same_mode_cancels_preview_without_edit")
	await _click(_button_named(panel, "Surface Paint"))
	var viewport: SubViewport = editor.get_editor_viewport_3d(0)
	solid.position += Vector3(15, 0, 0)
	var camera_before: Transform3D = viewport.get_camera_3d().global_transform
	var frame := InputEventKey.new()
	frame.keycode = KEY_F
	frame.physical_keycode = KEY_F
	frame.unicode = 102
	frame.pressed = true
	var surface: Control = _surface(viewport.get_parent().get_parent())
	surface.grab_focus()
	surface.get_viewport().push_input(frame)
	await create_timer(0.5).timeout
	_check(paint.active and viewport.get_camera_3d().global_transform != camera_before, "frame_selection_works_while_painting")
	await _click(_button_named(panel, "Pixel"))
	var save: Button = _button_named(panel, "Save Paint")
	var help: Label = panel.find_child("PaintHelp", true, false)
	_check(save.visible and actions_row.get_global_rect().grow(1.0).encloses(save.get_global_rect()), "pixel_save_fits_complete_action_wrapper")
	_check(help.visible and actions_row.get_global_rect().grow(1.0).encloses(help.get_global_rect()), "pixel_help_fits_complete_action_wrapper")
	await _capture(editor, {"capture_prefix": "/tmp/slab-paint-editor"}, "after")
	print("SLAB_PAINT_EDITOR ", JSON.stringify({"failures": failures}))
	quit(1 if failures else 0)


func _pending_uv_value(panel: Control, solid: Node3D, selection: RefCounted) -> void:
	var before: PackedByteArray = solid.get("data")
	var field: Node = panel.find_child("paint_uv_rotation", true, false)
	var spin: SpinBox = field.find_children("*", "SpinBox", true, false)[0]
	spin.get_line_edit().grab_focus()
	spin.get_line_edit().text = "15"
	await _click(_button_named(panel.find_child("PaintUvControls", true, false), "Apply UV"))
	var rotation: float = solid.call("face_uv", selection.ids[0]).get("rotation", 0.0)
	_check(is_equal_approx(rotation, deg_to_rad(15.0)), "apply_uv_uses_typed_rotation_without_enter")
	var after: PackedByteArray = solid.get("data")
	if after == before:
		return
	await _history_shortcut(panel, false)
	_check(solid.get("data") == before, "typed_uv_apply_is_one_undo_action")
	await _history_shortcut(panel, true)
	_check(solid.get("data") == after, "typed_uv_apply_redo_restores_exact_data")
	await _history_shortcut(panel, false)

func _history_shortcut(panel: Control, redo: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_Z
	key.physical_keycode = KEY_Z
	key.meta_pressed = OS.get_name() == "macOS"
	key.ctrl_pressed = OS.get_name() != "macOS"
	key.shift_pressed = redo
	key.pressed = true
	panel.get_viewport().push_input(key)
	key = key.duplicate()
	key.pressed = false
	panel.get_viewport().push_input(key)
	await create_timer(0.2).timeout


func _uv_gesture(canvas: Control, cancel_drag: bool) -> void:
	var start: Vector2 = canvas.global_position + canvas.image_rect().get_center()
	var end := start + Vector2(25, 15)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	canvas.get_viewport().push_input(press)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = end
	motion.global_position = end
	motion.relative = end - start
	canvas.get_viewport().push_input(motion)
	await process_frame
	_check(canvas.get("_paint").uv_drag_active, "canvas_mouse_drag_started")
	if cancel_drag:
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		canvas.get_viewport().push_input(escape)
		await process_frame
	press.pressed = false
	press.button_mask = 0
	press.position = end
	press.global_position = end
	canvas.get_viewport().push_input(press)
	await create_timer(0.2).timeout
