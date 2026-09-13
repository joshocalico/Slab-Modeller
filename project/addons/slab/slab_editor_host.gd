@tool
extends RefCounted

signal host_selection_changed
signal inspected_resource_edited(resource: Resource)


func scene_root() -> Node:
	return null


func selected_nodes() -> Array:
	return []


func focus_solid(_solid: Node3D, _additive: bool) -> void:
	pass


func replace_selection(_nodes: Array) -> void:
	pass


func ui_scale() -> float:
	return 1.0


func icon(_icon_name: String) -> Texture2D:
	return null


func undo() -> Object:
	return null


func inspect_resource(_resource: Resource) -> void:
	pass
