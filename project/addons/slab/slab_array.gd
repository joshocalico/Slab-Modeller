@tool
extends RefCounted

## Modal controller for exact linear and radial SlabSolid arrays.
## UI integration renders preview_transforms() as ghosts; preview never adds nodes.

signal preview_changed(transforms: Array[Transform3D])
signal reported(text: String)

enum Mode { LINEAR, RADIAL }

var mode: int = Mode.LINEAR
var count: int = 2
var linear_step := Vector3(2, 0, 0)
var radial_center := Vector3.ZERO
var radial_axis := Vector3.UP
var radial_angle_degrees := 45.0
var rotate_radial_copies := true

var active := false
var _source: Node3D = null
var _source_parent: Node = null
var _source_transform := Transform3D.IDENTITY
var _source_data := PackedByteArray()
var _host: RefCounted
var _copies: Array[Node3D] = []


func _init(host: RefCounted) -> void:
	_host = host


func begin(source: Node3D) -> bool:
	cancel()
	if source == null or not is_instance_valid(source) or not source.is_class("SlabSolid"):
		_report("Array needs one SlabSolid in Object mode.")
		return false
	if source.get_parent() == null:
		_report("Array needs a SlabSolid in the edited scene.")
		return false
	_source = source
	_source_parent = source.get_parent()
	_source_transform = source.transform
	_source_data = source.get("data")
	active = true
	refresh_preview()
	return true


func refresh_preview() -> Array[Transform3D]:
	var transforms := preview_transforms()
	preview_changed.emit(transforms)
	return transforms


func preview_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if not active or not is_instance_valid(_source) or count < 2:
		return out
	var source_xform := _source_transform
	for index in range(1, count):
		if mode == Mode.LINEAR:
			var linear := source_xform
			linear.origin += linear_step * index
			out.append(linear)
		else:
			var axis := radial_axis.normalized()
			if axis == Vector3.ZERO:
				return []
			var turn := Basis(axis, deg_to_rad(radial_angle_degrees * index))
			var radial := source_xform
			radial.origin = radial_center + turn * (source_xform.origin - radial_center)
			if rotate_radial_copies:
				radial.basis = turn * source_xform.basis
			out.append(radial)
	return out


func confirm() -> Array[Node3D]:
	if not _source_is_unchanged():
		cancel()
		_report("Array cancelled because the source changed during preview.")
		return []
	var transforms := preview_transforms()
	if transforms.is_empty():
		_report("Array needs a count of at least 2 and a valid radial axis.")
		return []
	var root: Node = _host.scene_root()
	var undo: Object = _host.undo()
	if root == null or undo == null:
		_report("Array needs an open scene and editor undo.")
		return []
	_copies.clear()
	for copy_transform in transforms:
		var copy := _source.duplicate() as Node3D
		if copy == null:
			continue
		copy.transform = copy_transform
		_copies.append(copy)
	if _copies.size() != transforms.size():
		for copy in _copies:
			copy.free()
		_copies.clear()
		_report("Array could not duplicate the selected solid.")
		return []
	undo.create_action("Slab %s Array" % ("Linear" if mode == Mode.LINEAR else "Radial"), UndoRedo.MERGE_DISABLE, root)
	for copy in _copies:
		undo.add_do_method(_source_parent, "add_child", copy, true)
		undo.add_do_method(copy, "set_owner", root)
		if undo.has_method("add_do_reference"):
			undo.add_do_reference(copy)
		undo.add_undo_method(_source_parent, "remove_child", copy)
	undo.commit_action()
	var result := _copies.duplicate()
	active = false
	_source = null
	_source_parent = null
	preview_changed.emit([])
	_report("Created %d copies as one undo action." % result.size())
	return result


func cancel() -> void:
	active = false
	_source = null
	_source_parent = null
	_source_data.clear()
	preview_changed.emit([])


func _source_is_unchanged() -> bool:
	return (
		active
		and is_instance_valid(_source)
		and _source.get_parent() == _source_parent
		and _source.transform == _source_transform
		and _source.get("data") == _source_data
	)


func _report(message: String) -> void:
	reported.emit(message)
