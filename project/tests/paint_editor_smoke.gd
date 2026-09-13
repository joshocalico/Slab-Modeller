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
	var selection: RefCounted = plugin.get("_selection")
	selection.set_objects([solid])
	await _click(_mode(panel, 3))
	for id in solid.call("get_faces"):
		if solid.call("face_normal", id).y > 0.9:
			selection.set_ids(PackedInt64Array([id]))
	await _click(_button_named(panel, "Surface Paint"))
	await _click(_button_named(panel, "Make Unique"))
	_check(_button_named(panel, "Assign").is_visible_in_tree(), "assign_is_visible")
	var picker: Control = panel.find_child("PaintMaterialPicker", true, false)
	var picker_wrap: Control = panel.find_child("PaintMaterialPickerWrap", true, false)
	var resource_button_width := 0.0
	for child in picker.find_children("*", "Button", true, false):
		if child is Button and child.is_visible_in_tree():
			resource_button_width = maxf(resource_button_width, child.get_global_rect().size.x)
	_check(picker.is_visible_in_tree() and picker.get_global_rect().size.x >= 200.0, "material_picker_is_visible")
	_check(picker_wrap.get_global_rect().encloses(picker.get_global_rect()), "material_picker_fits_its_slot")
	_check(resource_button_width >= 120.0, "material_picker_resource_button_is_readable")
	var imported := ResourceLoader.load("res://demo/signal_foundry/materials/brick.tres") as StandardMaterial3D
	picker.set("edited_resource", imported)
	picker.emit_signal("resource_changed", imported)
	await create_timer(0.2).timeout
	_check(panel.get("_paint").material() == imported, "material_picker_loads_imported_material")
	var actions_row: Control = panel.find_child("PaintActions", true, false)
	var thumbnail: TextureRect
	for child in picker.find_children("*", "TextureRect", true, false):
		if child is TextureRect and child.is_visible_in_tree():
			thumbnail = child
			break
	_check(picker_wrap.get_global_rect().encloses(picker.get_global_rect()), "loaded_material_picker_fits_its_slot")
	_check(actions_row.get_global_rect().grow(1.0).encloses(picker_wrap.get_global_rect()), "loaded_material_picker_fits_action_row")
	_check(thumbnail != null and picker.get_global_rect().encloses(thumbnail.get_global_rect()), "loaded_material_thumbnail_is_fully_visible")
	await _capture(editor, {"capture_prefix": "/tmp/slab-paint-picker", "capture_rect": panel.get_global_rect()}, "after")
	var paint: RefCounted = panel.get("_paint")
	var canvas: Control = panel.find_child("PaintCanvas", true, false)
	var before: PackedByteArray = solid.get("data")
	await _uv_gesture(canvas, true)
	_check(solid.get("data") == before and not paint.uv_drag_active and paint.active, "escape_cancels_uv_without_closing_workspace")
	await _uv_gesture(canvas, false)
	var after: PackedByteArray = solid.get("data")
	_check(after != before and not paint.uv_drag_active, "release_commits_uv")
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(solid))
	history.undo()
	_check(solid.get("data") == before, "editor_undo_restores_uv")
	history.redo()
	_check(solid.get("data") == after, "editor_redo_restores_uv")
	await _click(_mode(panel, 3))
	_check(not paint.active and selection.mode == 3, "same_face_mode_button_leaves_paint")
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
	await _capture(editor, {"capture_prefix": "/tmp/slab-paint-editor"}, "after")
	print("SLAB_PAINT_EDITOR ", JSON.stringify({"failures": failures}))
	quit(1 if failures else 0)

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
