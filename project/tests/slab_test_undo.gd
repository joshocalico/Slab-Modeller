extends RefCounted

var actions: Array[Dictionary] = []
var _open: Dictionary = {}


func create_action(name: String, merge_mode: int = UndoRedo.MERGE_DISABLE, custom_context: Object = null, backward_undo_ops: bool = false) -> void:
	_open = {
		"name": name,
		"merge": merge_mode,
		"context": custom_context,
		"backward": backward_undo_ops,
	}


func add_do_property(_object: Object, property: String, value: Variant) -> void:
	_open["property"] = property
	_open["do"] = value


func add_undo_property(_object: Object, property: String, value: Variant) -> void:
	_open["property"] = property
	_open["undo"] = value


func commit_action(execute: bool = true) -> void:
	_open["execute"] = execute
	actions.append(_open)
	_open = {}
