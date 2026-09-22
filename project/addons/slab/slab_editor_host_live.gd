@tool
extends "res://addons/slab/slab_editor_host.gd"

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")

var _undo: EditorUndoRedoManager


static func with_undo(undo: EditorUndoRedoManager) -> RefCounted:
	var host := new()
	host._undo = undo
	host._connect_inspector_edits()
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


func replace_selection(nodes: Array) -> void:
	var editor_selection := EditorInterface.get_selection()
	editor_selection.clear()
	for node in nodes:
		if node != null and is_instance_valid(node):
			editor_selection.add_node(node)


func ui_scale() -> float:
	return EditorInterface.get_editor_scale()


func icon(icon_name: String) -> Texture2D:
	return SlabIcons.texture(icon_name, ui_scale())


func undo() -> Object:
	return _undo


func inspect_resource(resource: Resource) -> void:
	if resource != null:
		_connect_inspector_edits()
		EditorInterface.edit_resource(resource)


func _connect_inspector_edits() -> void:
	var inspector := EditorInterface.get_inspector()
	if inspector != null and not inspector.property_edited.is_connected(_on_inspector_property_edited):
		inspector.property_edited.connect(_on_inspector_property_edited)


func _on_inspector_property_edited(_property: String) -> void:
	var inspector := EditorInterface.get_inspector()
	var resource: Variant = inspector.get_edited_object() if inspector != null else null
	if resource is Resource:
		inspected_resource_edited.emit(resource)


func connect_host_selection(target: Callable) -> void:
	var editor_selection := EditorInterface.get_selection()
	if editor_selection and not editor_selection.selection_changed.is_connected(target):
		editor_selection.selection_changed.connect(target)


func disconnect_host_selection(target: Callable) -> void:
	var editor_selection := EditorInterface.get_selection()
	if editor_selection and editor_selection.selection_changed.is_connected(target):
		editor_selection.selection_changed.disconnect(target)


func refresh_native_selection(solid: Node3D) -> void:
	if solid == null or not is_instance_valid(solid):
		return
	var editor_selection := EditorInterface.get_selection()
	if editor_selection == null:
		return
	var was_selected: bool = editor_selection.get_selected_nodes().has(solid)
	if not was_selected:
		return
	editor_selection.remove_node(solid)
	editor_selection.add_node(solid)
