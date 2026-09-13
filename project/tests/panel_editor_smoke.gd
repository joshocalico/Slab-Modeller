extends "res://tests/native_gizmo_editor_smoke.gd"

# Dedicated rendered editor acceptance for panel mode and preview transitions.
# scripts/godot --editor --path project --script res://tests/panel_editor_smoke.gd
# Uses actual GUI mouse events. Never saves the scene.

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
	var actions: RefCounted = plugin.get("_actions")
	selection.set_objects([solid])
	var before: PackedByteArray = solid.get("data")
	var preview: Control = panel.find_child("OperationHandles", true, false)
	var settings: Control = panel.find_child("Settings", true, false)
	await _click(_mode(panel, 0))
	_check(not preview.visible, "object_hides_element_previews")
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-object"}, "after")
	await _click(_mode(panel, 1))
	_check(not preview.visible and not settings.visible, "vertex_hides_unused_settings")
	await _click(_mode(panel, 3))
	var top := 0
	for id in solid.call("get_faces"):
		if solid.call("face_normal", id).y > 0.9: top = id
	selection.set_ids(PackedInt64Array([top]))
	await create_timer(0.2).timeout
	_check(preview.visible and settings.visible, "face_restores_settings")
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-face"}, "after")
	await _click(_button_named(preview, "Inset"))
	_check(actions.operation_active and not settings.visible, "preview_has_one_settings_area")
	_check(solid.get("data") == before, "preview_preserves_mesh")
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-preview"}, "after")
	await _click(_button_named(preview, "Cancel"))
	_check(not actions.operation_active and settings.visible, "cancel_restores_regular_settings")
	_check(solid.get("data") == before, "cancel_preserves_mesh")
	await _click(_button_named(preview, "Inset"))
	await _click(_button_named(preview, "Apply"))
	_check(not actions.operation_active and solid.get("data") != before, "apply_commits_preview")
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	manager.get_history_undo_redo(manager.get_object_history_id(solid)).undo()
	_check(solid.get("data") == before, "undo_restores_original_mesh")
	print("PANEL_EDITOR_RESULT failures=", failures)
	quit(1 if failures else 0)

func _click(button: Button) -> void:
	if button == null or button.disabled or not button.is_visible_in_tree():
		_fail("Requested panel button is unavailable")
		return
	var position := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = position
		event.global_position = position
		button.get_viewport().push_input(event)
	await create_timer(0.2).timeout

func _mode(node: Node, value: int) -> Button:
	if node is Button and node.get_meta("slab_mode", -1) == value: return node
	for child in node.get_children():
		var found := _mode(child, value)
		if found != null: return found
	return null

func _button_named(node: Node, label: String) -> Button:
	if node is Button and node.text == label: return node
	for child in node.get_children():
		var found := _button_named(child, label)
		if found != null: return found
	return null
