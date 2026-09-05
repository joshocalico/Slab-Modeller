extends "res://addons/slab/slab_editor_host.gd"

var _root: Node
var _host_selection: Array = []
var _commands: Array[String] = []
var _scale: float = 1.0
var _focused: Node3D = null
var _undo: Object = null


static func over(root: Node):
	var host := new()
	host._root = root
	return host


func scene_root() -> Node:
	return _root


func selected_nodes() -> Array:
	return _host_selection.duplicate()


func focus_solid(solid: Node3D, additive: bool) -> void:
	if solid == null:
		return
	_commands.append("focus:%s additive=%s" % [solid.name, str(additive)])
	_focused = solid
	if not additive:
		_host_selection = [solid]
		return
	if not _host_selection.has(solid):
		_host_selection.append(solid)


func ui_scale() -> float:
	return _scale


func icon(_icon_name: String) -> Texture2D:
	return null


func undo() -> Object:
	return _undo


func stub_undo(recorder: Object):
	_undo = recorder
	return self


func stub_ui_scale(scale: float):
	_scale = scale
	return self


func stub_host_selection(nodes: Array) -> void:
	_host_selection = nodes.duplicate()


func focused() -> Node3D:
	return _focused


func commands() -> Array[String]:
	return _commands.duplicate()


func forget_commands() -> void:
	_commands.clear()
