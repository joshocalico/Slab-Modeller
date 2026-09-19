extends RefCounted

signal version_changed

var actions: Array[Dictionary] = []
var _open: Dictionary = {}
var _cursor: int = 0


func create_action(name: String, merge_mode: int = UndoRedo.MERGE_DISABLE, custom_context: Object = null, backward_undo_ops: bool = false) -> void:
	_open = {
		"name": name,
		"merge": merge_mode,
		"context": custom_context,
		"backward": backward_undo_ops,
		"do_ops": [],
		"undo_ops": [],
	}


func add_do_property(object: Object, property: String, value: Variant) -> void:
	_open["do_ops"].append({ "object": object, "property": property, "value": value })
	_open["object"] = object
	_open["property"] = property
	_open["do"] = value


func add_undo_property(object: Object, property: String, value: Variant) -> void:
	_open["undo_ops"].append({ "object": object, "property": property, "value": value })
	_open["object"] = object
	_open["property"] = property
	_open["undo"] = value


func add_do_method(arg1: Variant, arg2: Variant = null, arg3: Variant = null, arg4: Variant = null, arg5: Variant = null) -> void:
	if arg1 is Callable:
		_open["do_ops"].append({ "callable": arg1 })
	else:
		_open["do_ops"].append({ "callable": _method_callable(arg1, arg2, arg3, arg4, arg5) })


func add_undo_method(arg1: Variant, arg2: Variant = null, arg3: Variant = null, arg4: Variant = null, arg5: Variant = null) -> void:
	if arg1 is Callable:
		_open["undo_ops"].append({ "callable": arg1 })
	else:
		_open["undo_ops"].append({ "callable": _method_callable(arg1, arg2, arg3, arg4, arg5) })


func _method_callable(object: Object, method: StringName, arg1: Variant, arg2: Variant, arg3: Variant) -> Callable:
	var callable := Callable(object, method)
	if arg3 != null:
		return callable.bind(arg1, arg2, arg3)
	if arg2 != null:
		return callable.bind(arg1, arg2)
	if arg1 != null:
		return callable.bind(arg1)
	return callable


func commit_action(execute: bool = true) -> void:
	_open["execute"] = execute
	if execute:
		_apply(_open.get("do_ops", []))
	actions.append(_open)
	_cursor = actions.size()
	_open = {}
	version_changed.emit()


func undo() -> void:
	if _cursor <= 0:
		return
	_cursor -= 1
	_apply(actions[_cursor].get("undo_ops", []))
	version_changed.emit()


func redo() -> void:
	if _cursor >= actions.size():
		return
	_apply(actions[_cursor].get("do_ops", []))
	_cursor += 1
	version_changed.emit()


func _apply(ops: Array) -> void:
	for op in ops:
		if op.has("callable"):
			(op["callable"] as Callable).call()
			continue
		var object: Object = op.get("object")
		if object != null:
			object.set(op["property"], op["value"])
