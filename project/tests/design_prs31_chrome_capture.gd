extends "res://tests/native_gizmo_editor_smoke.gd"

# PRS-31 docs chrome: Create strip, Op Card, Export, External, Soft Select, UV+Pack, Paint.
# DISPLAY=:5 scripts/godot --editor --path project --quit-after 300 --script res://tests/design_prs31_chrome_capture.gd
# Never saves the scene.

const OUT := "/tmp/slab-prs31"
const IMPORT_OBJ := "/tmp/slab_capture_import/box.obj"


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void: _fail("PRS-31 chrome capture exceeded 300 seconds"))
	_run.call_deferred()


func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("Requires --editor")
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var editor := Engine.get_singleton("EditorInterface")
	var deadline := Time.get_ticks_msec() + 45000
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		if Time.get_ticks_msec() > deadline:
			_fail("Editor initialization timed out")
			return
		await process_frame
	await create_timer(1.2).timeout
	if DisplayServer.window_get_size().x < 1200:
		DisplayServer.window_set_size(Vector2i(1280, 800))
		DisplayServer.window_set_position(Vector2i(0, 0))
		await create_timer(0.3).timeout

	# ---- modeller_lab: Create, Op Card, Soft Select, Export, External ----
	await _open_lab(editor)
	var plugin := _plugin(root)
	var panel: Control = plugin.get("_panel")
	var selection: RefCounted = plugin.get("_selection")
	var solid: Node3D = editor.get_edited_scene_root().get_node_or_null("Box2")
	if solid == null:
		_fail("Panel fixture is missing Box2")
		return
	await _focus_solid(editor, plugin, panel, selection, solid)

	# Object Create strip
	await _click(_mode(panel, 0))
	await create_timer(0.25).timeout
	var create_strip: Control = panel.find_child("CreateStrip", true, false)
	_check(create_strip != null and create_strip.visible, "create_strip_visible_object")
	var box_btn := _button_named_text(create_strip, "Box")
	_check(box_btn != null, "box_chip_present")
	await _click(box_btn)
	await create_timer(0.15).timeout
	_set_spin(create_strip, "Width", 2.0)
	_set_spin(create_strip, "Height", 2.0)
	_set_spin(create_strip, "Depth", 2.0)
	await create_timer(0.25).timeout
	await _snap(editor, panel, "panel-object")

	# Face Extrude Op Card
	await _click(_mode(panel, 3))
	var top := 0
	for id in solid.call("get_faces"):
		if solid.call("face_normal", id).y > 0.9:
			top = id
			break
	selection.set_ids(PackedInt64Array([top]))
	await create_timer(0.25).timeout
	await _click(_button_named_text(panel.find_child("Commands", true, false), "Extrude"))
	await create_timer(0.35).timeout
	var cancel_btn: Button = panel.find_child("OpCardCancel", true, false)
	var apply_btn: Button = panel.find_child("OpCardApply", true, false)
	_check(cancel_btn != null and apply_btn != null, "op_card_commit_buttons")
	_check(not apply_btn.disabled, "apply_enabled_valid_preview")
	await _snap(editor, panel, "panel-preview")
	await _snap(editor, panel, "panel")
	# Cancel preview before Soft Select
	if cancel_btn != null:
		await _click(cancel_btn)
		await create_timer(0.2).timeout

	# Soft Select — Vertex mode, on + radius/falloff chrome
	await _click(_mode(panel, 1))
	await create_timer(0.3).timeout
	_check(selection.mode == 1, "vertex_mode")
	var verts: PackedInt64Array = solid.call("get_vertices")
	var pick: int = verts[0]
	var best_y := -INF
	for v in verts:
		var p: Vector3 = solid.vertex_position(v)
		if p.y > best_y:
			best_y = p.y
			pick = v
	selection.set_ids(PackedInt64Array([pick]))
	await create_timer(0.25).timeout
	var soft_btn: Button = panel.find_child("SoftSelect", true, false)
	_check(soft_btn != null and not soft_btn.disabled, "soft_select_button")
	if soft_btn != null and not soft_btn.button_pressed:
		await _click(soft_btn)
	await create_timer(0.25).timeout
	_check(selection.soft_select, "soft_select_on")
	var soft_opts: HBoxContainer = panel.find_child("SoftSelectOptions", true, false)
	_check(soft_opts != null and soft_opts.visible, "soft_options_visible")
	var radius: SpinBox = panel.find_child("SoftRadius", true, false)
	if radius != null:
		radius.value = 2.5
	var falloff: OptionButton = panel.find_child("SoftFalloff", true, false)
	if falloff != null:
		falloff.select(0)
		falloff.item_selected.emit(0)
	await create_timer(0.35).timeout
	await _snap(editor, panel, "panel-soft-select")
	print("PANEL_SOFT_SELECT_RECT ", panel.get_global_rect())

	# Export… dialog with honest OBJ/STL/FBX filters
	await _click(_mode(panel, 0))
	await create_timer(0.25).timeout
	selection.set_objects([solid])
	var export_btn: Button = _button_named_text(panel, "Export...")
	_check(export_btn != null, "export_button")
	_ensure_visible(panel, export_btn)
	await create_timer(0.2).timeout
	await _click(export_btn)
	var dialog: EditorFileDialog = plugin.get("_export_dialog")
	if dialog == null or not is_instance_valid(dialog) or not dialog.visible:
		plugin.get("_actions").run("export_solids")
		await process_frame
		dialog = plugin.get("_export_dialog")
	var dlg_deadline := Time.get_ticks_msec() + 5000
	while (dialog == null or not is_instance_valid(dialog) or not dialog.visible) and Time.get_ticks_msec() < dlg_deadline:
		dialog = plugin.get("_export_dialog")
		await process_frame
	_check(dialog != null and dialog.visible, "export_dialog_open")
	if dialog != null:
		dialog.current_file = "box2.obj"
		var filter_btn := _find_filter_option(dialog)
		if filter_btn != null:
			var popup: PopupMenu = filter_btn.get_popup()
			if popup != null:
				filter_btn.show_popup()
				await create_timer(0.45).timeout
		await _snap_editor(editor, "panel-export")
		if filter_btn != null:
			var popup2: PopupMenu = filter_btn.get_popup()
			if popup2 != null and popup2.visible:
				popup2.hide()
		dialog.hide()
	print("PANEL_EXPORT captured")

	# External — import mesh, badge + disabled V/E/F, Promote visible
	_check(FileAccess.file_exists(IMPORT_OBJ), "fixture_obj_exists")
	var edited: Node = editor.get_edited_scene_root()
	for child in edited.get_children():
		if child is Node3D and (child.has_method("get_faces") or child is MeshInstance3D):
			if child != solid:
				edited.remove_child(child)
				child.free()
	await create_timer(0.3).timeout
	var import_btn: Button = _button_named_text(panel, "Import Mesh...")
	_check(import_btn != null, "import_button")
	_ensure_visible(panel, import_btn)
	await _click(import_btn)
	var import_dialog: EditorFileDialog = plugin.get("_import_dialog")
	if import_dialog == null or not is_instance_valid(import_dialog) or not import_dialog.visible:
		plugin.get("_actions").run("import_mesh")
		await process_frame
		import_dialog = plugin.get("_import_dialog")
	var imp_deadline := Time.get_ticks_msec() + 5000
	while (import_dialog == null or not is_instance_valid(import_dialog) or not import_dialog.visible) and Time.get_ticks_msec() < imp_deadline:
		import_dialog = plugin.get("_import_dialog")
		await process_frame
	_check(import_dialog != null and import_dialog.visible, "import_dialog_open")
	if import_dialog != null:
		import_dialog.file_selected.emit(IMPORT_OBJ)
		if import_dialog.visible:
			import_dialog.hide()
	await create_timer(0.6).timeout
	plugin.make_bottom_panel_item_visible(panel)
	var external: Node3D = null
	if selection.has_method("first_external_mesh"):
		external = selection.first_external_mesh()
	if external == null:
		for child2 in edited.get_children():
			if child2 is MeshInstance3D and not child2.has_method("get_faces"):
				external = child2
				break
	_check(external != null, "imported_external")
	if external != null:
		editor.get_selection().clear()
		editor.get_selection().add_node(external)
		editor.edit_node(external)
		selection.set_objects([external])
		selection.mode = 0
		await _click(_mode(panel, 0))
		await create_timer(0.35).timeout
		if panel.has_method("_reset_status"):
			panel.call("_reset_status")
		await process_frame
		var status_label: Label = panel.get("_status")
		var status_text := String(status_label.text) if status_label else ""
		_check(status_text.findn("External") >= 0 or String(selection.describe()).findn("External") >= 0, "external_badge")
		var v_btn: Button = _mode(panel, 1)
		var e_btn: Button = _mode(panel, 2)
		var f_btn: Button = _mode(panel, 3)
		_check(v_btn != null and v_btn.disabled, "vertex_disabled")
		_check(e_btn != null and e_btn.disabled, "edge_disabled")
		_check(f_btn != null and f_btn.disabled, "face_disabled")
		var promote_btn: Button = _button_named_text(panel, "Promote")
		_check(promote_btn != null and not promote_btn.disabled, "promote_visible_enabled")
		_ensure_visible(panel, promote_btn)
		await create_timer(0.35).timeout
		await _snap(editor, panel, "panel-external")
		print("PANEL_EXTERNAL_RECT ", panel.get_global_rect())

	# ---- signal_foundry: UV Mapping (Pack) + Surface/Pixel Paint ----
	await _capture_paint_uv(editor)

	print("DESIGN_PRS31_CHROME_CAPTURE failures=", failures)
	quit(0 if failures == 0 else 1)


func _capture_paint_uv(editor: Object) -> void:
	var scene_path := "res://demo/signal_foundry/signal_foundry.tscn"
	editor.open_scene_from_path(scene_path)
	editor.set_main_screen_editor("3D")
	var deadline := Time.get_ticks_msec() + 20000
	var stable := 0
	while stable < 15:
		await process_frame
		var edited: Node = editor.get_edited_scene_root()
		stable = stable + 1 if edited != null and edited.scene_file_path == scene_path else 0
		if Time.get_ticks_msec() > deadline:
			_fail("Signal Foundry did not remain current")
			return
	await create_timer(0.6).timeout
	var solid: Node3D = editor.get_edited_scene_root().get_node_or_null("MaintenanceBayRoof") as Node3D
	_check(solid != null, "foundry_roof")
	if solid == null:
		return
	var plugin := _plugin(root)
	var panel: Control = plugin.get("_panel")
	var selection: RefCounted = plugin.get("_selection")
	plugin.make_bottom_panel_item_visible(panel)
	editor.get_selection().clear()
	editor.get_selection().add_node(solid)
	editor.edit_node(solid)
	await create_timer(0.3).timeout
	selection.set_objects([solid])
	await _click(_mode(panel, 3))
	var top := 0
	var best_y := -INF
	for face in solid.call("get_faces"):
		var normal: Vector3 = solid.call("face_normal", face)
		var centre: Vector3 = solid.call("face_centroid", face)
		if normal.y > 0.9 and centre.y > best_y:
			best_y = centre.y
			top = face
	selection.set_ids(PackedInt64Array([top]))
	await create_timer(0.25).timeout

	# Material / UV — Mapping with Unwrap | Pack + Fit UV on canvas
	var uv_btn: Button = panel.find_child("UVWorkspace", true, false)
	if uv_btn == null:
		uv_btn = _button_named_text(panel, "UV")
	_check(uv_btn != null, "uv_workspace_button")
	await _click(uv_btn)
	panel.call("_enter_workspace", panel.Workspace.UV)
	plugin.make_bottom_panel_item_visible(panel)
	await create_timer(0.5).timeout
	var unwrap: Button = panel.find_child("PaintUnwrap", true, false)
	var pack: Button = panel.find_child("PaintPack", true, false)
	var fit: Button = panel.find_child("PaintFitUv", true, false)
	_check(unwrap != null and unwrap.visible, "unwrap_visible")
	_check(pack != null and pack.visible, "pack_visible")
	_check(fit != null and fit.visible, "fit_uv_visible")
	var inspector: ScrollContainer = panel.find_child("PaintInspector", true, false) as ScrollContainer
	if inspector != null and pack != null:
		inspector.ensure_control_visible(pack)
		await process_frame
		await process_frame
	await create_timer(0.4).timeout
	await _snap(editor, panel, "panel-material-uv")
	print("PANEL_MATERIAL_UV_RECT ", panel.get_global_rect())

	# Pixel paint — header Paint workspace (Material/UV↔Pixel chips are hidden)
	var paint_btn: Button = panel.find_child("PaintWorkspace", true, false)
	_check(paint_btn != null, "paint_workspace_button")
	await _click(paint_btn)
	panel.call("_enter_workspace", panel.Workspace.PAINT)
	plugin.make_bottom_panel_item_visible(panel)
	await create_timer(0.5).timeout
	_check(panel.current_workspace() == panel.Workspace.PAINT, "paint_workspace_open")
	inspector = panel.find_child("PaintInspector", true, false) as ScrollContainer
	var brush: Control = panel.get("_paint_brush")
	_check(brush != null and brush.visible, "paint_brush_visible")
	if inspector != null and brush != null:
		inspector.ensure_control_visible(brush)
		await process_frame
		await process_frame
	await create_timer(0.4).timeout
	var crop: Rect2 = panel.get_global_rect()
	for ctl in [brush, inspector]:
		if ctl != null:
			crop = crop.merge(ctl.get_global_rect())
	var brush_color: Control = panel.find_child("BrushColor", true, false)
	var brush_radius: Control = panel.find_child("brush_radius", true, false)
	var brush_opacity: Control = panel.find_child("brush_opacity", true, false)
	for ctl2 in [brush_color, brush_radius, brush_opacity]:
		if ctl2 != null:
			crop = crop.merge(ctl2.get_global_rect())
	crop = crop.grow_individual(4.0, 4.0, 4.0, 4.0)
	var vp: Rect2 = editor.get_base_control().get_viewport().get_visible_rect()
	crop = crop.intersection(vp)
	await _capture(editor, {"capture_prefix": OUT + "/panel-pixel-paint", "capture_rect": Rect2i(crop)}, "after")
	print("PANEL_PIXEL_PAINT_RECT ", crop)


func _open_lab(editor: Object) -> void:
	editor.open_scene_from_path("res://demo/modeller_lab.tscn")
	editor.set_main_screen_editor("3D")
	var stable_frames := 0
	var deadline := Time.get_ticks_msec() + 15000
	while stable_frames < 20:
		await process_frame
		var edited: Node = editor.get_edited_scene_root()
		stable_frames = stable_frames + 1 if edited != null and edited.scene_file_path == "res://demo/modeller_lab.tscn" else 0
		if Time.get_ticks_msec() > deadline:
			_fail("Panel fixture did not remain current after session restore")
			return
	await create_timer(0.4).timeout


func _focus_solid(editor: Object, plugin: EditorPlugin, panel: Control, selection: RefCounted, solid: Node3D) -> void:
	editor.get_selection().clear()
	editor.get_selection().add_node(solid)
	editor.edit_node(solid)
	await create_timer(0.35).timeout
	plugin.make_bottom_panel_item_visible(panel)
	await process_frame
	selection.set_objects([solid])


func _snap(editor: Object, panel: Control, name: String) -> void:
	await _capture(editor, {"capture_prefix": OUT + "/" + name, "capture_rect": panel.get_global_rect()}, "after")


func _snap_editor(editor: Object, name: String) -> void:
	await _capture(editor, {"capture_prefix": OUT + "/" + name}, "after")


func _ensure_visible(panel: Control, button: Button) -> void:
	if button == null:
		return
	var cmds: Node = panel.find_child("Commands", true, false)
	var scroll: ScrollContainer = null
	if cmds != null and cmds.get_parent() is ScrollContainer:
		scroll = cmds.get_parent()
	if scroll != null:
		scroll.ensure_control_visible(button)


func _find_filter_option(dialog: Node) -> OptionButton:
	if dialog == null:
		return null
	for child in dialog.find_children("*", "OptionButton", true, false):
		if child is OptionButton and (child as OptionButton).item_count >= 2:
			var ob := child as OptionButton
			for i in ob.item_count:
				var t := ob.get_item_text(i)
				if t.findn("OBJ") >= 0 or t.findn("STL") >= 0 or t.findn("FBX") >= 0 or t.findn(".obj") >= 0:
					return ob
			return ob
	return null


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
	await process_frame
	if button.toggle_mode:
		if button.button_group != null:
			button.pressed.emit()
		else:
			if not button.button_pressed:
				button.button_pressed = true
				button.pressed.emit()
	else:
		button.pressed.emit()
	await create_timer(0.15).timeout


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
