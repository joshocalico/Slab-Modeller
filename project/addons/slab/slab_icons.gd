@tool
extends RefCounted

const FALLBACK := "Node3D"


static func texture(name: String) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var base := EditorInterface.get_base_control()
	if base == null:
		return null
	if base.has_theme_icon(name, "EditorIcons"):
		return base.get_theme_icon(name, "EditorIcons")
	push_warning("Slab has no editor icon named %s. Falling back to %s." % [name, FALLBACK])
	if base.has_theme_icon(FALLBACK, "EditorIcons"):
		return base.get_theme_icon(FALLBACK, "EditorIcons")
	return null
