@tool
extends EditorPlugin

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")
const SlabSweepScript := preload("res://addons/slab/slab_sweep.gd")
const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
const SlabEditorHostLive := preload("res://addons/slab/slab_editor_host_live.gd")
const SolidGizmo := preload("res://addons/slab/gizmos/slab_solid_gizmo.gd")
const SocketGizmo := preload("res://addons/slab/gizmos/slab_socket_gizmo.gd")
const SweepGizmo := preload("res://addons/slab/gizmos/slab_sweep_gizmo.gd")

var _host: RefCounted
var _session: RefCounted
var _selection: RefCounted
var _actions: RefCounted
var _panel: Control
var _strip: Control
var _gizmos: Array = []
var _solid_gizmo: EditorNode3DGizmoPlugin
var _subgizmo_token := ""
var _subgizmo_solid: Node3D = null


func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	_host = SlabEditorHostLive.with_undo(get_undo_redo())
	_session = SlabViewport.new(_host)
	_selection = _session.state()
	_actions = SlabActions.new(_selection, get_undo_redo())
	_session.bind_actions(_actions)
	_add_gizmos()
	add_custom_type("SlabSweep", "Node3D", SlabSweepScript, SlabIcons.texture("Curve3D", EditorInterface.get_editor_scale()))

	var metrics: RefCounted = _session.metrics()
	_panel = SlabPanel.new()
	_panel.setup(_selection, _actions, metrics)
	add_control_to_bottom_panel(_panel, "Slab")
	make_bottom_panel_item_visible(_panel)

	_strip = SlabModeStrip.new()
	_strip.setup(_selection, false, metrics)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _strip)

	_host.connect_host_selection(_on_editor_selection_changed)
	_selection.changed.connect(_refresh_gizmos)
	_selection.hover_changed.connect(_refresh_gizmos)
	_on_editor_selection_changed()
	if OS.get_environment("SLAB_CAPTURE_VIEWPORT") != "":
		_wait_then_capture()


func _exit_tree() -> void:
	if _host:
		_host.disconnect_host_selection(_on_editor_selection_changed)
	if _selection:
		if _selection.changed.is_connected(_refresh_gizmos):
			_selection.changed.disconnect(_refresh_gizmos)
		if _selection.hover_changed.is_connected(_refresh_gizmos):
			_selection.hover_changed.disconnect(_refresh_gizmos)
	if _panel:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
	if _strip:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _strip)
		_strip.queue_free()
		_strip = null
	remove_custom_type("SlabSweep")
	_clear_subgizmo()
	for gizmo in _gizmos:
		remove_node_3d_gizmo_plugin(gizmo)
	_gizmos.clear()
	_solid_gizmo = null
	_actions = null
	_selection = null
	_session = null
	_host = null


func _handles(object: Object) -> bool:
	return SlabSelection.owning_solid(object) != null


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if _session == null:
		return AFTER_GUI_INPUT_PASS
	var verdict: int = _session.handle(viewport_camera, event)
	_refresh_gizmos()
	return SlabViewport.after_gui_input(verdict)


func _on_editor_selection_changed() -> void:
	if _session == null:
		return
	_session.adopt_host_selection()
	_refresh_gizmos()


func _refresh_gizmos() -> void:
	if _session == null:
		return
	for node in _session.gizmo_targets():
		if is_instance_valid(node):
			node.update_gizmos()
	_sync_subgizmo()


func _sync_subgizmo() -> void:
	var solid: Node3D = _selection.solid
	if solid == null or not is_instance_valid(solid) or _selection.mode == SlabSelection.Mode.OBJECT or _selection.ids.is_empty():
		_clear_subgizmo()
		return
	var token: String = "%s:%d:%s" % [solid.get_instance_id(), _selection.mode, ",".join(_id_tokens(_selection.ids))]
	if token == _subgizmo_token:
		return
	if _subgizmo_solid != null and is_instance_valid(_subgizmo_solid) and _subgizmo_solid != solid:
		_subgizmo_solid.clear_subgizmo_selection()
	for gizmo in solid.get_gizmos():
		if gizmo.get_plugin() != _solid_gizmo:
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
	_solid_gizmo.setup(_selection, get_undo_redo())
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
