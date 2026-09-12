@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabTopology := preload("res://addons/slab/slab_topology.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")
const SlabPlaneCut := preload("res://addons/slab/slab_plane_cut.gd")
const SlabLoopCut := preload("res://addons/slab/slab_loop_cut.gd")
const SlabArray := preload("res://addons/slab/slab_array.gd")
const SlabSnapAlign := preload("res://addons/slab/slab_snap_align.gd")
const SlabBevel := preload("res://addons/slab/slab_bevel.gd")
const SlabXform := preload("res://addons/slab/slab_element_xform.gd")

enum Verdict { PASS, STOP, CUSTOM }

const DRAG_THRESHOLD_PX := 6.0
const MIN_STEP := 0.0002
const MIN_BEVEL := 0.002

const EXTRUDE_LABEL := "Slab Extrude Faces"
const BEVEL_LABEL := "Slab Bevel Edges"


class Grab:
	enum Phase { IDLE, PRESSED, DRAGGING }
	enum Plan { NONE, MOVE_ALONG_NORMAL, EXTRUDE_ALONG_NORMAL, BEVEL_EDGES }

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
	var last_good := PackedByteArray()
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
var _plane: RefCounted
var _loop: RefCounted
var _array: RefCounted
var _snap_align: RefCounted
var _bevel: RefCounted
var _paint: RefCounted
var _gizmo_nodes: Array[Node3D] = []
var _grab: Grab = Grab.idle()


func _init(host: RefCounted) -> void:
	_host = host
	_selection = SlabSelection.new()
	_metrics = SlabMetrics.of(host)


func bind_actions(actions: RefCounted) -> void:
	_actions = actions
	_actions.plane_requested.connect(func() -> void:
		if _loop != null and _loop.active:
			_loop.cancel()
		_cancel_array()
		_cancel_snap_align()
		_cancel_bevel()
		_exit_paint()
	)
	_actions.loop_requested.connect(func() -> void:
		if _plane != null and _plane.active:
			_plane.cancel()
		_cancel_array()
		_cancel_snap_align()
		_cancel_bevel()
		_exit_paint()
	)
	_plane = SlabPlaneCut.new(_selection, _actions, _host)
	_loop = SlabLoopCut.new(_selection, _actions, _host)
	_array = SlabArray.new(_host)
	_array.preview_changed.connect(_on_array_preview)
	_array.reported.connect(func(message: String) -> void: _actions.reported.emit(message))
	_actions.array_requested.connect(_begin_array)
	_actions.array_settings_changed.connect(_refresh_array)
	_actions.array_apply_requested.connect(_confirm_array)
	_actions.array_cancel_requested.connect(_cancel_array)
	_selection.changed.connect(_array_selection_changed)
	_snap_align = SlabSnapAlign.new(_selection, _host)
	_snap_align.preview_changed.connect(_on_snap_align_preview)
	_snap_align.reported.connect(func(message: String) -> void: _actions.reported.emit(message))
	_actions.snap_vertex_requested.connect(_begin_vertex_snap)
	_actions.align_face_requested.connect(_begin_face_align)
	_actions.snap_align_settings_changed.connect(_refresh_snap_align)
	_actions.snap_align_cancel_requested.connect(_cancel_snap_align)
	_bevel = SlabBevel.new(_selection, _actions, _host)
	_actions.bevel_requested.connect(_begin_bevel)
	_actions.bevel_settings_changed.connect(_refresh_bevel)
	_actions.bevel_apply_requested.connect(_confirm_bevel)
	_actions.bevel_cancel_requested.connect(_cancel_bevel)
	_selection.changed.connect(_sync_bevel_state)


func bind_paint(paint: RefCounted) -> void:
	_paint = paint
	if _paint != null and _paint.has_signal("changed"):
		_paint.changed.connect(func() -> void:
			if _paint.active:
				_cancel_array()
				_cancel_snap_align()
				_cancel_bevel()
				if _plane != null and _plane.active:
					_plane.cancel()
				if _loop != null and _loop.active:
					_loop.cancel()
		)


static func after_gui_input(verdict: int) -> int:
	return verdict


func handle(camera: Camera3D, event: InputEvent) -> int:
	if _selection == null:
		return Verdict.PASS
	if _snap_align != null and _snap_align.active:
		return _snap_align.handle(camera, event)
	if _bevel != null and _bevel.active:
		var bevel_verdict: int = _bevel.handle(camera, event)
		_sync_bevel_state()
		return bevel_verdict
	if _array != null and _array.active:
		return _handle_array(event)
	if _plane != null and _plane.active:
		return _plane.handle(camera, event)
	if _loop != null and _loop.active:
		return _loop.handle(camera, event)
	if _paint != null and _paint.active:
		var verdict: int = _paint.handle_3d(camera, event, _host.scene_root() if _host != null else null)
		if verdict == Verdict.STOP:
			return verdict
		if event is InputEventKey:
			return Verdict.STOP
		return verdict
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
	if _plane != null and _plane.active:
		_plane.cancel()
	if _loop != null and _loop.active:
		_loop.cancel()
	_cancel_array()
	_cancel_snap_align()
	_cancel_bevel()
	if _grab.dragging():
		_cancel()
	_selection.set_objects(_host.selected_nodes())


func gizmo_targets() -> Array[Node3D]:
	_selection.drop_invalid()
	var seen: Dictionary = {}
	var current: Array[Node3D] = []
	for node in _selection.objects:
		_touch_gizmo(node, seen, current)
	_touch_gizmo(_selection.hover_solid, seen, current)
	_touch_gizmo(_selection.preview_solid, seen, current)
	_touch_gizmo(_selection.array_preview_solid, seen, current)
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


func _begin_array() -> void:
	if _plane != null and _plane.active:
		_plane.cancel()
	if _loop != null and _loop.active:
		_loop.cancel()
	_cancel_snap_align()
	_cancel_bevel()
	_exit_paint()
	_sync_array_settings()
	_actions.array_active = _array.begin(_selection.solid)
	_actions.array_state_changed.emit()


func _refresh_array() -> void:
	if _array == null or not _array.active:
		return
	_sync_array_settings()
	_array.refresh_preview()


func _confirm_array() -> void:
	if _array == null or not _array.active:
		return
	_array.confirm()
	_actions.array_active = false
	_actions.array_state_changed.emit()


func _cancel_array() -> void:
	if _array == null or not _array.active:
		return
	_array.cancel()
	_actions.array_active = false
	_actions.array_state_changed.emit()


func _handle_array(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_cancel_array()
			_actions.reported.emit("Array cancelled.")
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_confirm_array()
		return Verdict.STOP
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_array()
		_actions.reported.emit("Array cancelled.")
		return Verdict.STOP
	return Verdict.PASS


func _sync_array_settings() -> void:
	_array.mode = _actions.array_mode
	_array.count = _actions.array_count
	_array.linear_step = _actions.array_linear_step
	_array.radial_center = _actions.array_radial_center
	_array.radial_axis = _actions.array_radial_axis
	_array.radial_angle_degrees = _actions.array_radial_angle_degrees
	_array.rotate_radial_copies = _actions.array_rotate_copies


func _on_array_preview(transforms: Array) -> void:
	_selection.array_preview_solid = _selection.solid if _array != null and _array.active else null
	var typed: Array[Transform3D] = []
	typed.assign(transforms)
	_selection.array_preview_transforms = typed
	_selection.hover_changed.emit()


func _array_selection_changed() -> void:
	if _array != null and _array.active and (_selection.mode != SlabSelection.Mode.OBJECT or _selection.solid != _selection.array_preview_solid):
		_cancel_array()


func _exit_paint() -> void:
	if _paint != null and _paint.active:
		_paint.exit()


func _begin_vertex_snap() -> void:
	_cancel_bevel()
	_cancel_other_modals_for_snap()
	_actions.snap_align_active = _snap_align.begin_vertex_snap()
	_actions.snap_align_mode = SlabActions.SNAP_VERTEX if _actions.snap_align_active else SlabActions.SNAP_NONE
	_actions.snap_align_state_changed.emit()


func _begin_face_align() -> void:
	_cancel_bevel()
	_cancel_other_modals_for_snap()
	_snap_align.oppose_face_normals = _actions.align_oppose_normals
	_actions.snap_align_active = _snap_align.begin_face_align()
	_actions.snap_align_mode = SlabActions.SNAP_FACE if _actions.snap_align_active else SlabActions.SNAP_NONE
	_actions.snap_align_state_changed.emit()


func _cancel_other_modals_for_snap() -> void:
	if _plane != null and _plane.active:
		_plane.cancel()
	if _loop != null and _loop.active:
		_loop.cancel()
	_cancel_array()
	_exit_paint()


func _refresh_snap_align() -> void:
	if _snap_align == null or not _snap_align.active:
		return
	_snap_align.oppose_face_normals = _actions.align_oppose_normals
	_snap_align.refresh()


func _cancel_snap_align() -> void:
	if _snap_align == null or not _snap_align.active:
		return
	_snap_align.cancel()


func _on_snap_align_preview(preview: Dictionary) -> void:
	_selection.snap_align_preview = preview
	var next_active: bool = _snap_align != null and _snap_align.active
	var next_mode: int = _snap_align.mode if _snap_align != null else SlabActions.SNAP_NONE
	if next_active != _actions.snap_align_active or next_mode != _actions.snap_align_mode:
		_actions.snap_align_active = next_active
		_actions.snap_align_mode = next_mode
		_actions.snap_align_state_changed.emit()


func _begin_bevel() -> void:
	if _plane != null and _plane.active:
		_plane.cancel()
	if _loop != null and _loop.active:
		_loop.cancel()
	_cancel_array()
	_cancel_snap_align()
	_exit_paint()
	_bevel.amount = _actions.amount
	_bevel.segments = _actions.bevel_segments
	_bevel.begin()
	_actions.bevel_active = _bevel.active
	_actions.snap_align_state_changed.emit()


func _refresh_bevel() -> void:
	if _bevel == null or not _bevel.active:
		return
	_bevel.set_amount(_actions.amount)
	_bevel.set_segments(_actions.bevel_segments)


func _confirm_bevel() -> void:
	if _bevel != null and _bevel.active:
		_bevel.confirm()
	_actions.bevel_active = false
	_actions.snap_align_state_changed.emit()


func _cancel_bevel() -> void:
	if _bevel != null and _bevel.active:
		_bevel.cancel()
	if _actions != null and _actions.bevel_active:
		_actions.bevel_active = false
		_actions.snap_align_state_changed.emit()


func _sync_bevel_state() -> void:
	if _actions == null or _bevel == null:
		return
	var next_active: bool = _bevel.active
	if _actions.bevel_active != next_active:
		_actions.bevel_active = next_active
		_actions.snap_align_state_changed.emit()


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
		return Verdict.CUSTOM
	if hit == null:
		if not additive:
			_selection.clear_ids()
		return Verdict.CUSTOM if _selection.solid != null else Verdict.PASS
	_focus(hit, false)
	var id: int = SlabPick.pick(hit, _selection.mode, camera, screen, _metrics.pick_radius())
	if id == 0:
		if not additive:
			_selection.clear_ids()
		return Verdict.CUSTOM
	if event.double_click and _selection.mode == SlabSelection.Mode.EDGE:
		_select_loop(hit, id, additive)
		return Verdict.STOP
	_selection.toggle_id(id, additive)
	if event.shift_pressed and _selection.mode in [SlabSelection.Mode.FACE, SlabSelection.Mode.EDGE]:
		_grab = _armed(camera, hit, id, screen)
		return Verdict.STOP
	return Verdict.CUSTOM


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
	if grab.mode == SlabSelection.Mode.EDGE:
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
	if g.plan == Grab.Plan.NONE:
		_grab = Grab.idle()
		return false
	g.label = EXTRUDE_LABEL if g.plan == Grab.Plan.EXTRUDE_ALONG_NORMAL else BEVEL_LABEL
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
	if g.plan == Grab.Plan.BEVEL_EDGES:
		g.axis = _bevel_axis(g.solid, g.pressed_id)
		if g.axis == Vector3.ZERO:
			_grab = Grab.idle()
			return false
	g.vertices = SlabXform.vertices(g.solid, g.mode, g.ids)
	if g.vertices.is_empty():
		_grab = Grab.idle()
		return false
	g.anchor_vertex = g.vertices[0]
	g.anchor_origin = g.solid.vertex_position(g.anchor_vertex)
	g.phase = Grab.Phase.DRAGGING
	return true


func _drag_to(camera: Camera3D, screen: Vector2) -> void:
	if _grab.plan == Grab.Plan.BEVEL_EDGES:
		_bevel_to(camera, screen)
		return
	var g := _grab
	var travel: float = _axis_travel(camera, screen, g.anchor, g.axis) - _axis_travel(camera, g.press_screen, g.anchor, g.axis)
	var wanted_world: Vector3 = g.axis * travel
	var wanted_local: Vector3 = g.solid.to_local(g.anchor + wanted_world) - g.solid.to_local(g.anchor)
	var applied_local: Vector3 = g.solid.vertex_position(g.anchor_vertex) - g.anchor_origin
	var step: Vector3 = wanted_local - applied_local
	if step.length() < MIN_STEP:
		return
	g.solid.move_vertices(g.vertices, step)


func _bevel_to(camera: Camera3D, screen: Vector2) -> void:
	var g := _grab
	var travel: float = absf(
		_axis_travel(camera, screen, g.anchor, g.axis) - _axis_travel(camera, g.press_screen, g.anchor, g.axis)
	)
	var wanted_local: Vector3 = g.solid.to_local(g.anchor + g.axis * travel) - g.solid.to_local(g.anchor)
	var amount: float = wanted_local.length()
	g.solid.set("data", g.before)
	if amount < MIN_BEVEL:
		return
	var err: int = g.solid.bevel_edges(g.ids, amount)
	if err != OK:
		if not g.last_good.is_empty():
			g.solid.set("data", g.last_good)
		return
	g.last_good = g.solid.get("data")


func _finish() -> void:
	var g := _grab
	_grab = Grab.idle()
	if not is_instance_valid(g.solid):
		return
	var after: PackedByteArray = g.solid.get("data")
	if g.plan == Grab.Plan.BEVEL_EDGES and after != g.before:
		_selection.set_ids(PackedInt64Array())
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
	if mode == SlabSelection.Mode.FACE and shift:
		return Grab.Plan.EXTRUDE_ALONG_NORMAL
	if mode == SlabSelection.Mode.EDGE and shift:
		return Grab.Plan.BEVEL_EDGES
	return Grab.Plan.NONE


static func _bevel_axis(solid: Node3D, edge: int) -> Vector3:
	var faces: PackedInt64Array = solid.edge_faces(edge)
	if faces.size() < 2:
		return Vector3.ZERO
	var axis: Vector3 = _world_normal(solid, faces[0]) + _world_normal(solid, faces[1])
	if axis.length_squared() < 0.0001:
		return _world_normal(solid, faces[0])
	return axis.normalized()


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


func _touch_gizmo(node: Variant, seen: Dictionary, next: Array[Node3D]) -> void:
	# Typed Node3D args throw on a previously-freed Object before is_instance_valid runs.
	if node == null or not is_instance_valid(node) or not (node is Node3D):
		return
	var solid: Node3D = node
	if seen.has(solid):
		return
	seen[solid] = true
	next.append(solid)


static func screen_of(event: InputEventMouseButton) -> Vector2:
	return event.position
