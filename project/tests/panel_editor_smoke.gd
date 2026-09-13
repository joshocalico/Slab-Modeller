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
	var viewport: SubViewport = editor.get_editor_viewport_3d(0)
	var focus := InputEventKey.new()
	focus.keycode = KEY_F
	focus.pressed = true
	_surface(viewport.get_parent().get_parent()).gui_input.emit(focus)
	await create_timer(0.5).timeout
	_check(not preview.visible and settings.visible, "face_restores_settings")
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-face"}, "after")
	await _capture(editor, {"capture_prefix": "/tmp/slab-doc-panel", "capture_rect": panel.get_global_rect()}, "after")
	await _click(_button_named(panel.find_child("Commands", true, false), "Extrude"))
	_check(actions.operation_active and solid.get("data") == before, "extrude_button_opens_preview")
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-preview"}, "after")
	await _capture(editor, {"capture_prefix": "/tmp/slab-doc-panel-preview", "capture_rect": panel.get_global_rect()}, "after")
	var amount: SpinBox = panel.find_child("HandleAmount", true, false)
	amount.value = -4.0
	await create_timer(0.2).timeout
	_check(_button_named(preview, "Apply").disabled, "refused_preview_disables_apply")
	await _click(_button_named(preview, "Cancel"))
	_check(solid.get("data") == before, "refused_preview_preserves_mesh")
	await _click(_button_named(panel.find_child("Commands", true, false), "Inset"))
	_check(actions.operation_active and not settings.visible, "preview_has_one_settings_area")
	_check(solid.get("data") == before, "preview_preserves_mesh")
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-inset"}, "after")
	await _click(_button_named(preview, "Cancel"))
	_check(not actions.operation_active and settings.visible, "cancel_restores_regular_settings")
	_check(solid.get("data") == before, "cancel_preserves_mesh")
	await _click(_button_named(panel.find_child("Commands", true, false), "Inset"))
	await _click(_button_named(preview, "Apply"))
	_check(not actions.operation_active and solid.get("data") != before, "apply_commits_preview")
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	manager.get_history_undo_redo(manager.get_object_history_id(solid)).undo()
	_check(solid.get("data") == before, "undo_restores_original_mesh")
	await _click(_mode(panel, 2))
	selection.set_ids(PackedInt64Array([solid.call("get_edges")[0]]))
	await create_timer(0.2).timeout
	await _click(_button_named(panel.find_child("Commands", true, false), "Bevel"))
	amount.value = 0.1
	var segments: SpinBox = panel.find_child("bevel_segments", true, false)
	segments.value = 4
	await create_timer(0.2).timeout
	_check(actions.operation_active and segments.visible, "bevel_uses_shared_preview_with_segments")
	await _click(_button_named(preview, "Apply"))
	_check(solid.call("face_count") == 10, "bevel_applies_four_segments")
	manager.get_history_undo_redo(manager.get_object_history_id(solid)).undo()
	_check(solid.get("data") == before, "bevel_undo_restores_original_mesh")
	await _room_tutorial(editor, panel, selection, manager)
	print("PANEL_EDITOR_RESULT failures=", failures)
	quit(1 if failures else 0)

func _room_tutorial(editor: Object, panel: Control, selection: RefCounted, manager: EditorUndoRedoManager) -> void:
	await _click(_mode(panel, 0))
	panel.focus_create(&"make_box")
	for entry in [["size_x", 4.0], ["size_y", 3.0], ["size_z", 4.0]]:
		var box: Node = panel.find_child(entry[0], true, false)
		var field: SpinBox = box.find_children("*", "SpinBox", true, false)[0]
		field.value = entry[1]
	await _click(_button_named(panel.find_child("Commands", true, false), "Box"))
	var room: Node3D = editor.get_selection().get_selected_nodes()[0]
	_check(room.call("get_local_aabb").size.is_equal_approx(Vector3(4, 3, 4)), "tutorial_creates_4_by_3_by_4_box")
	await _click(_mode(panel, 3))
	var top := 0
	for id in room.call("get_faces"):
		if room.call("face_normal", id).y > 0.9: top = id
	selection.set_ids(PackedInt64Array([top]))
	var original: PackedByteArray = room.get("data")
	await _click(_button_named(panel.find_child("Commands", true, false), "Inset"))
	var amount: SpinBox = panel.find_child("HandleAmount", true, false)
	amount.value = 0.45
	await _click(_button_named(panel.find_child("OperationHandles", true, false), "Apply"))
	var inset: PackedByteArray = room.get("data")
	_check(inset != original and selection.ids.size() == 1, "tutorial_inset_keeps_inner_cap_selected")
	await _click(_button_named(panel.find_child("Commands", true, false), "Extrude"))
	amount.value = -2.4
	await _click(_button_named(panel.find_child("OperationHandles", true, false), "Apply"))
	_check(room.get("data") != inset and selection.ids.size() == 1, "tutorial_extrude_commits_room")
	var floor_y: float = room.call("face_centroid", selection.ids[0]).y
	_check(absf(floor_y - 0.6) < 0.002, "tutorial_leaves_0_6_metre_floor")
	var history := manager.get_history_undo_redo(manager.get_object_history_id(room))
	_check(history.get_current_action_name() == "Slab Extrude", "tutorial_has_named_extrude_undo")
	history.undo()
	_check(room.get("data") == inset, "tutorial_first_undo_restores_inset")
	history.undo()
	_check(room.get("data") == original, "tutorial_second_undo_restores_box")
	history.undo()
	_check(not room.is_inside_tree(), "tutorial_third_undo_removes_created_box")

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
