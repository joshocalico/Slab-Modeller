@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")

enum Verdict { PASS, STOP }

var _host: RefCounted
var _metrics: RefCounted
var _selection: RefCounted
var _actions: RefCounted
var _gizmo_nodes: Array[Node3D] = []


func _init(host: RefCounted) -> void:
	_host = host
	_selection = SlabSelection.new()
	_metrics = SlabMetrics.of(host)


func bind_actions(actions: RefCounted) -> void:
	_actions = actions


static func after_gui_input(verdict: int) -> int:
	return verdict


func handle(camera: Camera3D, event: InputEvent) -> int:
	if _selection == null:
		return Verdict.PASS
	if event is InputEventMouseMotion:
		_on_hover(camera, event.position)
		return Verdict.PASS
	if event is InputEventKey and event.pressed and not event.echo:
		return _on_key(event)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return _on_click(camera, event)
	return Verdict.PASS


func adopt_host_selection() -> void:
	_selection.set_objects(_host.selected_nodes())


func gizmo_targets() -> Array[Node3D]:
	var seen: Dictionary = {}
	var current: Array[Node3D] = []
	for node in _selection.objects:
		_touch_gizmo(node, seen, current)
	_touch_gizmo(_selection.hover_solid, seen, current)
	var previous: Array[Node3D] = _gizmo_nodes
	_gizmo_nodes = current
	var next: Array[Node3D] = current.duplicate()
	for node in previous:
		_touch_gizmo(node, seen, next)
	return next


func state() -> RefCounted:
	return _selection


func metrics() -> RefCounted:
	return _metrics


func _on_key(event: InputEventKey) -> int:
	if event.ctrl_pressed or event.meta_pressed:
		return Verdict.PASS
	if event.keycode == KEY_ESCAPE:
		_selection.mode = SlabSelection.Mode.OBJECT
		return Verdict.STOP
	var mode: int = SlabModeStrip.mode_for_keycode(event.keycode)
	if mode != -1:
		_selection.mode = mode
		return Verdict.STOP
	if event.alt_pressed:
		return Verdict.PASS
	if _actions != null and _actions.run_shortcut(event.keycode):
		return Verdict.STOP
	return Verdict.PASS


func _on_hover(camera: Camera3D, screen: Vector2) -> void:
	var hit: Node3D = SlabPick.pick_solid(_host.scene_root(), camera, screen)
	if hit == null or _selection.mode == SlabSelection.Mode.OBJECT:
		_selection.set_hover(hit, 0)
		return
	_selection.set_hover(hit, SlabPick.pick(hit, _selection.mode, camera, screen, _metrics.pick_radius()))


func _on_click(camera: Camera3D, event: InputEventMouseButton) -> int:
	var additive: bool = event.shift_pressed or event.ctrl_pressed or event.meta_pressed
	var hit: Node3D = SlabPick.pick_solid(_host.scene_root(), camera, screen_of(event))
	if _selection.mode == SlabSelection.Mode.OBJECT:
		if hit == null:
			return Verdict.PASS
		_focus(hit, additive)
		return Verdict.STOP
	if hit == null:
		if not additive:
			_selection.clear_ids()
		return Verdict.STOP if _selection.solid != null else Verdict.PASS
	_focus(hit, false)
	var id: int = SlabPick.pick(hit, _selection.mode, camera, screen_of(event), _metrics.pick_radius())
	if id == 0:
		if not additive:
			_selection.clear_ids()
		return Verdict.STOP
	_selection.toggle_id(id, additive)
	return Verdict.STOP


func _focus(solid: Node3D, additive: bool) -> void:
	_host.focus_solid(solid, additive)
	adopt_host_selection()


func _touch_gizmo(node: Node3D, seen: Dictionary, next: Array[Node3D]) -> void:
	if node == null or not is_instance_valid(node) or seen.has(node):
		return
	seen[node] = true
	next.append(node)


static func screen_of(event: InputEventMouseButton) -> Vector2:
	return event.position
