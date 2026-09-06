@tool
extends RefCounted

const FALLBACK := "Node3D"
const ICON_DIR := "res://addons/slab/icons"
const RASTER_SCALE := 2.0

static var _bundle: Dictionary = {}


static func texture(name: String) -> Texture2D:
	var tex := _named(name)
	if tex != null:
		return tex
	if name == FALLBACK:
		return null
	push_warning("Slab has no icon named %s. Falling back to %s." % [name, FALLBACK])
	return _named(FALLBACK)


static func _named(name: String) -> Texture2D:
	var from_editor := _editor_icon(name)
	if from_editor != null:
		return from_editor
	return _bundled(name)


static func _editor_icon(name: String) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var base := EditorInterface.get_base_control()
	if base == null:
		return null
	if base.has_theme_icon(name, "EditorIcons"):
		return base.get_theme_icon(name, "EditorIcons")
	return null


static func _bundled(name: String) -> Texture2D:
	if _bundle.has(name):
		return _bundle[name]
	var path := ICON_DIR.path_join("%s.svg" % name)
	if not FileAccess.file_exists(path):
		_bundle[name] = null
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_bundle[name] = null
		return null
	var img := Image.new()
	var err: int = img.load_svg_from_string(file.get_as_text(), RASTER_SCALE)
	if err != OK or img.is_empty():
		_bundle[name] = null
		return null
	var tex := ImageTexture.create_from_image(img)
	_bundle[name] = tex
	return tex
