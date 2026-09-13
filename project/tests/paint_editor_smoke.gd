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
	editor.open_scene_from_path("res://demo/modeller_lab.tscn")
	editor.set_main_screen_editor("3D")
	while editor.get_edited_scene_root() == null or editor.get_edited_scene_root().scene_file_path != "res://demo/modeller_lab.tscn":
		await process_frame
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
