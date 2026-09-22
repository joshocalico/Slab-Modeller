extends "res://tests/native_gizmo_editor_smoke.gd"

const SlabTestGui := preload("res://tests/slab_test_gui.gd")

# Dedicated rendered editor acceptance for panel mode and preview transitions.
# scripts/godot --editor --path project --script res://tests/panel_editor_smoke.gd
# Uses actual GUI mouse events. Never saves the scene.

func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("Requires --editor")
		return
	var editor := Engine.get_singleton("EditorInterface")
	var deadline := Time.get_ticks_msec() + 30000
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		if Time.get_ticks_msec() > deadline:
			_fail("Editor initialization timed out")
			return
		await process_frame
	# Session restore can reopen the previous scene after the first filesystem scan.
	# Let that settle before opening the fixture, then require the fixture to stay current.
	await create_timer(1.5).timeout
	editor.open_scene_from_path("res://demo/modeller_lab.tscn")
	editor.set_main_screen_editor("3D")
	var stable_frames := 0
	deadline = Time.get_ticks_msec() + 15000
	while stable_frames < 20:
		await process_frame
		var edited: Node = editor.get_edited_scene_root()
		stable_frames = stable_frames + 1 if edited != null and edited.scene_file_path == "res://demo/modeller_lab.tscn" else 0
		if Time.get_ticks_msec() > deadline:
			_fail("Panel fixture did not remain current after session restore")
			return
	var solid: Node3D = editor.get_edited_scene_root().get_node_or_null("Box2")
	if solid == null:
		_fail("Panel fixture is missing Box2")
		return
	editor.get_selection().clear()
	editor.get_selection().add_node(solid)
	editor.edit_node(solid)
	await create_timer(0.5).timeout
	var plugin := _plugin(root)
	var panel: Control = plugin.get("_panel")
	var selection: RefCounted = plugin.get("_selection")
	var actions: RefCounted = plugin.get("_actions")
	plugin.make_bottom_panel_item_visible(panel)
	await process_frame
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
	_surface(viewport.get_parent().get_parent()).grab_focus()
	viewport.push_input(focus)
	focus.pressed = false
	viewport.push_input(focus)
	await create_timer(0.5).timeout
	_check(not preview.visible and not settings.visible, "face_starts_with_geometry_tools")
	var create_strip: Control = panel.find_child("CreateStrip", true, false)
	_check(create_strip != null and not create_strip.visible, "create_strip_hidden_in_face_mode")
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-compact"}, "after")
	await _capture(editor, {"capture_prefix": "/tmp/slab-doc-panel", "capture_rect": panel.get_global_rect()}, "after")
	var select_all := InputEventKey.new()
	select_all.keycode = KEY_A
	select_all.pressed = true
	panel.get_viewport().push_input(select_all)
	select_all.pressed = false
	panel.get_viewport().push_input(select_all)
	await create_timer(0.2).timeout
	_check(selection.ids.size() == solid.call("get_faces").size(), "collapsed_selection_keeps_keyboard_shortcuts")
	_check(not panel.find_child("SectionSelection", true, false).button_pressed, "shortcut_does_not_expand_section")
	selection.set_ids(PackedInt64Array([top]))
	var disclosure: Button = panel.find_child("SectionSelection", true, false)
	await _ensure_commands_visible(panel, disclosure)
	await _click(disclosure)
	_check(disclosure.button_pressed and not settings.visible, "selection_disclosure_expands_without_legacy_uv_settings")
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-face"}, "after")
	await _capture(editor, {"capture_prefix": "/tmp/slab-doc-panel-face", "capture_rect": panel.get_global_rect()}, "after")
	await _click(_mode(panel, 2))
	await _click(_mode(panel, 3))
	selection.set_ids(PackedInt64Array([top]))
	_check(panel.find_child("SectionSelection", true, false).button_pressed and not settings.visible, "selection_disclosure_survives_mode_switch")
	disclosure = panel.find_child("SectionSelection", true, false)
	disclosure.grab_focus()
	var accept := InputEventKey.new()
	accept.keycode = KEY_SPACE
	accept.pressed = true
	panel.get_viewport().push_input(accept)
	accept.pressed = false
	panel.get_viewport().push_input(accept)
	await create_timer(0.2).timeout
	_check(not disclosure.button_pressed and not settings.visible, "keyboard_collapses_selection_commands")
	await _ensure_commands_visible(panel, disclosure)
	await _click(disclosure)
	var amount: SpinBox = panel.find_child("HandleAmount", true, false)
	var session_events := {"started": [], "updated": [], "ended": []}
	actions.op_session_started.connect(func(op_id: String, title: String, fields: Array) -> void:
		session_events["started"].append({"op_id": op_id, "title": title, "fields": fields}))
	actions.op_session_updated.connect(func(op_id: String, values: Dictionary, apply_enabled: bool) -> void:
		session_events["updated"].append({"op_id": op_id, "values": values, "apply_enabled": apply_enabled}))
	actions.op_session_ended.connect(func(op_id: String, reason: String) -> void:
		session_events["ended"].append({"op_id": op_id, "reason": reason}))
	await _click(_button_named(panel.find_child("Commands", true, false), "Extrude"))
	_check(actions.operation_active and solid.get("data") == before, "extrude_button_opens_preview")
	_check(is_equal_approx(amount.value, 0.5), "extrude_starts_with_its_own_default_distance")
	_check(session_events["started"].size() == 1 and session_events["started"][0]["op_id"] == "extrude",
		"op_session_started_emitted_with_extrude_id")
	_check(session_events["started"][0]["title"] == "Extrude", "op_session_started_has_extrude_title")
	_check(session_events["started"][0]["fields"].size() == 1 and session_events["started"][0]["fields"][0]["id"] == "distance",
		"op_session_started_has_distance_field")
	_check(actions.op_session_active() and actions.op_session_id() == "extrude", "op_session_getters_return_active_state")
	var cancel_btn: Button = panel.find_child("OpCardCancel", true, false)
	var apply_btn: Button = panel.find_child("OpCardApply", true, false)
	_check(cancel_btn != null and apply_btn != null, "op_card_has_named_commit_buttons")
	_check(cancel_btn.get_global_rect().position.x < apply_btn.get_global_rect().position.x,
		"op_card_cancel_left_apply_right")
	_check(not apply_btn.disabled and apply_btn.has_theme_stylebox_override("normal"),
		"valid_apply_has_primary_styling")
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-preview"}, "after")
	await _capture(editor, {"capture_prefix": "/tmp/slab-doc-panel-preview", "capture_rect": panel.get_global_rect()}, "after")
	amount.value = -4.0
	await create_timer(0.2).timeout
	_check(_button_named(preview, "Apply").disabled, "refused_preview_disables_apply")
	_check(not apply_btn.has_theme_stylebox_override("normal"), "invalid_apply_loses_primary_styling")
	var last_update: Dictionary = session_events["updated"][-1] if session_events["updated"].size() > 0 else {}
	_check(last_update.get("apply_enabled", true) == false, "op_session_updated_with_apply_enabled_false")
	await _click(_button_named(preview, "Cancel"))
	_check(solid.get("data") == before, "refused_preview_preserves_mesh")
	_check(session_events["ended"].size() == 1 and session_events["ended"][0]["reason"] == "cancel",
		"op_session_ended_with_cancel_reason")
	await _click(_button_named(panel.find_child("Commands", true, false), "Inset"))
	_check(actions.operation_active and not settings.visible, "preview_has_one_settings_area")
	_check(is_equal_approx(amount.value, 0.5), "inset_does_not_inherit_extrude_distance")
	_check(solid.get("data") == before, "preview_preserves_mesh")
	amount.value = 0.45
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-inset"}, "after")
	await _click(_button_named(preview, "Cancel"))
	_check(not actions.operation_active and not settings.visible, "cancel_restores_compact_face_commands")
	_check(solid.get("data") == before, "cancel_preserves_mesh")
	await _click(_button_named(panel.find_child("Commands", true, false), "Extrude"))
	_check(is_equal_approx(amount.value, -4.0), "cancelled_extrude_remembers_its_distance")
	await _click(_button_named(preview, "Cancel"))
	await _click(_button_named(panel.find_child("Commands", true, false), "Inset"))
	_check(is_equal_approx(amount.value, 0.45), "cancelled_inset_remembers_its_distance")
	await _type_spin_text(amount, "0.25")
	var ended_before_apply: int = session_events["ended"].size()
	await _click(_button_named(preview, "Apply"))
	_check(is_equal_approx(actions.inset_amount, 0.25), "inset_apply_uses_pending_distance")
	_check(not actions.operation_active and solid.get("data") != before, "apply_commits_preview")
	_check(session_events["ended"].size() == ended_before_apply + 1 and session_events["ended"][-1]["reason"] == "apply",
		"op_session_ended_with_apply_reason")
	_check(actions.op_session_remembered("inset").get("distance", 0.0) == 0.25,
		"op_session_remembered_returns_last_applied_value")
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	manager.get_history_undo_redo(manager.get_object_history_id(solid)).undo()
	_check(solid.get("data") == before, "undo_restores_original_mesh")
	await _click(_mode(panel, 2))
	selection.set_ids(PackedInt64Array([solid.call("get_edges")[0]]))
	await create_timer(0.2).timeout
	await _click(_button_named(panel.find_child("Commands", true, false), "Bevel"))
	_check(is_equal_approx(amount.value, 0.5), "bevel_keeps_an_independent_default_width")
	var segments: SpinBox = panel.find_child("bevel_segments", true, false)
	await _type_spin_text(amount, "0.1")
	await _type_spin_text(segments, "4")
	await create_timer(0.2).timeout
	_check(actions.operation_active and segments.visible, "bevel_uses_shared_preview_with_segments")
	await _click(_button_named(preview, "Apply"))
	_check(is_equal_approx(actions.bevel_amount, 0.1), "bevel_apply_uses_pending_width")
	_check(solid.call("face_count") == 10, "bevel_applies_four_segments")
	manager.get_history_undo_redo(manager.get_object_history_id(solid)).undo()
	_check(solid.get("data") == before, "bevel_undo_restores_original_mesh")
	await _boolean_swap(editor, panel, selection, manager)
	await _create_strip_tool_blocking(editor, panel, selection, actions)
	await _room_tutorial(editor, panel, selection, manager)
	await _create_repeated(editor, panel, manager)
	print("PANEL_EDITOR_RESULT failures=", failures)
	quit(1 if failures else 0)


func _boolean_swap(editor: Object, panel: Control, selection: RefCounted, manager: EditorUndoRedoManager) -> void:
	await _click(_mode(panel, 0))
	var scene: Node = editor.get_edited_scene_root()
	var first: Node3D = ClassDB.instantiate("SlabSolid")
	first.name = "PowerHouse"
	first.call("make_box", Vector3(2, 2, 2))
	scene.add_child(first)
	var second: Node3D = ClassDB.instantiate("SlabSolid")
	second.name = "PowerHouseDoorCutter"
	second.call("make_box", Vector3(2, 2, 2))
	second.position.x = 1.0
	scene.add_child(second)
	var first_before: PackedByteArray = first.get("data")
	var second_before: PackedByteArray = second.get("data")
	var native_selection: Object = editor.get_selection()
	native_selection.clear()
	native_selection.add_node(first)
	native_selection.add_node(second)
	for i in 10: await process_frame
	_check(selection.objects == [first, second], "native_two_solid_order_reaches_boolean_panel")
	_check(panel.find_child("SettingsTitle", true, false).text == "Boolean operands", "native_two_solid_selection_refreshes_boolean_block")
	await _capture(editor, {"capture_prefix": "/tmp/slab-panel-boolean", "capture_rect": panel.get_global_rect()}, "after")
	var swap_btn: Button = panel.find_child("SwapBooleanOperands", true, false)
	var settings_scroll: ScrollContainer = panel.find_child("SettingsScroll", true, false)
	if settings_scroll != null and swap_btn != null:
		settings_scroll.ensure_control_visible(swap_btn)
	await process_frame
	await _click(swap_btn)
	var native_nodes: Array = native_selection.get_selected_nodes()
	_check(native_nodes == [second, first] and selection.objects == [second, first], "swap_preserves_two_native_solids_in_displayed_order")
	await _click(_button_named(panel.find_child("Commands", true, false), "Subtract"))
	_check(second.get("data") != second_before and first.get("data") == first_before,
		"rendered_swapped_subtract_edits_target_and_retains_cutter")
	manager.get_history_undo_redo(manager.get_object_history_id(second)).undo()
	native_selection.clear()
	first.free()
	second.free()
	await process_frame


func _create_strip_tool_blocking(editor: Object, panel: Control, selection: RefCounted, actions: RefCounted) -> void:
	await _click(_mode(panel, 0))
	var scene: Node = editor.get_edited_scene_root()
	var solid: Node3D = scene.get_node_or_null("Box2")
	if solid == null:
		_fail("create_strip_tool_blocking test requires Box2")
		return
	var native_selection: Object = editor.get_selection()
	native_selection.clear()
	native_selection.add_node(solid)
	selection.set_objects([solid])
	await process_frame
	await process_frame
	var create_strip: Control = panel.find_child("CreateStrip", true, false)
	var create_btn: Button = panel.find_child("CreateShape", true, false)
	_check(create_strip != null and create_strip.visible, "create_strip_visible_before_array")
	_check(create_btn != null and not create_btn.disabled, "create_enabled_before_array")
	await _click(_button_named(panel.find_child("Commands", true, false), "Array"))
	await process_frame
	_check(create_strip.visible, "create_strip_visible_during_array")
	_check(create_btn.disabled, "create_disabled_during_array")
	_check(create_btn.tooltip_text.begins_with("Finish or cancel"), "create_tooltip_shows_blocking_reason")
	actions.array_cancel_requested.emit()
	await process_frame
	_check(not create_btn.disabled, "create_enabled_after_array_cancel")
	await _click(_button_named(panel.find_child("Commands", true, false), "Plane Cut"))
	await process_frame
	_check(create_strip.visible, "create_strip_visible_during_plane")
	_check(create_btn.disabled, "create_disabled_during_plane")
	actions.plane_cancel_requested.emit()
	await process_frame
	_check(not create_btn.disabled, "create_enabled_after_plane_cancel")


func _room_tutorial(editor: Object, panel: Control, selection: RefCounted, manager: EditorUndoRedoManager) -> void:
	var native_selection: Object = editor.get_selection()
	native_selection.clear()
	selection.set_ids(PackedInt64Array())
	await process_frame
	await _click(_mode(panel, 0))
	var create_strip: Control = panel.find_child("CreateStrip", true, false)
	_check(create_strip != null and create_strip.visible, "create_strip_visible_in_object_mode")
	await _click(_button_named(panel.find_child("CreateChips", true, false), "Box"))
	for entry in [["size_x", 4.0], ["size_y", 3.0], ["size_z", 4.0]]:
		var box: Node = panel.find_child(entry[0], true, false)
		var field: SpinBox = box.find_children("*", "SpinBox", true, false)[0]
		field.value = entry[1]
		field.get_line_edit().release_focus()
	var scene: Node = editor.get_edited_scene_root()
	var count_before: int = scene.get_child_count()
	var create_btn: Button = panel.find_child("CreateShape", true, false)
	var scroll: ScrollContainer = panel.find_child("SettingsScroll", true, false)
	_check(create_btn != null and create_btn.is_visible_in_tree(), "create_button_visible_without_scrolling")
	_check(scroll == null or not scroll.get_global_rect().encloses(create_btn.get_global_rect()), "create_button_outside_settings_scroll")
	await process_frame
	await _click(create_btn)
	await _confirm_create(editor, Vector3.ZERO)
	var selected: Array[Node] = native_selection.get_selected_nodes()
	for i in 30:
		if not selected.is_empty() and scene.get_child_count() > count_before:
			break
		await process_frame
		selected = native_selection.get_selected_nodes()
	_check(scene.get_child_count() > count_before, "tutorial_create_adds_solid_to_scene")
	_check(not selected.is_empty(), "tutorial_create_selects_box")
	if selected.is_empty():
		return
	var room: Node3D = selected[0]
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

func _create_repeated(editor: Object, panel: Control, manager: EditorUndoRedoManager) -> void:
	await _click(_mode(panel, 0))
	var scene: Node = editor.get_edited_scene_root()
	var count := scene.get_child_count()
	await _click(_button_named(panel.find_child("CreateChips", true, false), "Cylinder"))
	_check(scene.get_child_count() == count, "choosing_shape_does_not_create")
	var height: SpinBox = panel.find_child("size_y", true, false).find_children("*", "SpinBox", true, false)[0]
	height.get_line_edit().grab_focus()
	height.get_line_edit().text = "5.25"
	height.apply()
	await process_frame
	await _click(panel.find_child("CreateShape", true, false))
	await _confirm_create(editor, Vector3(8, 0, 0))
	var native_selection: Object = editor.get_selection()
	var selected: Array[Node] = native_selection.get_selected_nodes()
	for i in 30:
		if not selected.is_empty():
			break
		await process_frame
		selected = native_selection.get_selected_nodes()
	_check(not selected.is_empty(), "create_selects_first_cylinder")
	if selected.is_empty():
		return
	var first: Node3D = selected[0]
	var bounds: AABB = first.call("get_local_aabb")
	_check(scene.get_child_count() == count + 1 and is_equal_approx(bounds.size.y, 5.25), "create_commits_focused_typed_dimensions")
	await _click(panel.find_child("CreateShape", true, false))
	await _confirm_create(editor, Vector3(12, 0, 0))
	selected = native_selection.get_selected_nodes()
	for i in 30:
		if not selected.is_empty():
			break
		await process_frame
		selected = native_selection.get_selected_nodes()
	_check(not selected.is_empty(), "create_selects_second_cylinder")
	if selected.is_empty():
		return
	var second: Node3D = selected[0]
	_check(second != first and scene.get_child_count() == count + 2 and second.call("get_local_aabb") == bounds, "repeat_create_retains_shape_and_dimensions")
	var create_strip: Control = panel.find_child("CreateStrip", true, false)
	var create: Control = panel.find_child("CreateShape", true, false)
	_check(create_strip != null and create_strip.get_global_rect().encloses(create.get_global_rect()), "create_button_in_create_strip_above_scroll")
	await _capture(editor, {"capture_prefix": "/tmp/slab-create-editor"}, "after")
	await _capture(editor, {"capture_prefix": "/tmp/slab-create-panel", "capture_rect": panel.get_global_rect()}, "after")
	var history := manager.get_history_undo_redo(manager.get_object_history_id(second))
	history.undo()
	_check(scene.get_child_count() == count + 1, "one_undo_removes_one_created_shape")
	history.undo()
	_check(scene.get_child_count() == count, "second_undo_restores_scene_before_creation")


func _confirm_create(editor: Object, at: Vector3) -> void:
	var session: RefCounted = _plugin(root).get("_session")
	var placement: RefCounted = session.get("_create")
	placement.call("_place_at", at, false)
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	session.handle(editor.get_editor_viewport_3d(0).get_camera_3d(), event)
	await create_timer(0.3).timeout


func _type_spin_text(spin: SpinBox, value: String) -> void:
	var line := spin.get_line_edit()
	line.grab_focus()
	await process_frame
	line.select_all()
	# The rendered harness cannot route text entry through the native window
	# reliably. Emit the same focused keyboard receipt used to distinguish a
	# pending user edit from a programmatic SpinBox value update.
	var typed := InputEventKey.new()
	typed.keycode = KEY_1
	typed.unicode = 49
	typed.pressed = true
	line.gui_input.emit(typed)
	line.text = value
	await process_frame
	_check(line.text == value, "pending numeric text is visible before Apply")


func _ensure_commands_visible(panel: Control, control: Control) -> void:
	if control == null:
		return
	var commands: Node = panel.find_child("Commands", true, false)
	if commands == null:
		return
	var scroll: Node = commands.get_parent()
	if scroll is ScrollContainer:
		(scroll as ScrollContainer).ensure_control_visible(control)
		await process_frame


func _click(button: Button) -> void:
	if button == null or button.disabled or not button.is_visible_in_tree():
		_fail("Requested panel button is unavailable")
		return
	SlabTestGui.ensure_scrolled(button)
	await process_frame
	SlabTestGui.hover(button)
	await process_frame
	var already_latched := button.toggle_mode and button.button_group != null and button.button_pressed
	var hits := {"n": 0}
	var on_pressed := func() -> void:
		hits["n"] += 1
	button.pressed.connect(on_pressed)
	SlabTestGui.mouse_click(button)
	button.pressed.disconnect(on_pressed)
	if hits["n"] == 0 and not already_latched:
		_fail("viewport mouse click did not fire pressed on %s" % button.text)
		return
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
