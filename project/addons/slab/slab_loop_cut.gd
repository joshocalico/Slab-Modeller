@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")

var active := false
var sliding := false
var candidate_locked := false
var solid: Node3D
var edge: int = 0
var lines := PackedVector3Array()
var _selection: RefCounted
var _actions: RefCounted
var _host: RefCounted
var _before := PackedByteArray()
var _typed := ""
var _error: int = OK

func _init(selection: RefCounted, actions: RefCounted, host: RefCounted) -> void:
	_selection = selection
	_actions = actions
	_host = host
	_actions.loop_requested.connect(begin)
	_actions.loop_settings_changed.connect(refresh)
	_actions.loop_apply_requested.connect(confirm)
	_actions.loop_cancel_requested.connect(cancel_from_ui)
	_selection.changed.connect(_selection_changed)

func begin() -> void:
	cancel()
	active = true
	_publish_state()
	if _selection.solid != null and not _selection.ids.is_empty():
		solid = _selection.solid
		edge = _selection.ids[0]
		_before = solid.get("data")
		candidate_locked = true
		refresh()
		if _error != OK or lines.is_empty():
			candidate_locked = false
	else:
		_report("Loop Cut: hover an edge. Click to slide; click again or Enter to apply. Esc cancels.")

func positions() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var count: int = _actions.loop_count
	# Position is the centre of an evenly spaced group. The group slides as one.
	var half_span: float = float(count - 1) / float(count + 1) * 0.5
	var centre: float = clampf(_actions.loop_position, half_span + 0.001, 0.999 - half_span)
	_actions.loop_position = centre
	for i in range(count):
		result.append(centre + (float(i + 1) / float(count + 1) - 0.5))
	return result

func refresh() -> void:
	if not active:
		return
	lines.clear()
	if not is_instance_valid(solid) or edge == 0:
		_selection.preview_lines = PackedVector3Array()
		_selection.preview_solid = null
		_selection.hover_changed.emit()
		_publish_state()
		_report("Loop Cut: hover an edge to preview a cut. Esc cancels.")
		return
	if solid.get("data") != _before:
		cancel()
		_report("Loop Cut cancelled: the solid changed. Start again on the new geometry.")
		return
	var preview: Dictionary = solid.call("preview_loop_cuts", edge, positions())
	_error = int(preview.get("error", SlabActions.ERR_INVALID_SELECTION))
	lines = preview.get("segments", PackedVector3Array())
	_actions.loop_values_updated.emit()
	_selection.preview_solid = solid
	_selection.preview_lines = lines
	_selection.hover_changed.emit()
	_publish_state()
	if _error != OK:
		_report("Loop Cut: %s" % SlabActions.describe_error(_error, "insert_loop"))
	else:
		_report("Loop Cut: %d cuts, centre %.2f%%. Wheel changes count. Type a percentage. %s Esc cancels." % [_actions.loop_count, _actions.loop_position * 100.0, "Click or Enter applies." if sliding else "Click to slide."])

func handle(camera: Camera3D, event: InputEvent) -> int:
	if not active:
		return 0
	if not is_instance_valid(camera):
		return 1
	if _selection.mode != SlabSelection.Mode.EDGE:
		cancel()
		return 1
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel()
			_report("Loop Cut cancelled.")
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			confirm()
		elif event.keycode == KEY_BACKSPACE:
			_typed = _typed.left(-1)
			_apply_typed()
		elif event.unicode >= 48 and event.unicode <= 57 or event.unicode == 46:
			_typed += char(event.unicode)
			_apply_typed()
		return 1
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_actions.loop_count = clampi(_actions.loop_count + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 1, 32)
			refresh()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if sliding:
				confirm()
			elif is_instance_valid(solid) and not lines.is_empty():
				candidate_locked = true
				sliding = true
				refresh()
		return 1
	if event is InputEventMouseMotion:
		if candidate_locked:
			if not sliding:
				return 1
			var ends: PackedVector3Array = solid.edge_endpoints(edge)
			if ends.size() == 2 and _typed.is_empty():
				var a := camera.unproject_position(solid.to_global(ends[0]))
				var b := camera.unproject_position(solid.to_global(ends[1]))
				var delta := b - a
				if delta.length_squared() > 1.0:
					_actions.loop_position = clampf((event.position - a).dot(delta) / delta.length_squared(), 0.001, 0.999)
					refresh()
		else:
			var hit: Node3D = SlabPick.pick_solid(_host.scene_root(), camera, event.position)
			var picked: int = SlabPick.pick(hit, SlabSelection.Mode.EDGE, camera, event.position, 14.0) if hit != null else 0
			if picked != edge or hit != solid:
				solid = hit
				edge = picked
				_before = solid.get("data") if solid != null else PackedByteArray()
				_selection.preview_lines = PackedVector3Array()
				_selection.preview_solid = solid
				_selection.hover_changed.emit()
				refresh()
		return 1
	return 1

func _apply_typed() -> void:
	if _typed.is_valid_float():
		_actions.loop_position = clampf(float(_typed) / 100.0, 0.001, 0.999)
		refresh()

func confirm() -> void:
	if not is_instance_valid(solid) or lines.is_empty() or _error != OK:
		return
	if solid.get("data") != _before:
		cancel()
		return
	var target := solid
	var before := _before
	var err: int = target.call("insert_loops", edge, positions())
	if err != OK:
		_report("Loop Cut refused. %s" % SlabActions.describe_error(err, "insert_loop"))
		return
	var after: PackedByteArray = target.get("data")
	var undo: Object = _host.undo()
	if undo != null and before != after:
		undo.create_action("Slab Loop Cut and Slide", UndoRedo.MERGE_DISABLE, target)
		undo.add_do_property(target, "data", after)
		undo.add_undo_property(target, "data", before)
		undo.commit_action(false)
	cancel()
	_selection.solid = target
	_selection.clear_ids()
	_report("Loop cuts applied. Undo restores the original solid.")

func cancel() -> void:
	active = false
	sliding = false
	candidate_locked = false
	edge = 0
	solid = null
	_typed = ""
	lines.clear()
	_selection.preview_lines = PackedVector3Array()
	_selection.preview_solid = null
	_selection.hover_changed.emit()
	_publish_state()

func cancel_from_ui() -> void:
	if not active:
		return
	cancel()
	_report("Loop Cut cancelled.")

func _publish_state() -> void:
	var can_apply: bool = active and is_instance_valid(solid) and edge != 0 and not lines.is_empty() and _error == OK and solid.get("data") == _before
	if _actions.loop_active == active and _actions.loop_can_apply == can_apply:
		return
	_actions.loop_active = active
	_actions.loop_can_apply = can_apply
	_actions.loop_state_changed.emit()

func _report(message: String) -> void:
	_actions.reported.emit(message)

func _selection_changed() -> void:
	if active and _selection.mode != SlabSelection.Mode.EDGE:
		cancel()
