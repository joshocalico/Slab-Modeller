@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabTopology := preload("res://addons/slab/slab_topology.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")

enum Verdict { PASS, STOP }

const DRAG_THRESHOLD_PX := 6.0
const MIN_STEP := 0.0002

const LABELS: Dictionary = {
	SlabSelection.Mode.VERTEX: "Slab Move Vertices",
	SlabSelection.Mode.EDGE: "Slab Move Edges",
	SlabSelection.Mode.FACE: "Slab Move Faces",
}
const EXTRUDE_LABEL := "Slab Extrude Faces"


class Grab:
	enum Phase { IDLE, PRESSED, DRAGGING }
	enum Plan { NONE, MOVE_IN_CAMERA_PLANE, MOVE_ALONG_NORMAL, EXTRUDE_ALONG_NORMAL }

	var phase: int = Phase.IDLE
	var solid: Node3D = null
	var mode: int = SlabSelection.Mode.OBJECT
	var pressed_id: int = 0
	var press_screen := Vector2.ZERO
	var anchor := Vector3.ZERO
	var axis := Vector3.ZERO
	var plan: int = Plan.NONE
	var ids := PackedInt64Array()
	var vertices := PackedInt64Array()
	var anchor_vertex: int = 0
	var anchor_origin := Vector3.ZERO
	var before := PackedByteArray()
	var label := ""

	static func idle() -> Grab:
		return Grab.new()

	func active() -> bool:
		return phase != Phase.IDLE

	func dragging() -> bool:
		return phase == Phase.DRAGGING


var _host: RefCounted
var _metrics: RefCounted
var _selection: RefCounted
var _actions: RefCounted
var _gizmo_nodes: Array[Node3D] = []
var _grab: Grab = Grab.idle()


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
		return _on_motion(camera, event)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			return _on_press(camera, event) if event.pressed else _on_release()
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and _grab.dragging():
			return _cancel()
		return Verdict.STOP if _grab.active() else Verdict.PASS
	if event is InputEventKey and event.pressed and not event.echo:
		return _on_key(event)
	return Verdict.STOP if _grab.active() else Verdict.PASS


func adopt_host_selection() -> void:
	if _grab.dragging():
		_cancel()
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


func _on_motion(camera: Camera3D, event: InputEventMouseMotion) -> int:
	if not _grab.active():
		_on_hover(camera, event.position)
		return Verdict.PASS
	if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return _on_release()
	if _grab.phase == Grab.Phase.PRESSED:
		if event.position.distance_to(_grab.press_screen) < _metrics.px(DRAG_THRESHOLD_PX):
			return Verdict.STOP
		if not _start_drag(camera, event):
			return Verdict.STOP
	_drag_to(camera, event.position)
	return Verdict.STOP


func _on_press(camera: Camera3D, event: InputEventMouseButton) -> int:
	if _grab.active():
		_on_release()
	var additive: bool = event.shift_pressed or event.ctrl_pressed or event.meta_pressed
	var screen: Vector2 = screen_of(event)
	var hit: Node3D = SlabPick.pick_solid(_host.scene_root(), camera, screen)
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
	var id: int = SlabPick.pick(hit, _selection.mode, camera, screen, _metrics.pick_radius())
	if id == 0:
		if not additive:
			_selection.clear_ids()
		return Verdict.STOP
	if event.double_click and _selection.mode == SlabSelection.Mode.EDGE:
		_select_loop(hit, id, additive)
		return Verdict.STOP
	_selection.toggle_id(id, additive)
	_grab = _armed(camera, hit, id, screen)
	return Verdict.STOP


func _on_release() -> int:
	if _grab.phase == Grab.Phase.IDLE:
		return Verdict.PASS
	if _grab.phase == Grab.Phase.PRESSED:
		_grab = Grab.idle()
		return Verdict.STOP
	_finish()
	return Verdict.STOP


func _on_key(event: InputEventKey) -> int:
	if _grab.active():
		if event.keycode == KEY_ESCAPE:
			return _cancel()
		return Verdict.STOP
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


func _armed(camera: Camera3D, solid: Node3D, id: int, screen: Vector2) -> Grab:
	var grab := Grab.new()
	grab.phase = Grab.Phase.PRESSED
	grab.solid = solid
	grab.mode = _selection.mode
	grab.pressed_id = id
	grab.press_screen = screen
	if grab.mode == SlabSelection.Mode.VERTEX:
		grab.anchor = solid.to_global(solid.vertex_position(id))
		grab.axis = -camera.global_transform.basis.z
	elif grab.mode == SlabSelection.Mode.EDGE:
		var ends: PackedVector3Array = solid.edge_endpoints(id)
		grab.anchor = solid.to_global((ends[0] + ends[1]) * 0.5)
		grab.axis = -camera.global_transform.basis.z
	else:
		grab.axis = _world_normal(solid, id)
		grab.anchor = _face_anchor(camera, screen, solid, id, grab.axis)
	return grab


func _start_drag(camera: Camera3D, event: InputEventMouseMotion) -> bool:
	var g := _grab
	if not is_instance_valid(g.solid):
		_grab = Grab.idle()
		return false
	g.plan = _plan_for(g.mode, event.shift_pressed)
	g.label = EXTRUDE_LABEL if g.plan == Grab.Plan.EXTRUDE_ALONG_NORMAL else String(LABELS[g.mode])
	g.ids = PackedInt64Array(_selection.ids)
	if not g.ids.has(g.pressed_id):
		g.ids.append(g.pressed_id)
	_selection.set_ids(g.ids)
	g.before = g.solid.get("data")
	if g.plan == Grab.Plan.EXTRUDE_ALONG_NORMAL:
		var err: int = g.solid.extrude_faces(g.ids, 0.0)
		if err != OK:
			_grab = Grab.idle()
			return false
		g.plan = Grab.Plan.MOVE_ALONG_NORMAL
	g.vertices = _gather_vertices(g.solid, g.mode, g.ids)
	if g.vertices.is_empty():
		_grab = Grab.idle()
		return false
	g.anchor_vertex = g.vertices[0]
	g.anchor_origin = g.solid.vertex_position(g.anchor_vertex)
	g.phase = Grab.Phase.DRAGGING
	return true


func _drag_to(camera: Camera3D, screen: Vector2) -> void:
	var g := _grab
	var wanted_world := Vector3.ZERO
	if g.plan == Grab.Plan.MOVE_IN_CAMERA_PLANE:
		var now: Variant = _plane_point(camera, screen, g.anchor, g.axis)
		var was: Variant = _plane_point(camera, g.press_screen, g.anchor, g.axis)
		if now == null or was == null:
			return
		wanted_world = now - was
	else:
		var travel: float = _axis_travel(camera, screen, g.anchor, g.axis) - _axis_travel(camera, g.press_screen, g.anchor, g.axis)
		wanted_world = g.axis * travel
	var wanted_local: Vector3 = g.solid.to_local(g.anchor + wanted_world) - g.solid.to_local(g.anchor)
	var applied_local: Vector3 = g.solid.vertex_position(g.anchor_vertex) - g.anchor_origin
	var step: Vector3 = wanted_local - applied_local
	if step.length() < MIN_STEP:
		return
	g.solid.move_vertices(g.vertices, step)


func _finish() -> void:
	var g := _grab
	_grab = Grab.idle()
	if not is_instance_valid(g.solid):
		return
	var after: PackedByteArray = g.solid.get("data")
	if after == g.before:
		return
	var undo: Object = _host.undo()
	if undo == null:
		return
	_record_undo(undo, g.solid, g.label, g.before, after)


func _cancel() -> int:
	var g := _grab
	_grab = Grab.idle()
	if g.phase == Grab.Phase.DRAGGING and is_instance_valid(g.solid):
		g.solid.set("data", g.before)
	return Verdict.STOP


func _record_undo(undo: Object, solid: Node3D, label: String, before: PackedByteArray, after: PackedByteArray) -> void:
	undo.create_action(label, UndoRedo.MERGE_DISABLE, solid)
	undo.add_do_property(solid, "data", after)
	undo.add_undo_property(solid, "data", before)
	undo.commit_action(false)


func _select_loop(solid: Node3D, edge: int, additive: bool) -> void:
	var loop: PackedInt64Array = SlabTopology.edge_loop(solid, edge)
	if not additive:
		_selection.set_ids(loop)
		return
	var next := PackedInt64Array(_selection.ids)
	for id in loop:
		if not next.has(id):
			next.append(id)
	_selection.set_ids(next)


static func _plan_for(mode: int, shift: bool) -> int:
	if mode == SlabSelection.Mode.FACE:
		return Grab.Plan.EXTRUDE_ALONG_NORMAL if shift else Grab.Plan.MOVE_ALONG_NORMAL
	return Grab.Plan.MOVE_IN_CAMERA_PLANE


static func _gather_vertices(solid: Node3D, mode: int, ids: PackedInt64Array) -> PackedInt64Array:
	if mode == SlabSelection.Mode.VERTEX:
		return ids
	var seen: Dictionary = {}
	var out := PackedInt64Array()
	for id in ids:
		var verts: PackedInt64Array = solid.face_vertices(id) if mode == SlabSelection.Mode.FACE else solid.edge_vertices(id)
		for vertex in verts:
			if seen.has(vertex):
				continue
			seen[vertex] = true
			out.append(vertex)
	return out


static func _plane_point(camera: Camera3D, screen: Vector2, anchor: Vector3, normal: Vector3) -> Variant:
	return Plane(normal, anchor).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))


static func _axis_travel(camera: Camera3D, screen: Vector2, anchor: Vector3, axis: Vector3) -> float:
	var u: Vector3 = camera.project_ray_normal(screen)
	var v: Vector3 = axis
	var w0: Vector3 = camera.project_ray_origin(screen) - anchor
	var a: float = u.dot(u)
	var b: float = u.dot(v)
	var c: float = v.dot(v)
	var d: float = u.dot(w0)
	var e: float = v.dot(w0)
	var denom: float = a * c - b * b
	if absf(denom) < 0.0000001:
		return 0.0
	return (a * e - b * d) / denom


static func _world_normal(solid: Node3D, face: int) -> Vector3:
	return (solid.global_transform.basis * solid.face_normal(face)).normalized()


static func _face_anchor(camera: Camera3D, screen: Vector2, solid: Node3D, face: int, world_normal: Vector3) -> Vector3:
	var centroid: Vector3 = solid.to_global(solid.face_centroid(face))
	var hit: Variant = _plane_point(camera, screen, centroid, world_normal)
	return hit if hit != null else centroid


func _on_hover(camera: Camera3D, screen: Vector2) -> void:
	var hit: Node3D = SlabPick.pick_solid(_host.scene_root(), camera, screen)
	if hit == null or _selection.mode == SlabSelection.Mode.OBJECT:
		_selection.set_hover(hit, 0)
		return
	_selection.set_hover(hit, SlabPick.pick(hit, _selection.mode, camera, screen, _metrics.pick_radius()))


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
