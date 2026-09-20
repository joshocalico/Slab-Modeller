extends "res://tests/native_gizmo_editor_smoke.gd"

# PRS-31 docs chrome: Create strip (Box W/H/D) + Extrude Op Card.
# DISPLAY=:5 scripts/godot --editor --path project --quit-after 120 --script res://tests/design_prs31_chrome_capture.gd
# Never saves the scene.

const OUT := "/tmp/slab-prs31"

func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("Requires --editor")
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var editor := Engine.get_singleton("EditorInterface")
	var deadline := Time.get_ticks_msec() + 30000
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		if Time.get_ticks_msec() > deadline:
			_fail("Editor initialization timed out")
			return
		await process_frame
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
	if DisplayServer.window_get_size().x < 1200:
		DisplayServer.window_set_size(Vector2i(1280, 720))
		await create_timer(0.3).timeout
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
	plugin.make_bottom_panel_item_visible(panel)
	await process_frame
	selection.set_objects([solid])

	# Object mode Create strip — Box + Width/Height/Depth + Create
	await _click(_mode(panel, 0))
	await create_timer(0.3).timeout
	var create_strip: Control = panel.find_child("CreateStrip", true, false)
	_check(create_strip != null and create_strip.visible, "create_strip_visible_object")
	var box_btn := _button_named_text(create_strip, "Box")
	_check(box_btn != null, "box_chip_present")
	await _click(box_btn)
	await create_timer(0.2).timeout
	_set_spin(create_strip, "Width", 2.0)
	_set_spin(create_strip, "Height", 2.0)
	_set_spin(create_strip, "Depth", 2.0)
	await create_timer(0.35).timeout
	var create_btn := _button_named_text(create_strip, "Create")
	_check(create_btn != null and create_btn.visible, "create_button_visible")
	await _capture(editor, {"capture_prefix": OUT + "/panel-object-editor"}, "after")
	await _capture(editor, {"capture_prefix": OUT + "/panel-object", "capture_rect": panel.get_global_rect()}, "after")
	print("PANEL_OBJECT_RECT ", panel.get_global_rect())

	# Face Extrude Op Card — Cancel | yellow Apply
	await _click(_mode(panel, 3))
	var top := 0
	for id in solid.call("get_faces"):
		if solid.call("face_normal", id).y > 0.9:
			top = id
			break
	selection.set_ids(PackedInt64Array([top]))
	await create_timer(0.3).timeout
	await _click(_button_named_text(panel.find_child("Commands", true, false), "Extrude"))
	await create_timer(0.4).timeout
	var cancel_btn: Button = panel.find_child("OpCardCancel", true, false)
	var apply_btn: Button = panel.find_child("OpCardApply", true, false)
	_check(cancel_btn != null and apply_btn != null, "op_card_commit_buttons")
	_check(cancel_btn.get_global_rect().position.x < apply_btn.get_global_rect().position.x, "cancel_left_apply_right")
	_check(not apply_btn.disabled, "apply_enabled_valid_preview")
	await _capture(editor, {"capture_prefix": OUT + "/panel-preview-editor"}, "after")
	await _capture(editor, {"capture_prefix": OUT + "/panel-preview", "capture_rect": panel.get_global_rect()}, "after")
	# panel.png MDX alt describes Extrude op card — same crop
	await _capture(editor, {"capture_prefix": OUT + "/panel", "capture_rect": panel.get_global_rect()}, "after")
	print("PANEL_PREVIEW_RECT ", panel.get_global_rect())
	print("DESIGN_PRS31_CHROME_CAPTURE failures=", failures)
	quit(0 if failures == 0 else 1)


func _set_spin(root_n: Node, label: String, value: float) -> void:
	for n in root_n.find_children("*", "SpinBox", true, false):
		var p := n.get_parent()
		if p == null:
			continue
		for sib in p.get_children():
			if sib is Label and String(sib.text).findn(label) >= 0:
				(n as SpinBox).value = value
				return
	var named: Node = root_n.find_child(label, true, false)
	if named is SpinBox:
		(named as SpinBox).value = value


func _click(button: Button) -> void:
	if button == null or button.disabled or not button.is_visible_in_tree():
		_fail("Requested panel button is unavailable")
		return
	var position := button.get_global_rect().get_center()
	Input.warp_mouse(Vector2i(position))
	await process_frame
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
	if node is Button and node.get_meta("slab_mode", -1) == value:
		return node
	for child in node.get_children():
		var found := _mode(child, value)
		if found != null:
			return found
	return null


func _button_named_text(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and String(node.text).findn(text) >= 0:
		return node
	for child in node.get_children():
		var found := _button_named_text(child, text)
		if found != null:
			return found
	return null
