@tool
extends EditorPlugin

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")
const SlabSweepScript := preload("res://addons/slab/slab_sweep.gd")
const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
const SlabPaint := preload("res://addons/slab/slab_paint.gd")
const SlabEditorHostLive := preload("res://addons/slab/slab_editor_host_live.gd")
const SolidGizmo := preload("res://addons/slab/gizmos/slab_solid_gizmo.gd")
const SocketGizmo := preload("res://addons/slab/gizmos/slab_socket_gizmo.gd")
const SweepGizmo := preload("res://addons/slab/gizmos/slab_sweep_gizmo.gd")

var _host: RefCounted
var _session: RefCounted
var _selection: RefCounted
var _actions: RefCounted
var _paint: RefCounted
var _panel: Control
var _strip: Control
var _gizmos: Array = []
var _solid_gizmo: EditorNode3DGizmoPlugin
var _subgizmo_token := ""
var _subgizmo_solid: Node3D = null
var _topology_solid: Node3D = null
var _workspace := "3D"
var _overlay_camera: Camera3D


func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	set_process_shortcut_input(true)
	_host = SlabEditorHostLive.with_undo(get_undo_redo())
	_session = SlabViewport.new(_host)
	_selection = _session.state()
	_actions = SlabActions.new(_selection, get_undo_redo())
	_session.bind_actions(_actions)
	_paint = SlabPaint.new()
	_paint.bind(_selection, _actions, get_undo_redo(), _host)
	_session.bind_paint(_paint)
	if _paint.has_signal("changed"):
		_paint.changed.connect(_refresh_gizmos)
	_add_gizmos()
	add_custom_type("SlabSweep", "Node3D", SlabSweepScript, SlabIcons.texture("Curve3D", EditorInterface.get_editor_scale()))

	var metrics: RefCounted = _session.metrics()
	_panel = SlabPanel.new()
	_panel.setup(_selection, _actions, metrics)
	_panel.bind_undo(get_undo_redo())
	_panel.bind_paint(_paint)
	add_control_to_bottom_panel(_panel, "Slab")
	make_bottom_panel_item_visible(_panel)

	_strip = SlabModeStrip.new()
	_strip.setup(_selection, false, metrics)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _strip)

	_host.connect_host_selection(_on_editor_selection_changed)
	_selection.changed.connect(_on_selection_changed)
	_selection.hover_changed.connect(_refresh_gizmos)
	_selection.settings_changed.connect(_on_selection_settings_changed)
	_sync_native_local_axes()
	_on_editor_selection_changed()
	main_screen_changed.connect(_on_main_screen_changed)
	if not scene_saved.is_connected(_on_scene_saved):
		scene_saved.connect(_on_scene_saved)
	if OS.get_environment("SLAB_CAPTURE_VIEWPORT") != "":
		_wait_then_capture()


func _exit_tree() -> void:
	if _session:
		_session.cancel_create_preview()
	if _host:
		_host.disconnect_host_selection(_on_editor_selection_changed)
	if main_screen_changed.is_connected(_on_main_screen_changed):
		main_screen_changed.disconnect(_on_main_screen_changed)
	if scene_saved.is_connected(_on_scene_saved):
		scene_saved.disconnect(_on_scene_saved)
	if _selection:
		if _selection.changed.is_connected(_on_selection_changed):
			_selection.changed.disconnect(_on_selection_changed)
		if _selection.hover_changed.is_connected(_refresh_gizmos):
			_selection.hover_changed.disconnect(_refresh_gizmos)
		if _selection.settings_changed.is_connected(_on_selection_settings_changed):
			_selection.settings_changed.disconnect(_on_selection_settings_changed)
	if _paint:
		if _paint.has_signal("changed") and _paint.changed.is_connected(_refresh_gizmos):
			_paint.changed.disconnect(_refresh_gizmos)
	if _panel:
		_panel.bind_undo(null)
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
	if _strip:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _strip)
		_strip.queue_free()
		_strip = null
	remove_custom_type("SlabSweep")
	_clear_subgizmo()
	_bind_topology_solid(null)
	for gizmo in _gizmos:
		remove_node_3d_gizmo_plugin(gizmo)
	_gizmos.clear()
	_solid_gizmo = null
	_actions = null
	_paint = null
	_selection = null
	_session = null
	_host = null


func _handles(object: Object) -> bool:
	return SlabSelection.editor_owning_solid(object) != null


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	_overlay_camera = viewport_camera
	update_overlays()
	if _session == null:
		return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and get_viewport().is_input_handled():
		return AFTER_GUI_INPUT_STOP
	var native_was_pending: bool = _session.native_gizmo_pending()
	var verdict: int = _session.handle(viewport_camera, event)
	# Updating a Node3D's gizmos schedules a rebuild. Doing that between the
	# native handle press and its motion invalidates Godot's active subgizmo.
	if not native_was_pending and not _session.native_gizmo_pending():
		_refresh_gizmos()
	else:
		update_overlays()
		if native_was_pending and not _session.native_gizmo_pending():
			_refresh_gizmos.call_deferred()
	if verdict == SlabViewport.Verdict.STOP and event is InputEventKey:
		get_viewport().set_input_as_handled()
	return SlabViewport.after_gui_input(verdict)


func _shortcut_input(event: InputEvent) -> void:
	if _session == null:
		return
	var host_viewport := get_viewport()
	if host_viewport != null and host_viewport.is_input_handled():
		return
	var viewport_3d := EditorInterface.get_editor_viewport_3d(0)
	if not should_claim_shortcut(event, viewport_3d, host_viewport, _workspace):
		return
	var camera: Camera3D = viewport_3d.get_camera_3d() if viewport_3d != null else null
	if camera == null:
		return
	var verdict: int = _session.handle(camera, event)
	_refresh_gizmos()
	if verdict == SlabViewport.Verdict.STOP and host_viewport != null:
		host_viewport.set_input_as_handled()


func _on_main_screen_changed(screen_name: String) -> void:
	_workspace = screen_name


func _on_scene_saved(path: String) -> void:
	if _paint != null:
		_paint.scene_saved(path)


func _on_selection_settings_changed() -> void:
	_sync_native_local_axes()
	_refresh_gizmos()


func _sync_native_local_axes() -> void:
	if _selection == null:
		return
	var viewport_3d := EditorInterface.get_editor_viewport_3d(0)
	var spatial := spatial_editor_root(viewport_3d)
	if spatial == null:
		return
	var want_local: bool = _selection.orientation != SlabSelection.Orientation.WORLD
	for child in spatial.find_children("*", "Button", true, false):
		var button := child as Button
		if button == null or not shortcut_has_key(button.shortcut, KEY_T):
			continue
		if button.button_pressed != want_local:
			button.button_pressed = want_local
		return


static func shortcut_has_key(shortcut: Shortcut, keycode: Key) -> bool:
	if shortcut == null:
		return false
	for event in shortcut.events:
		if event is InputEventKey and (event.keycode == keycode or event.physical_keycode == keycode):
			return true
	return false


static func should_claim_shortcut(
	event: InputEvent,
	viewport_3d: Node,
	host_viewport: Viewport,
	workspace: String = "3D"
) -> bool:
	if not is_plain_modeling_key(event):
		return false
	if not spatial_editor_is_active(viewport_3d, workspace):
		return false
	var focus: Control = focus_owner(host_viewport)
	if focus_eats_keys(focus):
		return false
	return not focus_is_outside_spatial_editor(focus, viewport_3d)


static func is_plain_modeling_key(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	return not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed)


static func spatial_editor_is_active(viewport_3d: Node, workspace: String = "3D") -> bool:
	if workspace != "3D":
		return false
	if viewport_3d == null or not viewport_3d.is_inside_tree():
		return false
	return ancestor_visible_in_tree(viewport_3d)


static func ancestor_visible_in_tree(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if current is CanvasItem:
			return (current as CanvasItem).is_visible_in_tree()
		if current is Node3D:
			return (current as Node3D).is_visible_in_tree()
		current = current.get_parent()
	return true


static func focus_is_outside_spatial_editor(focus: Control, viewport_3d: Node) -> bool:
	if focus == null:
		return false
	var spatial: Node = spatial_editor_root(viewport_3d)
	if spatial == null:
		return true
	return not (spatial == focus or spatial.is_ancestor_of(focus))


static func spatial_editor_root(viewport_3d: Node) -> Node:
	var node: Node = viewport_3d
	var viewport_root: Node = null
	while node != null:
		var cls: String = node.get_class()
		if cls == "Node3DEditor":
			return node
		if cls == "Node3DEditorViewport" and viewport_root == null:
			viewport_root = node
		node = node.get_parent()
	return viewport_root if viewport_root != null else viewport_3d


static func focus_owner(viewport: Viewport) -> Control:
	if viewport == null:
		return null
	return viewport.gui_get_focus_owner()


static func focus_eats_keys(focus: Control) -> bool:
	if focus == null:
		return false
	if focus is LineEdit or focus is TextEdit or focus is CodeEdit:
		return true
	var parent: Node = focus.get_parent()
	return parent is SpinBox or parent is LineEdit


func _on_editor_selection_changed() -> void:
	if _session == null:
		return
	_session.adopt_host_selection()
	_bind_topology_solid(_selection.solid)
	_refresh_gizmos()


func _on_selection_changed() -> void:
	_bind_topology_solid(_selection.solid)
	_refresh_gizmos()


func _bind_topology_solid(solid: Node3D) -> void:
	if solid == _topology_solid:
		return
	if _topology_solid != null and is_instance_valid(_topology_solid) \
			and _topology_solid.has_signal("topology_changed") \
			and _topology_solid.topology_changed.is_connected(_on_selected_topology_changed):
		_topology_solid.topology_changed.disconnect(_on_selected_topology_changed)
	_topology_solid = solid
	if _topology_solid != null and is_instance_valid(_topology_solid) \
			and _topology_solid.has_signal("topology_changed") \
			and not _topology_solid.topology_changed.is_connected(_on_selected_topology_changed):
		_topology_solid.topology_changed.connect(_on_selected_topology_changed)


func _on_selected_topology_changed() -> void:
	_subgizmo_token = ""
	if _session != null and not _session.native_gizmo_pending():
		_refresh_gizmos.call_deferred()


func _refresh_gizmos() -> void:
	var selection_solid: Node3D = _selection.solid
	if selection_solid == null:
		selection_solid = _topology_solid
	if _session != null:
		for node in _session.gizmo_targets():
			if is_instance_valid(node):
				node.update_gizmos()
	if selection_solid != null and is_instance_valid(selection_solid):
		selection_solid.update_gizmos()
	_sync_subgizmo(selection_solid)
	update_overlays()


func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	if _selection == null or _overlay_camera == null or not is_instance_valid(_overlay_camera):
		return
	var label: Dictionary = SolidGizmo.operation_overlay_label(_selection.operation_preview, _overlay_camera)
	if label.is_empty(): return
	var preview: Dictionary = _selection.operation_preview
	var kind := int(preview.get("kind", 0))
	var color := Color(0.2, 0.95, 0.85) if kind == 0 else (Color(0.95, 0.72, 0.18) if kind == 1 else Color(0.8, 0.45, 1.0))
	if int(preview.get("error", OK)) != OK:
		color = Color(1.0, 0.2, 0.3)
	var lines := SolidGizmo.operation_handle_lines(preview)
	for i in range(0, lines.size() - 1, 2):
		if _overlay_camera.is_position_behind(lines[i]) or _overlay_camera.is_position_behind(lines[i + 1]):
			continue
		var start := _overlay_camera.unproject_position(lines[i])
		var end := _overlay_camera.unproject_position(lines[i + 1])
		overlay.draw_line(start, end, Color(0.04, 0.05, 0.06, 0.9), 4.0, true)
		overlay.draw_line(start, end, color, 2.0, true)
	var tip := _overlay_camera.unproject_position(preview.get("tip", Vector3.ZERO))
	overlay.draw_circle(tip, 7.0, Color(0.04, 0.05, 0.06))
	overlay.draw_circle(tip, 5.0, color)
	var font: Font = ThemeDB.fallback_font
	var size: int = int(14 * EditorInterface.get_editor_scale())
	var point: Vector2 = label["screen"]
	var text: String = label["text"]
	var extent: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	point.x = clampf(point.x, 8, maxf(8, overlay.size.x - extent.x - 8))
	point.y = clampf(point.y, size + 8, maxf(size + 8, overlay.size.y - 8))
	overlay.draw_style_box(_handle_label_style(), Rect2(point - Vector2(6, size), extent + Vector2(12, 8)))
	overlay.draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


func _handle_label_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.1, 0.9)
	style.set_corner_radius_all(4)
	return style


func _sync_subgizmo(override_solid: Node3D = null) -> void:
	var solid: Node3D = override_solid if override_solid != null else _selection.solid
	if solid == null:
		solid = _topology_solid
	if solid == null or not is_instance_valid(solid) or _selection.mode == SlabSelection.Mode.OBJECT or _selection.ids.is_empty():
		_clear_subgizmo()
		return
	var token: String = "%s:%d:%s:%d:%d:%d:%s" % [solid.get_instance_id(), _selection.mode, ",".join(_id_tokens(_selection.ids)), _selection.pivot_mode, _selection.orientation, _selection.active_id, _selection.custom_pivot_world]
	if token == _subgizmo_token:
		return
	if _subgizmo_solid != null and is_instance_valid(_subgizmo_solid) and _subgizmo_solid != solid:
		_subgizmo_solid.clear_subgizmo_selection()
	var gizmos: Array = solid.get_gizmos()
	if gizmos.is_empty():
		solid.update_gizmos()
		gizmos = solid.get_gizmos()
	for gizmo in gizmos:
		var gizmo_plugin: EditorNode3DGizmoPlugin = gizmo.get_plugin()
		if gizmo_plugin == null or gizmo_plugin.get_gizmo_name() != "SlabSolid":
			continue
		solid.set_subgizmo_selection(gizmo, SolidGizmo.SELECTION_SUBGIZMO, _solid_gizmo._get_subgizmo_transform(gizmo, SolidGizmo.SELECTION_SUBGIZMO))
		_subgizmo_token = token
		_subgizmo_solid = solid
		return
	_clear_subgizmo()


func _clear_subgizmo() -> void:
	if _subgizmo_solid != null and is_instance_valid(_subgizmo_solid):
		_subgizmo_solid.clear_subgizmo_selection()
	_subgizmo_token = ""
	_subgizmo_solid = null


func _id_tokens(ids: PackedInt64Array) -> PackedStringArray:
	var tokens := PackedStringArray()
	for id in ids:
		tokens.append(str(id))
	return tokens


func _add_gizmos() -> void:
	_solid_gizmo = SolidGizmo.new()
	_solid_gizmo.setup(_selection, get_undo_redo(), _paint)
	_gizmos = [_solid_gizmo, SocketGizmo.new(), SweepGizmo.new()]
	for gizmo in _gizmos:
		add_node_3d_gizmo_plugin(gizmo)


func _wait_then_capture() -> void:
	for i in 80:
		if EditorInterface.get_edited_scene_root() != null and ClassDB.class_exists(SlabSelection.SOLID_CLASS):
			await _capture_predicate()
			return
		await get_tree().create_timer(0.1).timeout
	push_error("capture timed out waiting for the edited scene")
	get_tree().quit()


func _capture_predicate() -> void:
	var path: String = OS.get_environment("SLAB_CAPTURE_VIEWPORT")
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		push_error("capture needs an open scene and SlabSolid")
		get_tree().quit()
		return
	make_bottom_panel_item_visible(_panel)
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	solid.name = "CaptureSolid"
	root.add_child(solid)
	solid.owner = root
	solid.call("make_box", Vector3(2, 3, 2))
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(solid)
	EditorInterface.edit_node(solid)
	_selection.mode = SlabSelection.Mode.FACE
	var top: int = 0
	var up := -2.0
	for id in PackedInt64Array(solid.call("get_faces")):
		var n: Vector3 = solid.call("face_normal", id)
		if n.y > up:
			up = n.y
			top = id
	_selection.set_ids(PackedInt64Array([top]))
	solid.call("extrude_faces", PackedInt64Array([top]), 1.0)
	solid.update_gizmos()
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var img: Image = viewport.get_texture().get_image()
	img.save_png(path)
	print("slab capture wrote ", path, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()
