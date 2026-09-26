extends "res://tests/panel_editor_smoke.gd"

# Rendered editor acceptance. Sends held mouse events through the real GUI.
# scripts/godot --editor --path project --script res://tests/paint_editor_smoke.gd
# The lab scene is never saved. Temporary PNGs are removed at teardown.

var _paint_test_panel: Control
var _paint_test_editor: Object
var _original_window_size := Vector2i.ZERO
var _original_window_mode: int
var _original_window_position := Vector2i.ZERO
var _created_pngs: Array[String] = []


func _initialize() -> void:
	create_timer(180.0).timeout.connect(func() -> void: _fail("Paint editor test exceeded 180 seconds"))
	_run.call_deferred()


func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("Requires --editor")
		return
	var editor := Engine.get_singleton("EditorInterface")
	_paint_test_editor = editor
	var startup_deadline := Time.get_ticks_msec() + 30000
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		if Time.get_ticks_msec() > startup_deadline:
			_fail("Paint editor initialization timed out")
			return
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
	_paint_test_panel = panel
	_original_window_size = root.size
	_original_window_mode = root.mode
	_original_window_position = root.position
	await _set_test_window(panel, Vector2i(1440, 800))
	plugin.call("make_bottom_panel_item_visible", panel)
	await process_frame
	var selection: RefCounted = plugin.get("_selection")
	selection.set_objects([solid])
	await _click(_mode(panel, 3))
	for id in solid.call("get_faces"):
		if solid.call("face_normal", id).y > 0.9:
			selection.set_ids(PackedInt64Array([id]))
	_check(not solid.has_meta("_edit_lock_"), "solid_unlocked_before_paint")
	await _click(_button_named(panel, "UV"))
	await _wait_layout([panel, panel.find_child("PaintInspector", true, false), panel.find_child("PaintCanvas", true, false)])
	_check(solid.has_meta("_edit_lock_") and solid.get_meta("_edit_lock_") == true,
		"uv_entry_hides_native_gizmo_via_edit_lock")
	_check_transform_gizmos_hidden(plugin, solid, "UV entry")
	_check(panel.current_workspace() == panel.Workspace.UV, "uv_button_enters_uv_workspace")
	var target_label: Label = panel.get("_paint_face")
	_check(target_label.text.begins_with("%s · 1 face · " % solid.name), "paint_target_names_solid_and_face_count")
	var uv_workspace: Button = panel.find_child("UVWorkspace", true, false)
	_check(uv_workspace.button_pressed and uv_workspace.get_theme_stylebox("hover_pressed").bg_color == panel.ACCENT,
		"uv_workspace_remains_highlighted_while_hovered")
	await _click(_button_named(panel, "Make Unique"))
	await process_frame
	_check_transform_gizmos_hidden(plugin, solid, "Make Unique")
	_check(_button_named(panel, "Assign").is_visible_in_tree(), "assign_is_visible")
	var picker: Control = panel.find_child("PaintMaterialPicker", true, false)
	var picker_wrap: Control = panel.find_child("PaintMaterialPickerWrap", true, false)
	await _wait_layout([panel, picker, picker_wrap])
	var resource_button_width := 0.0
	var resource_button: Button
	for child in picker.find_children("*", "Button", true, false):
		if child is Button and child.is_visible_in_tree():
			if child.get_global_rect().size.x > resource_button_width:
				resource_button_width = child.get_global_rect().size.x
				resource_button = child
	_check(picker.is_visible_in_tree() and picker.get_global_rect().size.x >= 200.0 * _paint_scale(), "material_picker_is_visible")
	_check(picker_wrap.get_global_rect().encloses(picker.get_global_rect()), "material_picker_fits_its_slot")
	_check(resource_button_width >= 120.0 * _paint_scale(), "material_picker_resource_button_is_readable")
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
	var data_before_unwrap: PackedByteArray = solid.get("data")
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
	_check_uv_framed(canvas, loops_after_unwrap, "Unwrap")
	_check(brush_before_unwrap != paint.material() and paint.brush_material() == brush_before_unwrap,
		"Unwrap refresh preserves the chosen brush resource")
	var data_after_unwrap: PackedByteArray = solid.get("data")
	await _history_shortcut(panel, false)
	_check(solid.get("data") == data_before_unwrap and paint.selected_uv_loops() == loops_before_unwrap,
		"Unwrap Undo restores exact planar data and loops")
	_check_uv_framed(canvas, paint.selected_uv_loops(), "Unwrap Undo")
	await _history_shortcut(panel, true)
	_check(solid.get("data") == data_after_unwrap and paint.selected_uv_loops() == loops_after_unwrap,
		"Unwrap Redo restores exact unwrapped data and loops")
	_check_uv_framed(canvas, paint.selected_uv_loops(), "Unwrap Redo")
	var density: SpinBox = panel.find_child("paint_uv_pixels_per_meter", true, false).get_child(1) as SpinBox
	var first_density := density.value
	density.get_line_edit().text = "1024"
	await _click(unwrap_button)
	var dense_loops: Array = paint.selected_uv_loops().duplicate(true)
	_check(dense_loops != loops_after_unwrap, "repeated Unwrap changes the existing unwrapped layout")
	_check_uv_framed(canvas, dense_loops, "Repeated Unwrap")
	await _history_shortcut(panel, false)
	_check(solid.get("data") == data_after_unwrap, "repeated Unwrap Undo restores exact prior layout")
	_check_uv_framed(canvas, paint.selected_uv_loops(), "Repeated Unwrap Undo")
	await _history_shortcut(panel, true)
	_check(paint.selected_uv_loops() == dense_loops, "repeated Unwrap Redo restores its layout")
	_check_uv_framed(canvas, paint.selected_uv_loops(), "Repeated Unwrap Redo")
	await _history_shortcut(panel, false)
	_check(panel.find_child("PaintMappingState", true, false).text == "Unwrapped mapping",
		"Unwrap refreshes the visible Mapping state")
	paint_inspector_scroll.ensure_control_visible(panel.find_child("PaintMapping", true, false))
	await process_frame
	await _capture(editor, {"capture_prefix": "/tmp/slab-paint-mapping", "capture_rect": panel.get_global_rect()}, "after")
	var repeat_u: SpinBox = panel.find_child("paint_uv_repeat_u", true, false).get_child(1) as SpinBox
	var repeat_v: SpinBox = panel.find_child("paint_uv_repeat_v", true, false).get_child(1) as SpinBox
	repeat_u.get_line_edit().text = "2"
	repeat_v.get_line_edit().text = "3"
	var placement_frame := _uv_frame(canvas)
	var before_quick_repeat: PackedByteArray = solid.get("data")
	await _click(_button_named(panel, "Repeat ×2"))
	_check(panel.get("_actions").uv_scale == Vector2(4.0, 6.0) and repeat_u.value == 4.0 and repeat_v.value == 6.0,
		"Repeat ×2 flushes pending U/V text and updates both fields")
	await _click(_button_named(panel, "Repeat ÷2"))
	_check(panel.get("_actions").uv_scale == Vector2(2.0, 3.0) and repeat_u.value == 2.0 and repeat_v.value == 3.0,
		"Repeat ÷2 updates model and fields consistently")
	await _history_shortcut(panel, false)
	await _history_shortcut(panel, false)
	_check(solid.get("data") == before_quick_repeat, "two quick-repeat Undos restore exact UV data")
	_check(_uv_frame(canvas) == placement_frame, "repeat changes and their Undo preserve canvas framing")
	await _pending_uv_value(panel, solid, selection)
	_check(_uv_frame(canvas) == placement_frame, "rotation Apply, Undo and Redo preserve canvas framing")
	var before: PackedByteArray = solid.get("data")
	await _uv_gesture(canvas, true)
	_check(solid.get("data") == before and not paint.uv_drag_active and paint.active, "escape_cancels_uv_without_closing_workspace")
	await _uv_gesture(canvas, false)
	var after: PackedByteArray = solid.get("data")
	_check(after != before and not paint.uv_drag_active, "release_commits_uv")
	await _history_shortcut(panel, false)
	_check(solid.get("data") == before, "editor_undo_restores_uv")
	var expected_header := "%s · %d %s · %s" % [solid.name, selection.ids.size(),
		"face" if selection.ids.size() == 1 else "faces", paint.selected_material_summary()]
	var actual_header: String = panel.get("_selection_context").text
	_check(panel.get("_status").text.is_empty() and selection.solid == solid
		and actual_header == expected_header and not actual_header.contains(distinct_brush.resource_name),
		"undo_clears_stale_report_and_keeps_selected_face_material_context (expected=%s actual=%s status=%s)" % [
			expected_header, actual_header, panel.get("_status").text])
	await _history_shortcut(panel, true)
	_check(solid.get("data") == after, "editor_redo_restores_uv")
	_check(_uv_frame(canvas) == placement_frame, "UV move, cancellation and history preserve canvas framing")
	# Explicit Unwrap also fits when only placement changed and its basis is unchanged.
	paint_inspector_scroll.ensure_control_visible(unwrap_button)
	await process_frame
	density.get_line_edit().text = str(first_density)
	await _click(unwrap_button)
	_check(paint.selected_uv_loops() == loops_after_unwrap,
		"same-density Unwrap resets placement to the original unwrapped layout")
	_check_uv_framed(canvas, paint.selected_uv_loops(), "Same-density Unwrap after placement")
	await _history_shortcut(panel, false)
	_check(solid.get("data") == after, "same-density Unwrap Undo restores exact placement data")
	await _extreme_uv_framing(editor, panel, canvas, paint, solid, selection)
	await _modifier_uv_framing(panel, canvas, paint, solid, selection)
	await _click(_mode(panel, 3))
	for i in 3: await process_frame
	_check(not paint.active and selection.mode == 3, "same_face_mode_button_leaves_uv")
	_check(not solid.has_meta("_edit_lock_"), "uv_exit_restores_native_gizmo")
	_check(not uv_workspace.button_pressed and uv_workspace.get_theme_stylebox("normal").bg_color != panel.ACCENT,
		"leaving_uv_clears_workspace_highlight")
	_check(panel.current_workspace() == panel.Workspace.MODELLING, "leaving_uv_returns_to_modelling_workspace")
	await _click(_button_named(panel, "UV"))
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
	await _click(_button_named(panel, "UV"))
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
	surface.get_viewport().push_input(frame, true)
	await create_timer(0.5).timeout
	_check(paint.active and viewport.get_camera_3d().global_transform != camera_before, "frame_selection_works_while_uv")
	await _click(_button_named(panel, "Paint"))
	await _wait_layout([panel, canvas, panel.find_child("PaintInspector", true, false)])
	_check(panel.current_workspace() == panel.Workspace.PAINT, "paint_button_enters_paint_workspace")
	var paint_workspace: Button = panel.find_child("PaintWorkspace", true, false)
	_check(paint_workspace.button_pressed, "paint_workspace_button_shows_pressed")
	_check(not uv_workspace.button_pressed, "uv_workspace_button_not_pressed_in_paint")
	var save: Button = _button_named(panel, "Save Paint")
	var help: Label = panel.find_child("PaintHelp", true, false)
	_check(save.visible and actions_row.get_global_rect().grow(1.0).encloses(save.get_global_rect()), "pixel_save_fits_complete_action_wrapper")
	_check(help.visible and actions_row.get_global_rect().grow(1.0).encloses(help.get_global_rect()), "pixel_help_fits_complete_action_wrapper")
	await _click(_button_named(panel, "Make Unique"))
	await process_frame
	_check_transform_gizmos_hidden(plugin, solid, "Make Unique")
	var resize_material: StandardMaterial3D = paint.material()
	var resize_before_data: PackedByteArray = solid.get("data")
	var resize_before_size: Vector2i = paint.image().get_size()
	await _click(_button_named(panel, "Resize…"))
	await _wait_layout([panel.find_child("PaintResizeForm", true, false), panel.find_child("PaintInspector", true, false)])
	var resize_form: VBoxContainer = panel.find_child("PaintResizeForm", true, false)
	_check(resize_form != null and resize_form.is_visible_in_tree(), "owned Pixel artwork reveals the inline Resize form")
	var resize_width: SpinBox = resize_form.find_child("PaintResizeWidth", true, false)
	var resize_height: SpinBox = resize_form.find_child("PaintResizeHeight", true, false)
	var keep_aspect: CheckBox = resize_form.find_child("PaintResizeAspect", true, false)
	var sampling: OptionButton = resize_form.find_child("PaintResizeSampling", true, false)
	var resize_apply: Button = resize_form.find_child("PaintResizeConfirm", true, false)
	var resize_cancel: Button = resize_form.find_child("PaintResizeCancel", true, false)
	_check(resize_cancel.get_global_rect().position.x < resize_apply.get_global_rect().position.x,
		"paint_resize_cancel_left_apply_right")
	_check(panel.get("_paint_inspector").get_global_rect().grow(1.0).encloses(resize_apply.get_global_rect())
		and panel.get("_paint_inspector").get_global_rect().grow(1.0).encloses(resize_cancel.get_global_rect()),
		"first-open Resize actions scroll fully into the Pixel inspector: %s apply=%s cancel=%s scroll=%s/%s" % [panel.get("_paint_inspector").get_global_rect(), resize_apply.get_global_rect(), resize_cancel.get_global_rect(), panel.get("_paint_inspector").scroll_vertical, panel.get("_paint_inspector").get_v_scroll_bar().max_value])
	await _click(resize_cancel)
	_check(not resize_form.visible and paint.image().get_size() == resize_before_size
		and paint.material() == resize_material and solid.get("data") == resize_before_data,
		"inline Resize Cancel closes without editing")
	await _click(_button_named(panel, "Resize…"))
	keep_aspect.button_pressed = false
	await _type_spin_text(resize_width, "512")
	await _type_spin_text(resize_height, "128")
	sampling.select(1)
	await _click(resize_apply)
	await create_timer(0.2).timeout
	await create_timer(0.2).timeout
	_check(paint.image().get_size() == Vector2i(512, 128) and paint.material() == resize_material
		and solid.get("data") == resize_before_data and paint.dirty,
		"Resize button commits pending 512 × 128 fields; got %s" % paint.image().get_size())
	await _history_shortcut(panel, false)
	_check(paint.image().get_size() == resize_before_size and paint.material() == resize_material
		and solid.get("data") == resize_before_data,
		"Resize Undo restores exact dimensions without changing UV geometry or material identity")
	var albedo_channel: Button = panel.find_child("ChannelAlbedo", true, false)
	_check(albedo_channel != null and albedo_channel.is_visible_in_tree() and albedo_channel.button_pressed,
		"Pixel workspace visibly selects the Albedo channel")
	var overlay_opacity_row: Control = panel.find_child("overlay_opacity", true, false)
	_check(overlay_opacity_row != null and overlay_opacity_row.is_visible_in_tree(),
		"Pixel workspace has overlay opacity control")
	var flatten_button: Button = panel.find_child("PaintFlatten", true, false)
	_check(flatten_button != null and flatten_button.is_visible_in_tree(),
		"Pixel workspace has Flatten button")
	_check(flatten_button.disabled, "Flatten is disabled without overlay strokes")
	var fitted: Rect2 = canvas.image_rect()
	var image_center: Vector2 = canvas.global_position + fitted.get_center()
	await _click_at(panel, image_center)
	await create_timer(0.2).timeout
	_check(paint.has_overlay_strokes(), "canvas click creates overlay strokes")
	_check(not flatten_button.disabled, "Flatten enabled after overlay strokes")
	var base_before_flatten: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	await _click(flatten_button)
	await create_timer(0.2).timeout
	var base_after_flatten: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_check(base_after_flatten.r > base_before_flatten.r + 0.05,
		"Flatten commits overlay to base, before=%s after=%s" % [base_before_flatten, base_after_flatten])
	_check(not paint.has_overlay_strokes(), "Flatten clears overlay strokes")
	_check(flatten_button.disabled, "Flatten disabled after flattening")
	await _history_shortcut(panel, false)
	var base_after_undo: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_check(base_after_undo.is_equal_approx(base_before_flatten),
		"Flatten Undo restores base, expected=%s got=%s" % [base_before_flatten, base_after_undo])
	_check(paint.has_overlay_strokes(), "Flatten Undo restores overlay strokes for re-editing")
	_check(not flatten_button.disabled, "Flatten enabled after Undo restores overlay")
	await _history_shortcut(panel, true)
	_check(not paint.has_overlay_strokes(), "Flatten Redo clears overlay strokes")
	_check(flatten_button.disabled, "Flatten disabled after Redo")
	await _layer_and_channel_controls(panel, canvas, paint, solid)
	await _width_matrix(panel, editor)
	await _capture(editor, {"capture_prefix": "/tmp/slab-paint-editor"}, "after")
	print("SLAB_PAINT_EDITOR ", JSON.stringify({"failures": failures}))
	_cleanup_paint_test()
	quit(1 if failures else 0)


func _pending_uv_value(panel: Control, solid: Node3D, selection: RefCounted) -> void:
	var before: PackedByteArray = solid.get("data")
	var field: Node = panel.find_child("paint_uv_rotation", true, false)
	var spin: SpinBox = field.find_children("*", "SpinBox", true, false)[0]
	await _type_spin_text(spin, "15")
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
	panel.get_viewport().push_input(key, true)
	key = key.duplicate()
	key.pressed = false
	panel.get_viewport().push_input(key, true)
	await create_timer(0.2).timeout


func _uv_gesture(canvas: Control, cancel_drag: bool, mode: int = 0) -> void:
	var view_before := _uv_frame(canvas)
	var start: Vector2 = canvas.global_position + canvas.image_rect().get_center()
	var end: Vector2 = start + Vector2(25, 15) * canvas.get("_metrics").scale()
	var paint: RefCounted = canvas.get("_paint")
	var offset_before: Vector2 = paint.get("_actions").uv_offset
	var pointer_delta: Vector2 = canvas.call("_canvas_to_uv", end - canvas.global_position) - canvas.call("_canvas_to_uv", start - canvas.global_position)
	var modifier := InputEventKey.new()
	modifier.keycode = KEY_SHIFT if mode == paint.UV_SCALE else (KEY_META if OS.get_name() == "macOS" else KEY_CTRL)
	modifier.physical_keycode = modifier.keycode
	modifier.pressed = true
	_modifier_flags(modifier, mode)
	if mode != paint.UV_MOVE:
		canvas.grab_focus()
		canvas.get_viewport().push_input(modifier, true)
		await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	_modifier_flags(press, mode)
	canvas.get_viewport().push_input(press, true)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = end
	motion.global_position = end
	motion.relative = end - start
	_modifier_flags(motion, mode)
	canvas.get_viewport().push_input(motion, true)
	await process_frame
	_check(canvas.get("_paint").uv_drag_active, "canvas_mouse_drag_started")
	_check(_uv_frame(canvas) == view_before, "held UV drag keeps a stable canvas frame")
	if mode == paint.UV_MOVE:
		_check((paint.get("_actions").uv_offset - offset_before).is_equal_approx(pointer_delta),
			"unmodified move follows the pointer in UV coordinates")
	if cancel_drag:
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		canvas.get_viewport().push_input(escape, true)
		await process_frame
	press.pressed = false
	press.button_mask = 0
	press.position = end
	press.global_position = end
	canvas.get_viewport().push_input(press, true)
	if mode != paint.UV_MOVE:
		modifier.pressed = false
		_modifier_flags(modifier, 0)
		canvas.get_viewport().push_input(modifier, true)
	await create_timer(0.2).timeout


func _check_uv_framed(canvas: Control, loops: Array, label: String) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for loop: PackedVector2Array in loops:
		for uv: Vector2 in loop:
			var mapped: Vector2 = canvas.call("_uv_to_canvas", uv)
			lo = lo.min(mapped)
			hi = hi.max(mapped)
	_check(not loops.is_empty() and Rect2(Vector2.ZERO, canvas.size).encloses(Rect2(lo, hi - lo)),
		"%s keeps every restored UV corner inside the canvas" % label)
	_check(((lo + hi) * 0.5).distance_to(canvas.size * 0.5) <= 2.0,
		"%s centres the UV bounds" % label)


func _uv_frame(canvas: Control) -> Array:
	return [canvas.get("_uv_center"), canvas.get("_uv_pixels_per_unit"), canvas.get("_uv_pan")]


func _extreme_uv_framing(editor: Object, panel: Control, canvas: Control, paint: RefCounted,
		solid: Node3D, selection: RefCounted) -> void:
	var saved_data: PackedByteArray = solid.get("data")
	var saved_brush: StandardMaterial3D = paint.brush_material()
	paint.choose_brush_material(load("res://demo/signal_foundry/materials/brick.tres"))
	_check(solid.call("set_face_uv", selection.ids, Vector2.ONE, Vector2.ZERO, 0.0) == 0,
		"ordinary unwrapped framing fixture clears placement")
	paint.refresh_uv_mapping()
	await _click(_button_named(panel, "Fit UV"))
	await _capture(editor, {"capture_prefix": "/tmp/slab-paint-small-unwrap", "capture_rect": panel.get_global_rect()}, "after")
	for fixture in [{"name": "tiny", "scale": Vector2.ONE * 0.00001},
			{"name": "large", "scale": Vector2.ONE * 100000000.0},
			{"name": "point", "scale": Vector2.ZERO}]:
		var label: String = fixture.name
		_check(solid.call("set_face_uv", selection.ids, fixture.scale, Vector2.ZERO, 0.0) == 0,
			"%s UV framing fixture commits" % label)
		paint.refresh_uv_mapping()
		await _click(_button_named(panel, "Fit UV"))
		var loops: Array = paint.selected_uv_loops()
		_check_uv_framed(canvas, loops, "%s Fit UV" % label)
		var bounds := _canvas_uv_bounds(canvas, loops)
		var fill := maxf(bounds.size.x / canvas.size.x, bounds.size.y / canvas.size.y)
		_check(is_finite(canvas.get("_uv_pixels_per_unit")), "%s Fit UV has a finite scale" % label)
		if label != "point":
			_check(fill >= 0.75 and fill <= 0.9, "%s Fit UV occupies useful canvas area: %s" % [label, fill])
			if label == "tiny":
				_check(canvas.get("_uv_pixels_per_unit") > 4096.0, "tiny Fit UV exceeds the old zoom ceiling")
				await _capture(editor, {"capture_prefix": "/tmp/slab-paint-tiny-fit", "capture_rect": panel.get_global_rect()}, "after")
			else:
				_check(canvas.get("_uv_pixels_per_unit") < 0.01, "large Fit UV falls below the old zoom floor")
			var anchor := canvas.size * Vector2(0.61, 0.58)
			var uv_anchor: Vector2 = canvas.call("_canvas_to_uv", anchor)
			var fitted_scale: float = canvas.get("_uv_pixels_per_unit")
			await _uv_wheel(canvas, anchor, MOUSE_BUTTON_WHEEL_UP)
			_check(canvas.get("_uv_pixels_per_unit") > fitted_scale, "%s wheel-up zooms inward after Fit UV" % label)
			_check((canvas.call("_uv_to_canvas", uv_anchor) as Vector2).distance_to(anchor) < 0.5,
				"%s wheel-up keeps its UV point under the pointer" % label)
			if label == "tiny":
				await _capture(editor, {"capture_prefix": "/tmp/slab-paint-tiny-zoom", "capture_rect": panel.get_global_rect()}, "after")
			var zoomed_scale: float = canvas.get("_uv_pixels_per_unit")
			await _uv_wheel(canvas, anchor, MOUSE_BUTTON_WHEEL_DOWN)
			_check(canvas.get("_uv_pixels_per_unit") < zoomed_scale
				and is_equal_approx(canvas.get("_uv_pixels_per_unit"), fitted_scale),
				"%s wheel-down restores fitted scale without a jump" % label)
			_check((canvas.call("_uv_to_canvas", uv_anchor) as Vector2).distance_to(anchor) < 0.5,
				"%s wheel-down keeps its UV point under the pointer" % label)
	solid.set("data", saved_data)
	paint.choose_brush_material(saved_brush)
	paint.refresh_uv_mapping()
	await _click(_button_named(panel, "Fit UV"))
	_check(solid.get("data") == saved_data, "UV framing fixtures restore exact original scene data")


func _uv_wheel(canvas: Control, position: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = canvas.global_position + position
	event.global_position = event.position
	canvas.get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	canvas.get_viewport().push_input(event, true)
	await create_timer(0.2).timeout


func _canvas_uv_bounds(canvas: Control, loops: Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for loop: PackedVector2Array in loops:
		for uv: Vector2 in loop:
			var mapped: Vector2 = canvas.call("_uv_to_canvas", uv)
			lo = lo.min(mapped)
			hi = hi.max(mapped)
	return Rect2(lo, hi - lo)


func _modifier_flags(event: InputEventWithModifiers, mode: int) -> void:
	event.shift_pressed = mode == 1
	event.meta_pressed = mode == 2 and OS.get_name() == "macOS"
	event.ctrl_pressed = mode == 2 and OS.get_name() != "macOS"


func _modifier_uv_framing(panel: Control, canvas: Control, paint: RefCounted,
		solid: Node3D, selection: RefCounted) -> void:
	var original: PackedByteArray = solid.get("data")
	var original_attrs: Dictionary = solid.call("face_uv", selection.ids[0])
	for mode in [paint.UV_SCALE, paint.UV_ROTATE]:
		await _click(_button_named(panel, "Fit UV"))
		var results: Array[Dictionary] = []
		for zoom_index in range(2):
			if zoom_index == 1:
				for notch in range(12):
					await _uv_wheel(canvas, canvas.size * 0.5, MOUSE_BUTTON_WHEEL_UP)
			var framing := _uv_frame(canvas)
			await _uv_gesture(canvas, true, mode)
			_check(solid.get("data") == original and not paint.uv_drag_active,
				"modifier %s Escape restores exact data at zoom %s" % [mode, zoom_index])
			await _uv_gesture(canvas, false, mode)
			var committed: PackedByteArray = solid.get("data")
			_check(committed != original and not paint.uv_drag_active,
				"modifier %s release commits at zoom %s" % [mode, zoom_index])
			results.append(solid.call("face_uv", selection.ids[0]))
			await _history_shortcut(panel, false)
			_check(solid.get("data") == original, "modifier drag Undo restores exact data")
			await _history_shortcut(panel, true)
			_check(solid.get("data") == committed, "modifier drag Redo restores exact data")
			await _history_shortcut(panel, false)
			_check(_uv_frame(canvas) == framing, "modifier drag, Escape and history preserve canvas framing")
		if mode == paint.UV_SCALE:
			_check((results[0].scale as Vector2).is_equal_approx(results[1].scale),
				"same Shift drag scales equally at different canvas zooms")
			var expected: Vector2 = original_attrs.scale * (Vector2.ONE + Vector2(25, 15) / 180.0)
			_check((results[0].scale as Vector2).is_equal_approx(expected), "Shift scaling uses 180 logical pixels per doubling")
		else:
			_check(is_equal_approx(results[0].rotation, results[1].rotation),
				"same rotation modifier drag rotates equally at different canvas zooms")
			_check(is_equal_approx(results[0].rotation, original_attrs.rotation + deg_to_rad(25.0)),
				"rotation modifier uses one degree per logical horizontal pixel")
	await _click(_button_named(panel, "Fit UV"))
	_check(solid.get("data") == original, "modifier regression restores original scene data")


func _click_at(control: Control, pos: Vector2) -> void:
	var vp: Viewport = control.get_viewport()
	if vp == null:
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = pos
	press.global_position = pos
	vp.push_input(press, true)
	await create_timer(0.05).timeout
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	release.position = pos
	release.global_position = pos
	vp.push_input(release, true)
	await create_timer(0.15).timeout


func _paint_scale() -> float:
	return _paint_test_panel.get("_metrics").scale() if _paint_test_panel != null else 1.0


func _set_test_window(panel: Control, logical_size: Vector2i) -> void:
	root.mode = Window.MODE_WINDOWED
	var requested := Vector2i(Vector2(logical_size) * _paint_scale())
	var usable := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = usable.position + (usable.size - requested) / 2
	root.size = requested
	print("PAINT_WINDOW ", JSON.stringify({"usable": str(usable), "position": str(root.position), "requested": str(requested), "actual": str(root.size), "editor_scale": _paint_test_editor.get_editor_scale()}))
	await _wait_layout([panel])
	_check(root.size == requested, "window reaches requested %s logical pixels, actual %s" % [logical_size, root.size])


func _wait_layout(controls: Array, context: String = "paint layout") -> void:
	var deadline := Time.get_ticks_msec() + 5000
	var prior: Array = []
	var stable := 0
	while stable < 6:
		await process_frame
		var current: Array = []
		var ready := true
		for control: Control in controls:
			if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
				ready = false
				continue
			current.append([control.get_global_rect(), control.get_combined_minimum_size()])
			ready = ready and control.size.x > 0.0 and control.size.y > 0.0
		stable = stable + 1 if ready and current == prior else 0
		prior = current
		if Time.get_ticks_msec() > deadline:
			_dump_layout(context)
			_fail("Layout did not stabilize: " + context)
			return


func _click(button: Button) -> void:
	if button == null or not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		_fail("Requested paint button is unavailable")
		return
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(button)
			await process_frame
		ancestor = ancestor.get_parent()
	await _wait_layout([button], "before clicking " + button.text)
	# Native window activation and mouse-enter notifications are asynchronous on macOS.
	# Wait for the real GUI hit target before sending a single press/release pair.
	button.get_window().grab_focus()
	button.get_viewport().warp_mouse(button.get_global_rect().get_center())
	var mouse_deadline := Time.get_ticks_msec() + 3000
	var hovered: Control
	while true:
		await process_frame
		var hover_event := InputEventMouseMotion.new()
		hover_event.window_id = button.get_window().get_window_id()
		hover_event.position = button.get_global_rect().get_center()
		hover_event.global_position = hover_event.position
		button.get_viewport().push_input(hover_event, true)
		hovered = button.get_viewport().gui_get_hovered_control()
		if button.get_window().has_focus() and (hovered == button or (hovered != null and button.is_ancestor_of(hovered))):
			break
		if Time.get_ticks_msec() > mouse_deadline:
			_fail("Native mouse did not reach %s; hover=%s rect=%s focus=%s" % [button.text, hovered, button.get_global_rect(), button.get_window().has_focus()])
			return
	var already_latched := button.toggle_mode and button.button_group != null and button.button_pressed
	var hits := {"n": 0}
	var pressed := func() -> void: hits["n"] += 1
	button.pressed.connect(pressed)
	await _click_at(button, button.get_global_rect().get_center())
	if is_instance_valid(button) and button.pressed.is_connected(pressed):
		button.pressed.disconnect(pressed)
	if hits["n"] == 0 and not already_latched:
		_fail("Viewport click did not fire pressed on %s; hover=%s rect=%s" % [button.text, hovered, button.get_global_rect()])


func _check_transform_gizmos_hidden(plugin: Node, solid: Node3D, context: String) -> void:
	var no_selected_subgizmos := true
	for gizmo in solid.get_gizmos():
		if not gizmo.get_subgizmo_selection().is_empty():
			no_selected_subgizmos = false
	_check(solid.get_meta("_edit_lock_", false) and no_selected_subgizmos
		and plugin.get("_subgizmo_solid") == null,
		"%s keeps native and Slab element transform gizmos hidden in UV/Paint" % context)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		_dump_layout(label)
	print("NATIVE_CHECK ", JSON.stringify({"check": label, "passed": ok}))


func _dump_layout(label: String) -> void:
	var bounds: Array = []
	if _paint_test_panel != null:
		for control_name in ["PaintWorkspaceSplit", "PaintInspector", "PaintActions", "PaintMaterialPickerWrap", "PaintMaterialPicker", "PaintCanvas", "ChannelPicker", "LayerList", "PaintResizeForm"]:
			var control: Control = _paint_test_panel.find_child(control_name, true, false)
			if control != null:
				bounds.append({"name": control_name, "rect": str(control.get_global_rect()), "minimum": str(control.get_combined_minimum_size()), "visible": control.is_visible_in_tree()})
	print("PAINT_LAYOUT ", JSON.stringify({"context": label, "window": str(root.size), "scale": _paint_scale(), "controls": bounds}))
	if _paint_test_editor != null and DisplayServer.get_name() != "headless":
		RenderingServer.force_sync()
		RenderingServer.force_draw(true)
		var shot: Image = _paint_test_editor.get_base_control().get_viewport().get_texture().get_image()
		var path := "/tmp/slab-paint-editor-failure-%d.png" % failures
		shot.save_png(path)
		print("PAINT_FAILURE_CAPTURE ", path)


func _cleanup_paint_test() -> void:
	for path in _created_pngs:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".import"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".import"))
	_created_pngs.clear()
	if _original_window_size != Vector2i.ZERO:
		root.position = _original_window_position
		root.size = _original_window_size
		root.mode = _original_window_mode


func _fail(message: String) -> void:
	_dump_layout(message)
	printerr("NATIVE_FAILURE ", message)
	_cleanup_paint_test()
	quit(1)


func _width_matrix(panel: Control, editor: Object) -> void:
	for logical_size in [Vector2i(1440, 800), Vector2i(1280, 800)]:
		await _set_test_window(panel, logical_size)
		await _click(_button_named(panel, "UV"))
		var picker: Control = panel.find_child("PaintMaterialPicker", true, false)
		var wrap: Control = panel.find_child("PaintMaterialPickerWrap", true, false)
		var inspector: Control = panel.find_child("PaintInspector", true, false)
		var canvas: Control = panel.find_child("PaintCanvas", true, false)
		await _wait_layout([picker, wrap, inspector, canvas])
		var readable := false
		for child: Button in picker.find_children("*", "Button", true, false):
			if child.is_visible_in_tree() and child.size.x >= 120.0 * _paint_scale():
				readable = true
		_check(picker.size.x >= 200.0 * _paint_scale() and readable,
			"%s UV resource picker retains readable widths" % logical_size.x)
		_check(wrap.get_global_rect().encloses(picker.get_global_rect())
			and inspector.get_global_rect().grow(1.0).encloses(wrap.get_global_rect())
			and not inspector.get_global_rect().intersects(canvas.get_global_rect()),
			"%s UV picker stays inside its dock without covering the canvas" % logical_size.x)
		await _capture(editor, {"capture_prefix": "/tmp/slab-paint-uv-%s" % logical_size.x}, "after")
		await _click(_button_named(panel, "Paint"))
		var channels: Control = panel.find_child("ChannelPicker", true, false)
		await _wait_layout([inspector, channels, canvas])
		_check(inspector.get_global_rect().grow(1.0).encloses(channels.get_global_rect())
			and not inspector.get_global_rect().intersects(canvas.get_global_rect()),
			"%s Paint opens with all six channel buttons visible without covering canvas" % logical_size.x)
		await _capture(editor, {"capture_prefix": "/tmp/slab-paint-pixel-%s" % logical_size.x}, "after")


func _layer_and_channel_controls(panel: Control, canvas: Control, paint: RefCounted, solid: Node3D) -> void:
	var before_count: int = paint.layer_count()
	await _click(panel.find_child("AddLayer", true, false))
	_check(paint.layer_count() == before_count + 1 and paint.active_layer_index() == before_count,
		"Add Layer button selects its new layer")
	var name_input: LineEdit = panel.find_child("LayerRename", true, false)
	var scroll := name_input.get_parent()
	while scroll != null:
		if scroll is ScrollContainer:
			scroll.ensure_control_visible(name_input)
			await process_frame
		scroll = scroll.get_parent()
	await _wait_layout([name_input])
	await _click_at(name_input, name_input.get_global_rect().get_center())
	_check(name_input.has_focus(), "layer name field receives real keyboard focus")
	name_input.select_all()
	for character in "Editor renamed layer":
		var key := InputEventKey.new()
		key.unicode = character.unicode_at(0)
		key.pressed = true
		panel.get_viewport().push_input(key, true)
		key = key.duplicate()
		key.pressed = false
		panel.get_viewport().push_input(key, true)
	var submit := InputEventKey.new()
	submit.keycode = KEY_ENTER
	submit.pressed = true
	panel.get_viewport().push_input(submit, true)
	submit = submit.duplicate()
	submit.pressed = false
	panel.get_viewport().push_input(submit, true)
	_check(paint.layer_info(paint.active_layer_index()).name == "Editor renamed layer",
		"layer name typing commits through its real LineEdit")
	await _click(panel.find_child("LayerDown", true, false))
	_check(paint.active_layer_index() == before_count - 1 and paint.layer_info(paint.active_layer_index()).name == "Editor renamed layer",
		"Lower button moves and retains the active layer")
	await _click(panel.find_child("LayerUp", true, false))
	_check(paint.active_layer_index() == before_count, "Raise button returns the layer above its neighbour")
	await _click(panel.find_child("DeleteLayer", true, false))
	_check(paint.layer_count() == before_count, "Delete Layer button removes the selected layer")
	await _history_shortcut(panel, false)
	_check(paint.layer_count() == before_count + 1, "Delete Layer keyboard Undo restores its layer")
	await _history_shortcut(panel, true)
	_check(paint.layer_count() == before_count, "Delete Layer keyboard Redo removes its layer")
	var saved_name := solid.name
	solid.name = "PaintEditorSmoke_%s" % Time.get_ticks_msec()
	var paths: Array[String] = []
	for channel_button in ["ChannelAlbedo", "ChannelRoughness", "ChannelEmission", "ChannelMetallic", "ChannelNormal", "ChannelHeight"]:
		await _click(panel.find_child(channel_button, true, false))
		await _wait_layout([canvas])
		await _click_at(canvas, canvas.global_position + canvas.image_rect().get_center())
		_check(paint.has_channel_overlay_strokes(), "%s canvas click creates editable artwork" % channel_button)
		var expected: PackedByteArray = paint.texture().get_image().save_png_to_buffer()
		var path: String = paint.default_save_path()
		_check(not FileAccess.file_exists(path), "Save fixture owns a new PNG path")
		if FileAccess.file_exists(path):
			_fail("Save fixture would overwrite an existing PNG")
			return
		_created_pngs.append(path)
		await _click(panel.find_child("PaintSave", true, false))
		var saved := Image.load_from_file(path)
		_check(saved != null and saved.save_png_to_buffer() == expected,
			"%s Save Paint button writes exact displayed pixels" % channel_button)
		paths.append(path)
	var unique_paths: Dictionary = {}
	for path in paths:
		unique_paths[path] = true
	_check(unique_paths.size() == 6, "all six channel Save buttons target independent PNGs")
	solid.name = saved_name
