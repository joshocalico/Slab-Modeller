@tool
extends EditorPlugin

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabSweepScript := preload("res://addons/slab/slab_sweep.gd")
const SolidGizmo := preload("res://addons/slab/gizmos/slab_solid_gizmo.gd")
const SocketGizmo := preload("res://addons/slab/gizmos/slab_socket_gizmo.gd")
const SweepGizmo := preload("res://addons/slab/gizmos/slab_sweep_gizmo.gd")

var _selection: RefCounted
var _actions: RefCounted
var _panel: Control
var _strip: Control
var _gizmos: Array = []
var _gizmo_nodes: Array[Node3D] = []


func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	_selection = SlabSelection.new()
	_actions = SlabActions.new(_selection, get_undo_redo())
	_add_gizmos()
	add_custom_type("SlabSweep", "Node3D", SlabSweepScript, SlabIcons.texture("Curve3D"))

	_panel = SlabPanel.new()
	_panel.setup(_selection, _actions)
	add_control_to_bottom_panel(_panel, "Slab")
	make_bottom_panel_item_visible(_panel)

	_strip = SlabModeStrip.new()
	_strip.setup(_selection, false)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _strip)

	EditorInterface.get_selection().selection_changed.connect(_sync_selection)
	_selection.changed.connect(_refresh_gizmos)
	_selection.hover_changed.connect(_refresh_gizmos)
	_sync_selection()
	if OS.get_environment("SLAB_CAPTURE_VIEWPORT") != "":
		_wait_then_capture()


func _exit_tree() -> void:
	var editor_selection := EditorInterface.get_selection()
	if editor_selection and editor_selection.selection_changed.is_connected(_sync_selection):
		editor_selection.selection_changed.disconnect(_sync_selection)
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
	for gizmo in _gizmos:
		remove_node_3d_gizmo_plugin(gizmo)
	_gizmos.clear()
	_actions = null
	_selection = null


func _handles(object: Object) -> bool:
	return SlabSelection.owning_solid(object) != null


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if _selection == null:
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		_on_hover(viewport_camera, event.position)
		return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and not event.echo:
		return _on_key(event)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return _on_click(viewport_camera, event)
	return AFTER_GUI_INPUT_PASS


func _on_key(event: InputEventKey) -> int:
	if event.ctrl_pressed or event.meta_pressed:
		return AFTER_GUI_INPUT_PASS
	if event.keycode == KEY_ESCAPE:
		_selection.mode = SlabSelection.Mode.OBJECT
		return AFTER_GUI_INPUT_STOP
	var mode: int = SlabModeStrip.mode_for_keycode(event.keycode)
	if mode != -1:
		_selection.mode = mode
		return AFTER_GUI_INPUT_STOP
	if event.alt_pressed:
		return AFTER_GUI_INPUT_PASS
	if _actions.run_shortcut(event.keycode):
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _on_hover(camera: Camera3D, screen: Vector2) -> void:
	var hit: Node3D = SlabPick.pick_solid(EditorInterface.get_edited_scene_root(), camera, screen)
	if hit == null or _selection.mode == SlabSelection.Mode.OBJECT:
		_selection.set_hover(hit, 0)
		return
	_selection.set_hover(hit, SlabPick.pick(hit, _selection.mode, camera, screen))


func _on_click(camera: Camera3D, event: InputEventMouseButton) -> int:
	var additive: bool = event.shift_pressed or event.ctrl_pressed or event.meta_pressed
	var hit: Node3D = SlabPick.pick_solid(EditorInterface.get_edited_scene_root(), camera, event.position)
	if _selection.mode == SlabSelection.Mode.OBJECT:
		if hit == null:
			return AFTER_GUI_INPUT_PASS
		_select_in_editor(hit, additive)
		return AFTER_GUI_INPUT_STOP
	if hit == null:
		if not additive:
			_selection.clear_ids()
		return AFTER_GUI_INPUT_STOP if _selection.solid != null else AFTER_GUI_INPUT_PASS
	_select_in_editor(hit, false)
	var id: int = SlabPick.pick(hit, _selection.mode, camera, event.position)
	if id == 0:
		if not additive:
			_selection.clear_ids()
		return AFTER_GUI_INPUT_STOP
	_selection.toggle_id(id, additive)
	return AFTER_GUI_INPUT_STOP


func _select_in_editor(solid: Node3D, additive: bool) -> void:
	var editor_selection := EditorInterface.get_selection()
	if not additive:
		if _selection.objects.size() == 1 and _selection.objects[0] == solid:
			EditorInterface.edit_node(solid)
			return
		editor_selection.clear()
	editor_selection.add_node(solid)
	EditorInterface.edit_node(solid)


func _sync_selection() -> void:
	_selection.set_objects(EditorInterface.get_selection().get_selected_nodes())


func _refresh_gizmos() -> void:
	var seen: Dictionary = {}
	var next: Array[Node3D] = []
	for node in _selection.objects:
		_touch_gizmo(node, seen, next)
	_touch_gizmo(_selection.hover_solid, seen, next)
	for node in _gizmo_nodes:
		_touch_gizmo(node, seen, next)
	_gizmo_nodes = next


func _touch_gizmo(node: Node3D, seen: Dictionary, next: Array[Node3D]) -> void:
	if node == null or not is_instance_valid(node) or seen.has(node):
		return
	seen[node] = true
	next.append(node)
	node.update_gizmos()


func _add_gizmos() -> void:
	var solid := SolidGizmo.new()
	solid.setup(_selection)
	_gizmos = [solid, SocketGizmo.new(), SweepGizmo.new()]
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
