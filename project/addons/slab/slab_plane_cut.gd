@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")

var active := false
var solid: Node3D
var lines := PackedVector3Array()
var _selection: RefCounted
var _actions: RefCounted
var _host: RefCounted
var _before := PackedByteArray()
var _preview_data := PackedByteArray()
var _error: int = OK

func _init(selection: RefCounted, actions: RefCounted, host: RefCounted) -> void:
	_selection = selection
	_actions = actions
	_host = host
	_actions.plane_requested.connect(begin)
	_actions.plane_settings_changed.connect(refresh)
	_actions.plane_apply_requested.connect(confirm)
	_actions.plane_cancel_requested.connect(cancel)
	_selection.changed.connect(_selection_changed)

func _selection_changed() -> void:
	if active and (_selection.mode != SlabSelection.Mode.OBJECT or _selection.solid != solid):
		cancel()

func begin() -> void:
	cancel()
	if _selection.solid == null:
		_report("Plane Cut needs one selected solid.")
		return
	active = true
	solid = _selection.solid
	_before = solid.get("data")
	_actions.plane_active = true
	_actions.plane_state_changed.emit()
	refresh()

func plane_origin() -> Vector3:
	var normal: Vector3 = _actions.plane_normal
	return normal.normalized() * _actions.plane_offset if not normal.is_zero_approx() else Vector3.ZERO

func refresh() -> void:
	if not active or not is_instance_valid(solid):
		return
	if solid.get("data") != _before:
		cancel()
		_report("Plane Cut cancelled: the solid changed.")
		return
	var preview: Dictionary = solid.call("preview_plane_cut", plane_origin(), _actions.plane_normal,
			_actions.plane_keep_positive, _actions.plane_cap_material)
	_error = int(preview.get("error", SlabActions.ERR_INVALID_SELECTION))
	_preview_data = preview.get("data", PackedByteArray())
	lines = preview.get("segments", PackedVector3Array())
	_selection.preview_solid = solid
	_selection.preview_lines = lines
	_selection.hover_changed.emit()
	if _error == OK:
		_report("Plane Cut preview: keeping the %s side. Enter or Apply confirms; Escape cancels." % ["positive" if _actions.plane_keep_positive else "negative"])
	else:
		_report("Plane Cut preview refused. %s" % SlabActions.describe_error(_error, "plane_cut"))

func handle(_camera: Camera3D, event: InputEvent) -> int:
	if not active:
		return 0
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel()
			_report("Plane Cut cancelled.")
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			confirm()
		return 1
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel()
		_report("Plane Cut cancelled.")
		return 1
	return 1

func confirm() -> void:
	if not active or not is_instance_valid(solid) or _error != OK or _preview_data.is_empty():
		return
	if solid.get("data") != _before:
		cancel()
		return
	var target := solid
	var before := _before
	var err: int = target.call("plane_cut", plane_origin(), _actions.plane_normal,
			_actions.plane_keep_positive, _actions.plane_cap_material)
	if err != OK:
		_report("Plane Cut refused. %s" % SlabActions.describe_error(err, "plane_cut"))
		return
	var after: PackedByteArray = target.get("data")
	var undo: Object = _host.undo()
	if undo != null and before != after:
		undo.create_action("Slab Plane Cut", UndoRedo.MERGE_DISABLE, target)
		undo.add_do_property(target, "data", after)
		undo.add_undo_property(target, "data", before)
		undo.commit_action(false)
	cancel()
	_selection.solid = target
	_selection.clear_ids()
	_report("Plane Cut applied. Undo restores the original solid.")

func cancel() -> void:
	active = false
	solid = null
	lines.clear()
	_preview_data.clear()
	_error = OK
	_actions.plane_active = false
	_actions.plane_state_changed.emit()
	_selection.preview_lines = PackedVector3Array()
	_selection.preview_solid = null
	_selection.hover_changed.emit()

func _report(message: String) -> void:
	_actions.reported.emit(message)
