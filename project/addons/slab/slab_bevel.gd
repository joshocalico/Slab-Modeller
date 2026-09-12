@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")

var active := false
var amount := 0.5
var segments := 1
var solid: Node3D
var lines := PackedVector3Array()
var _selection: RefCounted
var _actions: RefCounted
var _host: RefCounted
var _before := PackedByteArray()
var _edges := PackedInt64Array()
var _preview_data := PackedByteArray()
var _error: int = OK

func _init(selection: RefCounted, actions: RefCounted, host: RefCounted) -> void:
	_selection = selection
	_actions = actions
	_host = host
	amount = actions.amount
	_selection.changed.connect(_selection_changed)

func begin() -> void:
	cancel()
	if _selection.mode != SlabSelection.Mode.EDGE or _selection.solid == null or _selection.ids.is_empty():
		_report("Bevel needs one or more selected edges.")
		return
	active = true
	solid = _selection.solid
	_before = solid.get("data")
	_edges = _selection.ids.duplicate()
	refresh()

func set_amount(value: float) -> void:
	amount = clampf(value, SlabActions.AMOUNT_FLOOR, SlabActions.AMOUNT_CEILING)
	refresh()

func set_segments(value: int) -> void:
	segments = clampi(value, 1, 16)
	refresh()

func refresh() -> void:
	if not active or not is_instance_valid(solid):
		return
	if solid.get("data") != _before:
		cancel()
		_report("Bevel cancelled: the solid changed.")
		return
	var preview: Dictionary = solid.call("preview_bevel", _edges, amount, segments)
	_error = int(preview.get("error", SlabActions.ERR_INVALID_SELECTION))
	_preview_data = preview.get("data", PackedByteArray())
	lines = preview.get("segments", PackedVector3Array())
	_selection.preview_solid = solid
	_selection.preview_lines = lines
	_selection.hover_changed.emit()
	if _error == OK:
		_report("Bevel preview: %.2f m, %d segment%s. Enter or Apply confirms; Escape cancels." % [amount, segments, "" if segments == 1 else "s"])
	else:
		_report("Bevel preview refused. %s" % SlabActions.describe_error(_error, "bevel_edges"))

func handle(_camera: Camera3D, event: InputEvent) -> int:
	if not active:
		return 0
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel()
			_report("Bevel cancelled.")
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			confirm()
		return 1
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel()
		_report("Bevel cancelled.")
		return 1
	return 1

func confirm() -> void:
	if not active or not is_instance_valid(solid) or _error != OK or _preview_data.is_empty():
		return
	if solid.get("data") != _before:
		cancel()
		_report("Bevel cancelled: the solid changed.")
		return
	var target := solid
	var before := _before
	var err: int = target.call("bevel_edges", _edges, amount, segments)
	if err != OK:
		_report("Bevel refused. %s" % SlabActions.describe_error(err, "bevel_edges"))
		return
	var after: PackedByteArray = target.get("data")
	var undo: Object = _host.undo()
	if undo != null and before != after:
		undo.create_action("Slab Bevel", UndoRedo.MERGE_DISABLE, target)
		undo.add_do_property(target, "data", after)
		undo.add_undo_property(target, "data", before)
		undo.commit_action(false)
	cancel()
	_selection.solid = target
	_selection.clear_ids()
	_report("Bevel applied. Undo restores the original solid.")

func cancel() -> void:
	active = false
	solid = null
	lines.clear()
	_preview_data.clear()
	_edges.clear()
	_error = OK
	_selection.preview_lines = PackedVector3Array()
	_selection.preview_solid = null
	_selection.hover_changed.emit()

func _selection_changed() -> void:
	if active and (_selection.mode != SlabSelection.Mode.EDGE or _selection.solid != solid or _selection.ids != _edges):
		cancel()

func _report(message: String) -> void:
	_actions.reported.emit(message)
