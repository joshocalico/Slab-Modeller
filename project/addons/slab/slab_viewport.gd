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
const SlabXform := preload("res://addons/slab/slab_element_xform.gd")
const SlabSelectionFrame := preload("res://addons/slab/slab_selection_frame.gd")
const SlabCreatePlacement := preload("res://addons/slab/slab_create_placement.gd")

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
var _paint: RefCounted
var _create: RefCounted
var _gizmo_nodes: Array[Node3D] = []
var _grab: Grab = Grab.idle()
var _pick_candidates: Array[Dictionary] = []
var _candidate_index := 0
var _candidate_screen := Vector2(INF, INF)
var _candidate_camera: Camera3D
var _candidate_mode := -1
var _operation := preload("res://addons/slab/slab_operation_handles.gd").new()
var _operation_dragging := false
var _operation_press := Vector2.ZERO
var _operation_start := 0.0
var _pending_native_press := false
var _pending_native_dragged := false
var _pending_native_screen := Vector2.ZERO
var _pending_native_candidate: Dictionary = {}


func _init(host: RefCounted) -> void:
	_host = host
	_selection = SlabSelection.new()
	_selection.settings_changed.connect(_clear_candidates)
	_selection.mode_requested.connect(_on_mode_requested)
	_metrics = SlabMetrics.of(host)


func bind_actions(actions: RefCounted) -> void:
	_actions = actions
	_create = SlabCreatePlacement.new(_host, _actions)
	_create.reported.connect(func(message: String) -> void: _actions.reported.emit(message))
	_actions.create_placement_requested.connect(_begin_create)
	_actions.create_settings_changed.connect(_create_settings_changed)
	_actions.object_order_changed.connect(_host.replace_selection)
	_actions.operation_requested.connect(_begin_operation)
	_actions.operation_amount_changed.connect(_change_operation_amount)
	_actions.operation_segments_changed.connect(_change_operation_segments)
	_actions.operation_apply_requested.connect(_confirm_operation)
	_actions.operation_cancel_requested.connect(_cancel_operation)
	_selection.changed.connect(func() -> void: _cancel_operation_with_reason("exit"))
	_actions.plane_requested.connect(func() -> void:
		_cancel_create()
		if _loop != null and _loop.active:
			_loop.cancel()
		_cancel_array()
		_cancel_snap_align()
		_cancel_operation_with_reason("superseded")
		_exit_paint()
	)
	_actions.loop_requested.connect(func() -> void:
		_cancel_create()
		if _plane != null and _plane.active:
			_plane.cancel()
		_cancel_array()
		_cancel_snap_align()
		_cancel_operation_with_reason("superseded")
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



func bind_paint(paint: RefCounted) -> void:
	_paint = paint
	if _paint != null and _paint.has_signal("changed"):
		_paint.changed.connect(func() -> void:
			if _paint.active:
				_cancel_create()
				_cancel_array()
				_cancel_snap_align()
				_cancel_operation_with_reason("exit")
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
	if _create != null and _create.active():
		return Verdict.STOP if _create.handle(camera, event) else Verdict.PASS
	if _operation.active:
		return _handle_operation(camera, event)
	if _snap_align != null and _snap_align.active:
		return _snap_align.handle(camera, event)
	if _array != null and _array.active:
		return _handle_array(event)
	if _plane != null and _plane.active:
		return _plane.handle(camera, event)
	if _loop != null and _loop.active:
		return _loop.handle(camera, event)
	if _paint != null and _paint.active:
		if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.meta_pressed and not event.alt_pressed:
			var mode := SlabModeStrip.mode_for_keycode(event.keycode)
			if mode != -1:
				_selection.request_mode(mode)
				return Verdict.STOP
		var verdict: int = _paint.handle_3d(camera, event, _host.scene_root() if _host != null else null)
		if verdict == Verdict.STOP:
			return verdict
		if event is InputEventKey:
			if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
				return Verdict.PASS
			if is_native_view_navigation_key(event.keycode):
				return Verdict.PASS
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


static func is_native_view_navigation_key(keycode: int) -> bool:
	return keycode == KEY_F or keycode in [
		KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4,
		KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9,
	]


func adopt_host_selection() -> void:
	_cancel_create()
	if _plane != null and _plane.active:
		_plane.cancel()
	if _loop != null and _loop.active:
		_loop.cancel()
	_cancel_array()
	_cancel_snap_align()
	_cancel_operation_with_reason("exit")
	if _grab.dragging():
		_cancel()
	_selection.set_editor_objects(_host.selected_nodes())


func _on_mode_requested() -> void:
	_cancel_create()
	if _plane != null and _plane.active:
		_plane.cancel()
	if _loop != null and _loop.active:
		_loop.cancel()
	_cancel_array()
	_cancel_snap_align()
	_cancel_operation_with_reason("exit")
	if _grab.active():
		_cancel()


func _begin_create(row: Dictionary, plan: Dictionary) -> void:
	if _plane != null and _plane.active: _plane.cancel()
	if _loop != null and _loop.active: _loop.cancel()
	_cancel_array()
	_cancel_snap_align()
	_cancel_operation_with_reason("superseded")
	_exit_paint()
	_create.begin(row, plan)


func _cancel_create() -> void:
	if _create != null and _create.active():
		_create.cancel(false)


func _create_settings_changed() -> void:
	if _create != null and _create.active():
		_create.cancel(false)
		_actions.reported.emit("Placement cancelled because the shape settings changed. Click Create again.")


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


func native_gizmo_pending() -> bool:
	return _pending_native_press


func cancel_create_preview() -> void:
	_cancel_create()


func metrics() -> RefCounted:
	return _metrics


func _begin_array() -> void:
	_cancel_create()
	if _plane != null and _plane.active:
		_plane.cancel()
	if _loop != null and _loop.active:
		_loop.cancel()
	_cancel_snap_align()
	_cancel_operation_with_reason("superseded")
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
	_cancel_create()
	_cancel_operation_with_reason("superseded")
	_cancel_other_modals_for_snap()
	_actions.snap_align_active = _snap_align.begin_vertex_snap()
	_actions.snap_align_mode = SlabActions.SNAP_VERTEX if _actions.snap_align_active else SlabActions.SNAP_NONE
	_actions.snap_align_state_changed.emit()


func _begin_face_align() -> void:
	_cancel_create()
	_cancel_operation_with_reason("superseded")
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


func _on_motion(camera: Camera3D, event: InputEventMouseMotion) -> int:
	if _pending_native_press:
		if event.position.distance_to(_pending_native_screen) >= _metrics.px(DRAG_THRESHOLD_PX):
			_pending_native_dragged = true
		return Verdict.PASS
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
	_pending_native_press = false
	_pending_native_dragged = false
	_pending_native_candidate.clear()
	if _grab.active():
		_on_release()
	var additive: bool = event.shift_pressed or event.ctrl_pressed or event.meta_pressed
	var screen: Vector2 = screen_of(event)
	var candidate := _candidate_at(camera, screen)
	var hit: Node3D = candidate.get("solid")
	if _selection.mode == SlabSelection.Mode.OBJECT:
		hit = SlabPick.pick_solid(_host.scene_root(), camera, screen)
		if hit == null:
			return Verdict.PASS
		_focus(hit, additive)
		return Verdict.CUSTOM
	if not additive and not event.double_click and not _selection.ids.is_empty():
		# Native gizmo handles can cover otherwise pickable geometry. Resolve a
		# plain click on release; if it becomes a drag, keep the current element
		# set and leave the complete gesture to Godot.
		_pending_native_press = true
		_pending_native_screen = screen
		_pending_native_candidate = candidate
		var native := _near_native_gizmo(camera, screen)
		return Verdict.PASS if native else Verdict.CUSTOM
	if hit == null:
		if not additive:
			_selection.clear_ids()
		return Verdict.CUSTOM if _selection.solid != null else Verdict.PASS
	_focus(hit, false)
	var id: int = int(candidate.get("id", 0))
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


func _near_native_gizmo(camera: Camera3D, screen: Vector2) -> bool:
	var frame := SlabSelectionFrame.from_selection(_selection)
	if not frame.get("valid", false):
		return false
	var world: Transform3D = frame["world"]
	var centre := camera.unproject_position(world.origin)
	var offset := screen - centre
	var scale: float = _metrics.px(1.0)
	var radius := offset.length()
	if radius <= 13.0 * scale or (radius >= 52.0 * scale and radius <= 98.0 * scale):
		return true
	var reach := maxf(camera.global_position.distance_to(world.origin) * 0.2, 0.25)
	for axis in [world.basis.x, world.basis.y, world.basis.z]:
		var toward := camera.unproject_position(world.origin + axis * reach) - centre
		if toward.is_zero_approx():
			continue
		var direction := toward.normalized()
		var along := offset.dot(direction)
		var across := absf(offset.cross(direction))
		if along >= 7.0 * scale and along <= 112.0 * scale and across <= 9.0 * scale:
			return true
	return false


func _on_release() -> int:
	if _pending_native_press:
		var dragged := _pending_native_dragged
		var candidate := _pending_native_candidate
		_pending_native_press = false
		_pending_native_dragged = false
		_pending_native_candidate = {}
		if not dragged:
			var hit: Node3D = candidate.get("solid")
			var id := int(candidate.get("id", 0))
			if hit == null or id == 0:
				_selection.clear_ids()
			else:
				_focus(hit, false)
				_selection.toggle_id(id, false)
		return Verdict.PASS if dragged else Verdict.CUSTOM
	if _grab.phase == Grab.Phase.IDLE:
		return Verdict.PASS
	if _grab.phase == Grab.Phase.PRESSED:
		_grab = Grab.idle()
		return Verdict.STOP
	_finish()
	return Verdict.STOP


func _on_key(event: InputEventKey) -> int:
	if _pending_native_press and event.keycode == KEY_ESCAPE:
		# Let Godot cancel its transform and keep release from selecting a face.
		_pending_native_dragged = true
		return Verdict.PASS
	if _grab.active():
		if event.keycode == KEY_ESCAPE:
			return _cancel()
		return Verdict.STOP
	if event.keycode == KEY_TAB and not event.ctrl_pressed and not event.meta_pressed and not event.alt_pressed and _candidate_mode == _selection.mode:
		if _pick_candidates.size() > 1:
			_candidate_index = posmod(_candidate_index + (-1 if event.shift_pressed else 1), _pick_candidates.size())
			var candidate: Dictionary = _pick_candidates[_candidate_index]
			_selection.set_hover(candidate.get("solid"), int(candidate.get("id", 0)))
			if _actions != null:
				_actions.reported.emit("Candidate %d / %d. Click to select; Tab cycles, Shift-Tab reverses." % [_candidate_index + 1, _pick_candidates.size()])
			return Verdict.STOP
	if event.ctrl_pressed or event.meta_pressed:
		return Verdict.PASS
	if event.keycode == KEY_ESCAPE:
		_selection.mode = SlabSelection.Mode.OBJECT
		return Verdict.STOP
	var mode: int = SlabModeStrip.mode_for_keycode(event.keycode)
	if mode != -1:
		_selection.request_mode(mode)
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
	return (solid.global_transform.basis.inverse().transposed() * solid.face_normal(face)).normalized()


static func _face_anchor(camera: Camera3D, screen: Vector2, solid: Node3D, face: int, world_normal: Vector3) -> Vector3:
	var centroid: Vector3 = solid.to_global(solid.face_centroid(face))
	var hit: Variant = _plane_point(camera, screen, centroid, world_normal)
	return hit if hit != null else centroid


func _on_hover(camera: Camera3D, screen: Vector2) -> void:
	if _selection.mode == SlabSelection.Mode.OBJECT:
		_selection.set_hover(SlabPick.pick_solid(_host.scene_root(), camera, screen), 0)
		return
	var candidate := _candidate_at(camera, screen)
	_selection.set_hover(candidate.get("solid"), int(candidate.get("id", 0)))


func _clear_candidates() -> void:
	_pick_candidates.clear()
	_candidate_index = 0
	_candidate_screen = Vector2(INF, INF)


func _candidate_at(camera: Camera3D, screen: Vector2) -> Dictionary:
	var next: Array[Dictionary] = SlabPick.scene_candidates(_host.scene_root(), _selection.mode,
		camera, screen, _metrics.pick_radius(), not _selection.xray)
	var same: bool = camera == _candidate_camera and _candidate_mode == _selection.mode and screen.distance_to(_candidate_screen) <= 2.0 and next.size() == _pick_candidates.size()
	if same:
		for i in next.size():
			if next[i].get("solid") != _pick_candidates[i].get("solid") or next[i].get("id") != _pick_candidates[i].get("id"):
				same = false
				break
	if not same:
		_candidate_index = 0
	_pick_candidates = next
	_candidate_camera = camera
	_candidate_mode = _selection.mode
	_candidate_screen = screen
	return _pick_candidates[_candidate_index] if not _pick_candidates.is_empty() else {}


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


func _begin_operation(kind: int) -> void:
	_cancel_create()
	_cancel_operation_with_reason("superseded")
	if _selection.solid == null or _selection.ids.is_empty() or _selection.mode != (SlabSelection.Mode.EDGE if kind == 2 else SlabSelection.Mode.FACE):
		_actions.reported.emit("Bevel needs one or more selected edges." if kind == 2 else "%s needs one or more selected faces." % ["Extrude" if kind == 0 else "Inset"])
		return
	_cancel_array()
	_cancel_snap_align()
	_exit_paint()
	if _plane != null and _plane.active: _plane.cancel()
	if _loop != null and _loop.active: _loop.cancel()
	if _operation.begin(kind, _selection.solid, _selection.ids, _actions.operation_amount_for(kind), _actions.bevel_segments):
		_publish_operation(true)
	else:
		_actions.reported.emit("Bevel could not place a handle on these edges. Choose live edges joined to faces." if kind == 2 else "%s needs one face or a connected face region with a shared direction." % ["Extrude" if kind == 0 else "Inset"])


func _publish_operation(started: bool = false) -> void:
	if not _operation.active: return
	var shape: Dictionary = _operation.geometry()
	shape["solid"] = _operation.solid
	shape["preview_lines"] = _operation.preview_lines
	shape["error"] = _operation.error
	_selection.operation_preview = shape
	_actions.operation_active = true
	_actions.operation_amount = _operation.amount
	_actions.remember_operation_amount(_operation.kind, _operation.amount)
	var apply_enabled: bool = _operation.error == OK
	_actions._op_session_apply_enabled = apply_enabled
	if started:
		_actions.notify_op_session_start(_operation.kind)
	else:
		_actions.notify_op_session_update(apply_enabled)
	_actions.operation_state_changed.emit()
	_selection.hover_changed.emit()
	var action_id := "extrude_faces" if _operation.kind == 0 else ("bevel_edges" if _operation.kind == 2 else "")
	_actions.reported.emit(shape["label"] + (". Drag the handle or enter an amount; Apply confirms, Escape cancels." if _operation.error == OK else ". " + _actions.describe_error(_operation.error, action_id)))


func _change_operation_segments(value: int) -> void:
	if not _operation.active: return
	_actions.bevel_segments = clampi(value, 1, 16)
	_operation.segments = _actions.bevel_segments
	_operation.refresh()
	_publish_operation()


func _change_operation_amount(value: float) -> void:
	if not _operation.active: return
	_operation.set_amount(value)
	_publish_operation()


func _handle_operation(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE: _cancel_operation()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER: _confirm_operation()
		else: return Verdict.PASS
		return Verdict.STOP
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_operation()
			return Verdict.STOP
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _operation.hit_test(camera, event.position, _metrics.pick_radius()):
				_operation_dragging = true
				_operation_press = event.position
				_operation_start = _operation.amount
				return Verdict.STOP
			elif not event.pressed:
				var dragged := _operation_dragging
				_operation_dragging = false
				return Verdict.STOP if dragged else Verdict.PASS
			return Verdict.PASS
	if event is InputEventMouseMotion and _operation_dragging:
		_change_operation_amount(_operation_start + _operation.drag_value(camera, _operation_press, event.position))
		return Verdict.STOP
	return Verdict.PASS


func _cancel_operation() -> void:
	_cancel_operation_with_reason("cancel")


func _cancel_operation_with_reason(reason: String) -> void:
	var was_active: bool = _operation.active or (_actions != null and _actions.op_session_active())
	_operation.cancel()
	_operation_dragging = false
	_selection.operation_preview = {}
	if _actions != null:
		if was_active:
			_actions.notify_op_session_end(reason)
		_actions.operation_active = false
		_actions.operation_state_changed.emit()
		if was_active: _actions.status_reset_requested.emit()
	_selection.hover_changed.emit()


func _confirm_operation() -> void:
	var before_ids: PackedInt64Array = _selection.ids.duplicate()
	var operation_name: String = ["Extrude", "Inset", "Bevel"][_operation.kind]
	var result: Dictionary = _operation.confirm()
	if result.is_empty():
		if not _operation.active:
			_cancel_operation_with_reason("exit")
			_actions.reported.emit("Preview cancelled because the solid changed. Start the tool again.")
		return
	_cancel_operation_with_reason("apply")
	var after_ids: PackedInt64Array = result["result_ids"]
	if after_ids.is_empty(): after_ids = before_ids
	var undo: Object = _host.undo()
	if undo != null:
		undo.create_action("Slab " + operation_name, UndoRedo.MERGE_DISABLE, result["solid"])
		undo.add_do_method(self, "_restore_operation", result["solid"], result["after"], after_ids)
		undo.add_undo_method(self, "_restore_operation", result["solid"], result["before"], before_ids)
		undo.commit_action(false)
	_selection.set_ids(after_ids)
	_actions.reported.emit(operation_name + " applied. Undo restores the previous solid.")


func _restore_operation(solid: Node3D, data: PackedByteArray, ids: PackedInt64Array) -> void:
	solid.set("data", data)
	_selection.set_ids(ids)
