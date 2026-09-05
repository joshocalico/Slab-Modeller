@tool
extends "res://addons/slab/slab_editor_host.gd"

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")

var _undo: EditorUndoRedoManager


static func with_undo(undo: EditorUndoRedoManager) -> RefCounted:
	var host := new()
	host._undo = undo
	return host


func scene_root() -> Node:
	return EditorInterface.get_edited_scene_root()


func selected_nodes() -> Array:
	return EditorInterface.get_selection().get_selected_nodes()


func focus_solid(solid: Node3D, additive: bool) -> void:
	var editor_selection := EditorInterface.get_selection()
	if not additive:
		var current: Array = editor_selection.get_selected_nodes()
		if current.size() == 1 and SlabSelection.owning_solid(current[0]) == solid:
			EditorInterface.edit_node(solid)
			return
		editor_selection.clear()
	editor_selection.add_node(solid)
	EditorInterface.edit_node(solid)


func ui_scale() -> float:
	return EditorInterface.get_editor_scale()


func icon(icon_name: String) -> Texture2D:
	return SlabIcons.texture(icon_name)


func undo() -> Object:
	return _undo


func connect_host_selection(target: Callable) -> void:
	var editor_selection := EditorInterface.get_selection()
	if editor_selection and not editor_selection.selection_changed.is_connected(target):
		editor_selection.selection_changed.connect(target)


func disconnect_host_selection(target: Callable) -> void:
	var editor_selection := EditorInterface.get_selection()
	if editor_selection and editor_selection.selection_changed.is_connected(target):
		editor_selection.selection_changed.disconnect(target)
