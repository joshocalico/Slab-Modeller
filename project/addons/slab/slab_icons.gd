@tool
extends RefCounted

const FALLBACK := "Node3D"
const ICON_DIR := "res://addons/slab/icons"
const RASTER_SCALE := 2.0

static var _bundle: Dictionary = {}


static func texture(name: String, ui_scale: float = 1.0) -> Texture2D:
	var raster: float = RASTER_SCALE * ui_scale
	var tex := _bundled(name, raster)
	if tex != null:
		return tex
	if name == FALLBACK:
		return null
	push_warning("Slab has no icon named %s. Falling back to %s." % [name, FALLBACK])
	return _bundled(FALLBACK, raster)


static func _bundled(name: String, raster: float) -> Texture2D:
	var key := "%s@%.3f" % [name, raster]
	if _bundle.has(key):
		return _bundle[key]
	var path := ICON_DIR.path_join("%s.svg" % name)
	if not FileAccess.file_exists(path):
		_bundle[key] = null
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_bundle[key] = null
		return null
	var svg: String = file.get_as_text()
	var img := Image.new()
	var err: int = img.load_svg_from_string(svg, 1.0)
	if err != OK or img.is_empty():
		_bundle[key] = null
		return null
	var edge: int = maxi(1, int(round(16.0 * raster)))
	# RASTER_SCALE is for 16 px canvases. 10 px and 12 px Godot icons would
	# bilinear-upscale if we only multiplied that scale.
	var native: int = maxi(img.get_width(), img.get_height())
	var fit: float = float(edge) / float(maxi(1, native))
	if not is_equal_approx(fit, 1.0):
		err = img.load_svg_from_string(svg, fit)
		if err != OK or img.is_empty():
			_bundle[key] = null
			return null
	if img.get_width() != edge or img.get_height() != edge:
		img.resize(edge, edge, Image.INTERPOLATE_BILINEAR)
	var tex := ImageTexture.create_from_image(img)
	_bundle[key] = tex
	return tex
