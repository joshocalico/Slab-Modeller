@tool
extends RefCounted

const SlabPaintUv := preload("res://addons/slab/slab_paint_uv.gd")
const SlabPaintRaster := preload("res://addons/slab/slab_paint_raster.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")

signal changed
signal image_changed
signal reported(text: String)
signal channel_changed
signal layers_changed

enum Tool { MATERIAL_UV, PIXEL }
enum Channel { ALBEDO, ROUGHNESS, EMISSION }

const PNG_META := "slab_paint_png"
const OWNED_META := "slab_paint_owned"
const LAYERS_META := "slab_paint_layers"
const DEFAULT_SIZE := 256
const PAINT_HEIGHT := 360.0
const VERDICT_PASS := 0
const VERDICT_STOP := 1
const UV_MOVE := 0
const UV_SCALE := 1
const UV_ROTATE := 2

var active: bool = false:
	set(value):
		if value == active:
			return
		if not value:
			cancel_stroke()
			cancel_uv_drag()
			_left_gesture_owned = false
		active = value
		changed.emit()

var tool: int = Tool.MATERIAL_UV:
	set(value):
		if value == tool:
			return
		cancel_stroke()
		cancel_uv_drag()
		_left_gesture_owned = false
		tool = value
		if tool == Tool.MATERIAL_UV:
			channel = Channel.ALBEDO
		if active:
			if tool == Tool.MATERIAL_UV:
				_bind_brush_to_selection()
			else:
				_bind_pixel_selection()
		changed.emit()

var brush_color := Color(0.86, 0.18, 0.16)
var brush_radius: float = 8.0
var brush_opacity: float = 1.0
var overlay_opacity: float:
	get:
		if _material == null:
			return 1.0
		return channel_state(channel).active_layer().opacity
	set(value):
		if _material != null:
			set_layer_opacity(active_layer_index(), value)
var dirty: bool = false
var stroke_active: bool = false
var _left_gesture_owned := false
var _overlay_image: Image
var _overlay_dirty: bool = false

var channel: int = Channel.ALBEDO:
	set(value):
		if value == channel:
			return
		cancel_stroke()
		cancel_uv_drag()
		var old_channel := channel
		channel = value
		_switch_channel(old_channel, channel)
		channel_changed.emit()
		changed.emit()

class PaintLayer:
	var name: String = "Layer 1"
	var visible: bool = true
	var opacity: float = 1.0
	var image: Image
	
	func _init(size: Vector2i = Vector2i(256, 256), layer_name: String = "Layer 1") -> void:
		name = layer_name
		image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
	
	func is_empty() -> bool:
		if image == null or image.is_empty():
			return true
		var data: PackedByteArray = image.get_data()
		for i in range(3, data.size(), 4):
			if data[i] > 0:
				return false
		return true
	
	func duplicate_layer() -> PaintLayer:
		var copy := PaintLayer.new(image.get_size(), name)
		copy.visible = visible
		copy.opacity = opacity
		copy.image = image.duplicate()
		return copy

class ChannelState:
	var base_image: Image
	var layers: Array[PaintLayer] = []
	var active_layer_index: int = 0
	var texture: ImageTexture
	var dirty: bool = false
	
	func _init(size: Vector2i = Vector2i(256, 256)) -> void:
		base_image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		base_image.fill(Color(0, 0, 0, 0))
		var first_layer := PaintLayer.new(size, "Layer 1")
		layers.append(first_layer)
	
	func active_layer() -> PaintLayer:
		if active_layer_index >= 0 and active_layer_index < layers.size():
			return layers[active_layer_index]
		return null
	
	func has_visible_strokes() -> bool:
		for layer in layers:
			if layer.visible and not layer.is_empty():
				return true
		return false
	
	func add_layer(layer_name: String = "") -> int:
		var size := base_image.get_size() if base_image != null else Vector2i(256, 256)
		var new_name := layer_name if layer_name != "" else "Layer %d" % (layers.size() + 1)
		var new_layer := PaintLayer.new(size, new_name)
		layers.append(new_layer)
		active_layer_index = layers.size() - 1
		return active_layer_index
	
	func remove_layer(index: int) -> bool:
		if layers.size() <= 1:
			return false
		if index < 0 or index >= layers.size():
			return false
		layers.remove_at(index)
		if active_layer_index >= layers.size():
			active_layer_index = layers.size() - 1
		elif active_layer_index > index:
			active_layer_index -= 1
		return true
	
	func composite_all_layers(base: Image) -> Image:
		var result := base.duplicate() if base != null else Image.create(256, 256, false, Image.FORMAT_RGBA8)
		for layer in layers:
			if layer.visible and layer.image != null and not layer.image.is_empty():
				_blend_layer(result, layer.image, layer.opacity)
		return result
	
	static func _blend_layer(base: Image, overlay: Image, opacity: float) -> void:
		if base == null or overlay == null or base.is_empty() or overlay.is_empty():
			return
		var w: int = mini(base.get_width(), overlay.get_width())
		var h: int = mini(base.get_height(), overlay.get_height())
		for y in range(h):
			for x in range(w):
				var src: Color = overlay.get_pixel(x, y)
				if src.a < 0.001:
					continue
				var dst: Color = base.get_pixel(x, y)
				var a: float = src.a * opacity
				base.set_pixel(x, y, dst.lerp(Color(src.r, src.g, src.b, 1.0), a))

# The material stores serialized artwork; this cache holds only live editing images.
var _material_states: Dictionary = {}  # instance ID -> weak material reference and channels
var _empty_channel_states: Dictionary = {}
var _stroke_state: Dictionary = {}

var _undo: Object = null
var _selection: RefCounted
var _actions: RefCounted
var _image: Image
var _texture: ImageTexture
var _material: StandardMaterial3D
var _brush_material: StandardMaterial3D
var _watched_brush_material: StandardMaterial3D
var _solid: Node3D
var _slot: int = -1
var _stroke_before := PackedByteArray()
var _stroke_material: StandardMaterial3D
var _host: RefCounted
var _last_pixel := Vector2(-1, -1)
var _uv_offset_start := Vector2.ZERO
var _uv_scale_start := Vector2.ONE
var _uv_rotation_start := 0.0
var _uv_before_data := PackedByteArray()
var uv_drag_active := false
var _uv_solid: Node3D
var _uv_ids := PackedInt64Array()
var _brush_node: MeshInstance3D
var _dirty_ids: Dictionary = {}
var _pending_scene_saves: Dictionary = {}
var _locked_solid: Node3D = null
var _had_prior_lock: bool = false


func bind(selection: RefCounted, actions: RefCounted, undo: Object, host: RefCounted = null) -> void:
	if _undo != null and _undo.has_signal("version_changed"):
		if _undo.version_changed.is_connected(_on_undo_version):
			_undo.version_changed.disconnect(_on_undo_version)
	_selection = selection
	_actions = actions
	_undo = undo
	_host = host
	if _host != null and _host.has_signal("inspected_resource_edited"):
		var callback := Callable(self, "_on_inspected_resource_edited")
		if not _host.is_connected("inspected_resource_edited", callback):
			_host.connect("inspected_resource_edited", callback)
	if _selection != null and _selection.has_signal("changed"):
		if not _selection.changed.is_connected(_on_selection_changed):
			_selection.changed.connect(_on_selection_changed)
		if not _selection.mode_requested.is_connected(_on_mode_requested):
			_selection.mode_requested.connect(_on_mode_requested)
	if _undo != null and _undo.has_signal("version_changed"):
		if not _undo.version_changed.is_connected(_on_undo_version):
			_undo.version_changed.connect(_on_undo_version)


func enter() -> void:
	_left_gesture_owned = false
	active = true
	if _selection != null:
		_selection.mode = 3
	_lock_transform_gizmo()
	_adopt_selection_material()
	if tool == Tool.PIXEL:
		_report("Paint workspace. Brush paints albedo; switch to UV workspace for material placement.")
	else:
		_report("UV workspace. Place textures and materials; switch to Paint workspace for pixel painting.")


func exit() -> void:
	_left_gesture_owned = false
	cancel_stroke()
	_save_current_overlay_to_channel(channel)
	_free_brush()
	_unlock_transform_gizmo()
	active = false
	_report("Returned to modelling.")


func toggle() -> void:
	if active:
		exit()
	else:
		enter()


func image() -> Image:
	return _image


func overlay_image() -> Image:
	return _overlay_image


func has_overlay_strokes() -> bool:
	return _overlay_image != null and not _overlay_image.is_empty() and _overlay_dirty


func texture() -> Texture2D:
	return _texture


func material() -> StandardMaterial3D:
	return _material


func brush_material() -> StandardMaterial3D:
	return _brush_material


func selected_material_summary() -> String:
	var common: Dictionary = _common_selected_material()
	if common.is_empty():
		return "none" if _selection == null or _selection.ids.is_empty() else "Mixed"
	var mat: Variant = common.get("material")
	return material_label(mat, int(common.get("slot", 0))) if mat is StandardMaterial3D else "Default"


func brush_preview_caption() -> String:
	if tool != Tool.MATERIAL_UV or _selection == null:
		return ""
	if _brush_material == null:
		return "Selected: Mixed · Choose or sample a brush" if not _selection.ids.is_empty() and _common_selected_material().is_empty() else ""
	var brush_name := material_label(_brush_material, _slot)
	if _selection.ids.is_empty():
		return "Brush preview: %s · Click a face to paint" % brush_name
	var common := _common_selected_material()
	if not common.is_empty() and common.get("material") == _brush_material:
		return ""
	return "Brush preview: %s · Assign to apply to selection" % brush_name


func select_material_slot(slot: int) -> bool:
	if _selection == null or _selection.solid == null:
		return false
	var mats: Array = _selection.solid.get("materials")
	if slot < 0 or slot >= mats.size() or not (mats[slot] is StandardMaterial3D):
		_set_brush_material(null)
		_bind_empty_selection_target()
		return false
	_set_brush_material(mats[slot])
	_actions.material_slot = slot
	if tool == Tool.PIXEL:
		_bind_pixel_selection()
	else:
		_bind_from_selection()
	return true


func choose_brush_material(mat: StandardMaterial3D) -> void:
	_set_brush_material(mat)
	if mat == null:
		_bind_empty_selection_target()
		_report("Brush cleared. Choose a material before Assign.")
		return
	_bind_brush_to_selection()
	_report("Brush preview: %s. Assign applies it to the selected faces." % material_label(mat, _slot))


func _on_chosen_brush_changed() -> void:
	refresh_brush_preview()


func refresh_brush_preview() -> void:
	if (not active or tool != Tool.MATERIAL_UV or stroke_active or uv_drag_active
		or _brush_material == null or _brush_material != _watched_brush_material):
		return
	_material = _brush_material
	_image = _image_from_material(_brush_material)
	_sync_texture_resolution_from_artwork(_brush_material, _image)
	_texture = _brush_material.albedo_texture as ImageTexture
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
	changed.emit()


func inspect_brush_resource(resource: Resource) -> void:
	if _host != null and resource != null:
		_host.inspect_resource(resource)


func _on_inspected_resource_edited(resource: Resource) -> void:
	if resource == _brush_material:
		call_deferred("refresh_brush_preview")


func _set_brush_material(mat: StandardMaterial3D) -> void:
	if _watched_brush_material != null and _watched_brush_material.changed.is_connected(_on_chosen_brush_changed):
		_watched_brush_material.changed.disconnect(_on_chosen_brush_changed)
	_watched_brush_material = null
	_brush_material = mat
	if mat != null:
		_watched_brush_material = mat
		if not mat.changed.is_connected(_on_chosen_brush_changed):
			mat.changed.connect(_on_chosen_brush_changed)


func sample_selection() -> bool:
	var common := _common_selected_material()
	if common.is_empty() or not (common.get("material") is StandardMaterial3D):
		_report("Select faces that use one material before Sample.")
		return false
	_set_brush_material(common["material"])
	_actions.material_slot = int(common["slot"])
	_bind_from_selection()
	_report("Sampled %s." % material_label(_brush_material, int(common["slot"])))
	return true


func slot() -> int:
	return _slot


func is_pixel() -> bool:
	return tool == Tool.PIXEL


func can_make_unique() -> bool:
	if _selection == null or _selection.objects.size() != 1 or _selection.ids.is_empty():
		return false
	if tool == Tool.MATERIAL_UV and _brush_material != null:
		return true
	var common := _common_selected_material()
	if common.is_empty():
		return false
	if tool == Tool.MATERIAL_UV:
		return _brush_material != null or common.get("material") == null
	return _material != null or common.get("material") == null


func is_owned(mat: StandardMaterial3D) -> bool:
	return _is_unique(mat)


func brush_preview() -> MeshInstance3D:
	return _brush_node if _brush_node != null and is_instance_valid(_brush_node) else null


func thumbnail(mat: Variant, px: int = 28) -> Texture2D:
	var size: int = maxi(8, px)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	if mat is StandardMaterial3D and mat.albedo_texture != null and mat.albedo_texture.has_method("get_image"):
		var src: Image = mat.albedo_texture.get_image()
		if src != null and not src.is_empty():
			var copy: Image = src.duplicate()
			if copy.is_compressed():
				copy.decompress()
			if copy.get_format() != Image.FORMAT_RGBA8:
				copy.convert(Image.FORMAT_RGBA8)
			copy.resize(size, size, Image.INTERPOLATE_BILINEAR)
			return ImageTexture.create_from_image(copy)
		img.fill(mat.albedo_color)
	elif mat is StandardMaterial3D:
		img.fill(mat.albedo_color)
	else:
		img.fill(Color(0.45, 0.45, 0.42))
	return ImageTexture.create_from_image(img)


static func uv_rotate_modifier_name() -> String:
	return "Cmd" if OS.get_name() == "macOS" else "Ctrl"


static func uv_canvas_hint() -> String:
	return "Drag moves UV. Shift scales. %s rotates. Scroll zooms. Middle-drag pans." % uv_rotate_modifier_name()


static func uv_mode_for(event: InputEvent) -> int:
	if event is InputEventWithModifiers:
		# macOS Control-click is a secondary click before the canvas sees it.
		# Native free-rotate on macOS is Command (meta_pressed); Ctrl still
		# rotates on other platforms and in synthetic events.
		if event.ctrl_pressed or event.meta_pressed:
			return UV_ROTATE
		if event.shift_pressed:
			return UV_SCALE
	return UV_MOVE


func selected_uvs() -> PackedVector2Array:
	if _selection == null or _selection.solid == null or _selection.ids.is_empty():
		return PackedVector2Array()
	return SlabPaintUv.face_uvs(_selection.solid, _selection.ids[0])


func selected_uv_loops() -> Array[PackedVector2Array]:
	var loops: Array[PackedVector2Array] = []
	if _selection == null or _selection.solid == null:
		return loops
	for face in _selection.ids:
		var uvs := SlabPaintUv.face_uvs(_selection.solid, face)
		if not uvs.is_empty():
			loops.append(uvs)
	return loops


func refresh_uv_mapping() -> void:
	_sync_uv_from_selection()
	changed.emit()


func make_unique() -> int:
	var solid: Node3D = _selection.solid if _selection != null else null
	if solid == null:
		_report("Select a solid before Make Unique.")
		return -1
	if _selection.ids.is_empty():
		_report("Select a face, then Make Unique so the copy attaches to that face.")
		return -1
	if not can_make_unique():
		_report("Select faces that use one material before Make Unique.")
		return -1
	_actions.clamp_material_slot()
	var prev_slot: int = _actions.material_slot
	var before_mats: Array = (solid.get("materials") as Array).duplicate()
	var before_data: PackedByteArray = solid.get("data")
	var mats: Array = before_mats.duplicate()
	var src: Variant = _brush_material if tool == Tool.MATERIAL_UV else _material
	var copy := _duplicate_material(src)
	var img: Image = _image_from_material(copy if copy != null else src, _new_texture_size())
	var tex := ImageTexture.create_from_image(img)
	copy.albedo_texture = tex
	copy.resource_local_to_scene = true
	copy.resource_path = ""
	copy.set_meta(OWNED_META, true)
	mats.append(copy)
	var new_slot: int = mats.size() - 1
	solid.set("materials", mats)
	_set_brush_material(copy)
	_actions.material_slot = new_slot
	solid.call("set_face_material", _selection.ids, new_slot)
	if _undo != null:
		_create_undo_action("Slab Make Unique Material", solid)
		_undo.add_do_property(solid, "materials", mats)
		_undo.add_undo_property(solid, "materials", before_mats)
		_undo.add_do_property(solid, "data", solid.get("data"))
		_undo.add_undo_property(solid, "data", before_data)
		_undo.add_do_property(_actions, "material_slot", new_slot)
		_undo.add_undo_property(_actions, "material_slot", prev_slot)
		_undo.commit_action(false)
	_bind_editable(solid, new_slot, copy, img, tex)
	_mark_dirty(copy, true)
	_report("Unique material %d on the selected face. Pixel paint stays on this copy." % new_slot)
	changed.emit()
	return new_slot


func assign_active_to_selection() -> void:
	if tool == Tool.MATERIAL_UV:
		if _brush_material == null:
			_report("Choose or sample a material before painting.")
			return
		pick_material(_brush_material)
	elif _actions != null:
		_actions.run("set_face_material")


func sample_face(solid: Node3D, face: int) -> void:
	if solid == null:
		return
	var attrs: Dictionary = solid.face_uv(face)
	if attrs.is_empty():
		return
	_actions.material_slot = int(attrs.get("slot", 0))
	_actions.uv_scale = attrs.get("scale", Vector2.ONE)
	_actions.uv_offset = attrs.get("offset", Vector2.ZERO)
	_actions.uv_rotation_degrees = rad_to_deg(float(attrs.get("rotation", 0.0)))
	var mats: Array = solid.get("materials")
	var sampled_slot := int(attrs.get("slot", 0))
	_set_brush_material(mats[sampled_slot] if sampled_slot >= 0 and sampled_slot < mats.size() and mats[sampled_slot] is StandardMaterial3D else null)
	_focus_target(solid)
	_selection.set_objects([solid])
	_selection.set_ids(PackedInt64Array([face]))
	if _brush_material != null:
		_bind_from_selection()
		_report("Sampled %s." % material_label(_brush_material, sampled_slot))
	else:
		_bind_empty_selection_target()
		_report("The default material cannot be used as a brush. Choose a material first.")


func rotate_uv_90() -> void:
	if _actions != null:
		_actions.run("uv_rotate")
		changed.emit()


func apply_uv() -> void:
	if _actions != null:
		_actions.run("uv_apply")
		changed.emit()


func scale_uv(factor: float) -> void:
	if _actions != null:
		_actions.run("uv_scale_up" if factor > 1.0 else "uv_scale_down")
		changed.emit()


func reset_uv() -> void:
	if _actions != null:
		_actions.run("uv_reset")
		changed.emit()


func can_resize_image() -> bool:
	return (active and tool == Tool.PIXEL and _material != null and _is_unique(_material)
		and _image != null and not _image.is_empty() and _solid != null and not stroke_active and not uv_drag_active)


func resize_image(width: int, height: int, smooth: bool = true, expected_material: StandardMaterial3D = null) -> bool:
	if expected_material != null and _material != expected_material:
		_report("Resize target changed. Open Resize again for the current image.")
		return false
	if not can_resize_image():
		_report("Make Unique before resizing this image.")
		return false
	width = clampi(width, 16, 16384)
	height = clampi(height, 16, 16384)
	if _image.get_size() == Vector2i(width, height):
		_report("Image is already %d × %d px." % [width, height])
		return false
	_save_current_overlay_to_channel(channel)
	var before := _snapshot_channel(_material, channel)
	var state := channel_state(channel)
	var interpolation := Image.INTERPOLATE_BILINEAR if smooth else Image.INTERPOLATE_NEAREST
	state.base_image.resize(width, height, interpolation)
	for layer in state.layers:
		layer.image.resize(width, height, interpolation)
	_load_channel_overlay(channel)
	_commit_channel_edit("Slab Resize Paint Image", before)
	_actions.uv_texture_resolution = width
	_report("Resized paint image to %d × %d px." % [width, height])
	return true


func can_flatten() -> bool:
	return (active and _material != null and _is_unique(_material)
		and _image != null and not _image.is_empty() and _solid != null
		and not stroke_active and not uv_drag_active and has_channel_overlay_strokes())


func flatten() -> bool:
	if not can_flatten():
		_report("No overlay strokes to flatten.")
		return false
	_save_current_overlay_to_channel(channel)
	var before := _snapshot_channel(_material, channel)
	var state := channel_state(channel)
	_flatten_all_layers_to_base(state)
	# Hidden artwork remains editable. Only the visible layers were committed.
	var hidden: Array[PaintLayer] = []
	for layer in state.layers:
		if not layer.visible:
			hidden.append(layer)
	state.layers = hidden
	state.add_layer("Layer 1" if hidden.is_empty() else "Paint")
	_load_channel_overlay(channel)
	_commit_channel_edit("Slab Flatten %s Layer" % channel_name(channel), before)
	_report("Flattened visible layers to %s." % channel_name(channel))
	return true


func _flatten_all_layers_to_base(state: ChannelState) -> void:
	if _image == null or _image.is_empty():
		return
	for layer in state.layers:
		if layer.visible and layer.image != null and not layer.image.is_empty():
			ChannelState._blend_layer(state.base_image, layer.image, layer.opacity)


func _serialize_layers(state: ChannelState) -> Array:
	var result: Array = []
	for layer in state.layers:
		result.append({
			"name": layer.name,
			"visible": layer.visible,
			"opacity": layer.opacity,
			"png": layer.image.save_png_to_buffer() if layer.image != null and not layer.image.is_empty() else PackedByteArray()
		})
	result.append({"active_index": state.active_layer_index})
	return result


func _deserialize_layers(state: ChannelState, data: Array) -> void:
	state.layers.clear()
	var active_index := 0
	for item in data:
		if item.has("active_index"):
			active_index = int(item["active_index"])
			continue
		var layer := PaintLayer.new(Vector2i(DEFAULT_SIZE, DEFAULT_SIZE), str(item.get("name", "Layer")))
		layer.visible = bool(item.get("visible", true))
		layer.opacity = float(item.get("opacity", 1.0))
		var png: PackedByteArray = item.get("png", PackedByteArray())
		if not png.is_empty():
			var img := Image.new()
			if img.load_png_from_buffer(png) == OK:
				layer.image = img
		state.layers.append(layer)
	if state.layers.is_empty():
		state.add_layer("Layer 1")
	state.active_layer_index = clampi(active_index, 0, state.layers.size() - 1)


func _set_channel_texture(ch: int, tex: ImageTexture, mat: StandardMaterial3D = null) -> void:
	var target := mat if mat != null else _material
	if target == null:
		return
	match ch:
		Channel.ALBEDO:
			target.albedo_texture = tex
		Channel.ROUGHNESS:
			target.roughness_texture = tex
			if tex != null:
				target.roughness = 1.0
				target.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		Channel.EMISSION:
			target.emission_enabled = true
			target.emission_texture = tex
			if tex != null:
				# Authored RGB pixels control the mask; energy remains the brightness control.
				target.emission = Color.WHITE
				target.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY


func _ensure_overlay() -> void:
	if _image == null or _image.is_empty():
		return
	if _overlay_image == null or _overlay_image.is_empty() or _overlay_image.get_size() != _image.get_size():
		_overlay_image = Image.create(_image.get_width(), _image.get_height(), false, Image.FORMAT_RGBA8)
		_overlay_image.fill(Color(0, 0, 0, 0))
		_overlay_dirty = false


func _clear_overlay() -> void:
	if _overlay_image != null and not _overlay_image.is_empty():
		_overlay_image.fill(Color(0, 0, 0, 0))
	_overlay_dirty = false

func _composite_overlay() -> void:
	if _image == null or _image.is_empty() or _material == null:
		return
	_save_current_overlay_to_channel(channel)
	var state := channel_state(channel)
	state.base_image = _image
	_render_channel(_material, channel, state)
	_texture = state.texture
	image_changed.emit()


func begin_uv_drag() -> void:
	cancel_uv_drag()
	if _selection == null or _selection.solid == null or _selection.ids.is_empty():
		return
	_uv_solid = _selection.solid
	_uv_ids = _selection.ids.duplicate()
	uv_drag_active = true
	_uv_offset_start = _actions.uv_offset
	_uv_scale_start = _actions.uv_scale
	_uv_rotation_start = _actions.uv_rotation_degrees
	_uv_before_data = _uv_solid.get("data")


# Delta is UV displacement for Move, normalized screen displacement for Scale/Rotate.
func drag_uv(delta: Vector2, mode: int = UV_MOVE) -> void:
	if not uv_drag_active or not is_instance_valid(_uv_solid):
		return
	if mode == UV_SCALE:
		_actions.uv_scale = Vector2(
			maxf(0.05, _uv_scale_start.x * (1.0 + delta.x)),
			maxf(0.05, _uv_scale_start.y * (1.0 + delta.y))
		)
	elif mode == UV_ROTATE:
		_actions.uv_rotation_degrees = _uv_rotation_start + delta.x * 180.0
	else:
		_actions.uv_offset = _uv_offset_start + delta
	_uv_solid.call("set_face_uv", _uv_ids, _actions.uv_scale, _actions.uv_offset, deg_to_rad(_actions.uv_rotation_degrees))
	changed.emit()


func end_uv_drag() -> void:
	if not uv_drag_active:
		return
	uv_drag_active = false
	var solid: Node3D = _uv_solid
	_uv_solid = null
	if not is_instance_valid(solid):
		return
	var after: PackedByteArray = solid.get("data")
	if after == _uv_before_data:
		return
	if _undo != null:
		_create_undo_action("Slab UV Place", solid)
		_undo.add_do_property(solid, "data", after)
		_undo.add_undo_property(solid, "data", _uv_before_data)
		_undo.add_do_property(_actions, "uv_offset", _actions.uv_offset)
		_undo.add_undo_property(_actions, "uv_offset", _uv_offset_start)
		_undo.add_do_property(_actions, "uv_scale", _actions.uv_scale)
		_undo.add_undo_property(_actions, "uv_scale", _uv_scale_start)
		_undo.add_do_property(_actions, "uv_rotation_degrees", _actions.uv_rotation_degrees)
		_undo.add_undo_property(_actions, "uv_rotation_degrees", _uv_rotation_start)
		_undo.commit_action(false)
	changed.emit()


func cancel_uv_drag() -> void:
	if not uv_drag_active:
		return
	uv_drag_active = false
	var solid: Node3D = _uv_solid
	_uv_solid = null
	if is_instance_valid(solid):
		solid.set("data", _uv_before_data)
	_actions.uv_offset = _uv_offset_start
	_actions.uv_scale = _uv_scale_start
	_actions.uv_rotation_degrees = _uv_rotation_start
	changed.emit()


func begin_stroke() -> bool:
	if not _ensure_editable():
		return false
	_save_current_overlay_to_channel(channel)
	_stroke_state = _snapshot_channel(_material, channel)
	stroke_active = true
	_ensure_overlay()
	_stroke_before = _overlay_image.save_png_to_buffer() if _overlay_image != null and not _overlay_image.is_empty() else PackedByteArray()
	_stroke_material = _material
	_last_pixel = Vector2(-1, -1)
	return true


func dab_uv(uv: Vector2) -> void:
	if not stroke_active or _image == null:
		return
	var pixel := Vector2(SlabPaintUv.uv_to_pixel(uv, _image.get_width(), _image.get_height())) + Vector2(0.5, 0.5)
	_dab_at(pixel)


func dab_pixel(pixel: Vector2) -> void:
	if not stroke_active or _image == null:
		return
	_dab_at(pixel)


func end_stroke() -> void:
	if not stroke_active:
		return
	stroke_active = false
	if _overlay_image == null or _overlay_image.is_empty() or _overlay_image.save_png_to_buffer() == _stroke_before:
		return
	_save_current_overlay_to_channel(channel)
	_commit_channel_edit("Slab Paint Stroke", _stroke_state)
	_report("Painted on %s layer." % channel_name(channel))


func _is_overlay_empty() -> bool:
	if _overlay_image == null or _overlay_image.is_empty():
		return true
	var data: PackedByteArray = _overlay_image.get_data()
	for i in range(3, data.size(), 4):
		if data[i] > 0:
			return false
	return true


static func channel_name(ch: int) -> String:
	match ch:
		Channel.ALBEDO: return "Albedo"
		Channel.ROUGHNESS: return "Roughness"
		Channel.EMISSION: return "Emission"
		_: return "Unknown"


func current_channel() -> int:
	return channel


func current_channel_name() -> String:
	return channel_name(channel)


func channel_state(ch: int) -> ChannelState:
	return _state_for_material(_material, ch)


func _state_for_material(mat: StandardMaterial3D, ch: int) -> ChannelState:
	var channels: Dictionary
	if mat == null:
		channels = _empty_channel_states
	else:
		var material_id := mat.get_instance_id()
		if not _material_states.has(material_id):
			_material_states[material_id] = {"material": weakref(mat), "channels": {}}
		channels = _material_states[material_id]["channels"]
	if not channels.has(ch):
		var base: Image
		match ch:
			Channel.ROUGHNESS: base = _roughness_image_from_material(mat)
			Channel.EMISSION: base = _emission_image_from_material(mat)
			_: base = _image_from_material(mat, _new_texture_size())
		var state := ChannelState.new(base.get_size())
		state.base_image = base
		if mat != null and mat.has_meta(LAYERS_META):
			var stored: Dictionary = mat.get_meta(LAYERS_META)
			if stored.has(ch):
				_decode_channel(state, stored[ch])
		channels[ch] = state
	return channels[ch]


func _encode_channel(state: ChannelState) -> Dictionary:
	return {"base": state.base_image.save_png_to_buffer(), "layers": _serialize_layers(state)}


func _decode_channel(state: ChannelState, data: Dictionary) -> void:
	var base := Image.new()
	if base.load_png_from_buffer(data["base"]) == OK:
		state.base_image = base
	_deserialize_layers(state, data["layers"])


func _snapshot_channel(mat: StandardMaterial3D, ch: int) -> Dictionary:
	var texture_present := false
	if mat != null:
		match ch:
			Channel.ALBEDO: texture_present = mat.albedo_texture != null
			Channel.ROUGHNESS: texture_present = mat.roughness_texture != null
			Channel.EMISSION: texture_present = mat.emission_texture != null
	return {"material": mat, "channel": ch, "data": _encode_channel(_state_for_material(mat, ch)),
		"texture_present": texture_present, "emission_enabled": mat.emission_enabled if mat != null else false,
		"emission": mat.emission if mat != null else Color.BLACK,
		"emission_operator": mat.emission_operator if mat != null else BaseMaterial3D.EMISSION_OP_ADD,
		"emission_texture": mat.emission_texture if mat != null else null,
		"roughness": mat.roughness if mat != null else 0.5,
		"roughness_texture": mat.roughness_texture if mat != null else null,
		"roughness_component": mat.roughness_texture_channel if mat != null else BaseMaterial3D.TEXTURE_CHANNEL_RED}


func _persist_channel(mat: StandardMaterial3D, ch: int, state: ChannelState) -> void:
	if not _is_unique(mat):
		return
	var stored: Dictionary = (mat.get_meta(LAYERS_META, {}) as Dictionary).duplicate(true)
	stored[ch] = _encode_channel(state)
	mat.set_meta(LAYERS_META, stored)


func _render_channel(mat: StandardMaterial3D, ch: int, state: ChannelState, publish: bool = true) -> void:
	var display := state.composite_all_layers(state.base_image)
	display.generate_mipmaps()
	state.texture = ImageTexture.create_from_image(display)
	if publish and _is_unique(mat):
		_set_channel_texture(ch, state.texture, mat)
		mat.emit_changed()


func _commit_channel_edit(label: String, before: Dictionary) -> void:
	var state := channel_state(channel)
	_render_channel(_material, channel, state)
	_image = state.base_image
	_texture = state.texture
	_persist_channel(_material, channel, state)
	_mark_dirty(_material, true)
	if _undo != null:
		_create_undo_action(label, _solid)
		_add_do_method(_restore_channel, _snapshot_channel(_material, channel))
		_add_undo_method(_restore_channel, before)
		_undo.commit_action(false)
	layers_changed.emit()
	image_changed.emit()
	changed.emit()


func _restore_channel(snapshot: Dictionary) -> void:
	var mat: StandardMaterial3D = snapshot["material"]
	var ch: int = snapshot["channel"]
	var state := _state_for_material(mat, ch)
	_decode_channel(state, snapshot["data"])
	_render_channel(mat, ch, state)
	if not snapshot["texture_present"]:
		_set_channel_texture(ch, null, mat)
	if ch == Channel.EMISSION:
		mat.emission_enabled = snapshot["emission_enabled"]
		mat.emission = snapshot["emission"]
		mat.emission_operator = snapshot["emission_operator"]
		mat.emission_texture = snapshot["emission_texture"]
	if ch == Channel.ROUGHNESS:
		mat.roughness = snapshot["roughness"]
		mat.roughness_texture = snapshot["roughness_texture"]
		mat.roughness_texture_channel = snapshot["roughness_component"]
	_persist_channel(mat, ch, state)
	state.dirty = _channel_differs_from_saved(mat, ch, state)
	_refresh_material_dirty(mat)
	if mat == _material and ch == channel:
		_image = state.base_image
		_texture = state.texture
		_load_channel_overlay(ch)
	layers_changed.emit()
	image_changed.emit()
	changed.emit()


func _switch_channel(from_ch: int, to_ch: int) -> void:
	_save_current_overlay_to_channel(from_ch)
	_bind_channel_texture(to_ch)
	_report("Switched to %s channel." % channel_name(to_ch))


func _save_current_overlay_to_channel(ch: int) -> void:
	if _overlay_image == null or _overlay_image.is_empty():
		return
	var state := channel_state(ch)
	if state.layers.is_empty():
		state.add_layer("Layer 1")
	var active := state.active_layer()
	if active != null:
		active.image = _overlay_image.duplicate()


func _load_channel_overlay(ch: int) -> void:
	var state := channel_state(ch)
	var active := state.active_layer()
	if active != null and active.image != null and not active.image.is_empty():
		_overlay_image = active.image.duplicate()
		_overlay_dirty = not active.is_empty()
	else:
		_ensure_overlay()
		_clear_overlay()


func _bind_channel_texture(ch: int) -> void:
	if _material == null:
		return
	var state := channel_state(ch)
	_image = state.base_image
	_load_channel_overlay(ch)
	_render_channel(_material, ch, state, false)
	_texture = state.texture
	image_changed.emit()


func _roughness_image_from_material(mat: StandardMaterial3D) -> Image:
	if mat == null:
		return _filled_gray(DEFAULT_SIZE, mat.roughness if mat != null else 0.5)
	if mat.roughness_texture != null:
		var source := _cpu_image_from_texture(mat.roughness_texture)
		if source != null and not source.is_empty():
			# Layers store effective roughness, independent of imported channel/scalar settings.
			var result := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
			for y in source.get_height():
				for x in source.get_width():
					var pixel := source.get_pixel(x, y)
					var value: float
					match mat.roughness_texture_channel:
						BaseMaterial3D.TEXTURE_CHANNEL_RED: value = pixel.r
						BaseMaterial3D.TEXTURE_CHANNEL_GREEN: value = pixel.g
						BaseMaterial3D.TEXTURE_CHANNEL_BLUE: value = pixel.b
						BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: value = pixel.a
						BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: value = (pixel.r + pixel.g + pixel.b) / 3.0
					value *= mat.roughness
					result.set_pixel(x, y, Color(value, value, value, 1.0))
			return result
	return _filled_gray(_new_texture_size(), mat.roughness)


func _emission_image_from_material(mat: StandardMaterial3D) -> Image:
	if mat == null:
		return _filled(DEFAULT_SIZE, Color.BLACK)
	if mat.emission_texture is ImageTexture:
		var live: Image = _cpu_image_from_texture(mat.emission_texture)
		if live != null and not live.is_empty():
			return live
	if mat.emission_texture != null:
		var from_tex: Image = _cpu_image_from_texture(mat.emission_texture)
		if from_tex != null and not from_tex.is_empty():
			return from_tex
	if mat.emission_enabled:
		return _filled(_new_texture_size(), mat.emission)
	return _filled(_new_texture_size(), Color.BLACK)


func _filled_gray(size: int, value: float) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var gray := Color(value, value, value, 1.0)
	img.fill(gray)
	return img


func channel_has_texture(ch: int) -> bool:
	if _material == null:
		return false
	match ch:
		Channel.ALBEDO:
			return _material.albedo_texture != null
		Channel.ROUGHNESS:
			return _material.roughness_texture != null
		Channel.EMISSION:
			return _material.emission_enabled and _material.emission_texture != null
		_:
			return false


func can_make_unique_channel(ch: int = -1) -> bool:
	var target_ch := ch if ch >= 0 else channel
	if _selection == null or _selection.objects.size() != 1 or _selection.ids.is_empty():
		return false
	if tool == Tool.MATERIAL_UV and _brush_material != null:
		return true
	var common := _common_selected_material()
	if common.is_empty():
		return false
	return true


func make_unique_channel(ch: int = -1) -> int:
	var target_ch := ch if ch >= 0 else channel
	if not can_make_unique():
		_report("Cannot make unique for %s channel." % channel_name(target_ch))
		return -1
	var slot := make_unique()
	if slot >= 0 and target_ch != Channel.ALBEDO:
		_ensure_channel_texture(target_ch)
	return slot


func _ensure_channel_texture(ch: int) -> void:
	if _material == null or not _is_unique(_material):
		return
	var size := _new_texture_size()
	if _image != null and not _image.is_empty():
		size = _image.get_width()
	match ch:
		Channel.ROUGHNESS:
			if _material.roughness_texture == null:
				var img := _filled_gray(size, _material.roughness)
				img.generate_mipmaps()
				var tex := ImageTexture.create_from_image(img)
				_set_channel_texture(ch, tex)
		Channel.EMISSION:
			if _material.emission_texture == null:
				var img := _filled(size, _material.emission if _material.emission_enabled else Color.BLACK)
				img.generate_mipmaps()
				var tex := ImageTexture.create_from_image(img)
				_set_channel_texture(ch, tex)


func layer_count() -> int:
	var state := channel_state(channel)
	return state.layers.size()


func active_layer_index() -> int:
	var state := channel_state(channel)
	return state.active_layer_index


func set_active_layer(index: int) -> void:
	var state := channel_state(channel)
	if index < 0 or index >= state.layers.size() or index == state.active_layer_index:
		return
	cancel_stroke()
	_save_current_overlay_to_channel(channel)
	state.active_layer_index = index
	_load_channel_overlay(channel)
	_persist_channel(_material, channel, state)
	layers_changed.emit()
	changed.emit()


func layer_info(index: int) -> Dictionary:
	var state := channel_state(channel)
	if index < 0 or index >= state.layers.size():
		return {}
	var layer := state.layers[index]
	return {
		"name": layer.name,
		"visible": layer.visible,
		"opacity": layer.opacity,
		"is_empty": layer.is_empty()
	}


func all_layers_info() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state := channel_state(channel)
	for i in state.layers.size():
		var layer := state.layers[i]
		result.append({
			"index": i,
			"name": layer.name,
			"visible": layer.visible,
			"opacity": layer.opacity,
			"is_empty": layer.is_empty(),
			"active": i == state.active_layer_index
		})
	return result


func add_layer(layer_name: String = "") -> int:
	cancel_stroke()
	_save_current_overlay_to_channel(channel)
	var before := _snapshot_channel(_material, channel)
	var state := channel_state(channel)
	var index := state.add_layer(layer_name)
	_load_channel_overlay(channel)
	_commit_channel_edit("Slab Add Paint Layer", before)
	_report("Added %s to %s." % [state.layers[index].name, channel_name(channel)])
	return index


func remove_layer(index: int = -1) -> bool:
	var state := channel_state(channel)
	var target_index := index if index >= 0 else state.active_layer_index
	if state.layers.size() <= 1 or target_index < 0 or target_index >= state.layers.size():
		_report("Cannot delete the last layer.")
		return false
	cancel_stroke()
	_save_current_overlay_to_channel(channel)
	var before := _snapshot_channel(_material, channel)
	state.remove_layer(target_index)
	_load_channel_overlay(channel)
	_commit_channel_edit("Slab Delete Paint Layer", before)
	return true


func set_layer_visible(index: int, visible: bool) -> void:
	var state := channel_state(channel)
	if index < 0 or index >= state.layers.size() or state.layers[index].visible == visible:
		return
	_save_current_overlay_to_channel(channel)
	var before := _snapshot_channel(_material, channel)
	state.layers[index].visible = visible
	_commit_channel_edit("Slab Paint Layer Visibility", before)


func set_layer_opacity(index: int, opacity: float) -> void:
	var state := channel_state(channel)
	opacity = clampf(opacity, 0.0, 1.0)
	if index < 0 or index >= state.layers.size() or is_equal_approx(state.layers[index].opacity, opacity):
		return
	_save_current_overlay_to_channel(channel)
	var before := _snapshot_channel(_material, channel)
	state.layers[index].opacity = opacity
	_commit_channel_edit("Slab Paint Layer Opacity", before)


func set_layer_name(index: int, new_name: String) -> void:
	var state := channel_state(channel)
	if index < 0 or index >= state.layers.size() or state.layers[index].name == new_name:
		return
	_save_current_overlay_to_channel(channel)
	var before := _snapshot_channel(_material, channel)
	state.layers[index].name = new_name
	_commit_channel_edit("Slab Rename Paint Layer", before)


func has_channel_overlay_strokes() -> bool:
	var state := channel_state(channel)
	return state.has_visible_strokes()


func cancel_stroke() -> void:
	if not stroke_active:
		return
	stroke_active = false
	_restore_channel(_stroke_state)
	_report("Paint stroke cancelled.")

func save_png(path: String) -> int:
	if _image == null:
		_report("Nothing to save.")
		return ERR_DOES_NOT_EXIST
	var state := channel_state(channel)
	var output := state.composite_all_layers(state.base_image)
	_ensure_dir(path.get_base_dir())
	var err: int = output.save_png(path)
	if err != OK:
		_report("Could not save %s." % path)
		return err
	if has_channel_overlay_strokes():
		flatten()
	if _material != null:
		_material.set_meta(_png_meta(channel), path)
		_material.resource_local_to_scene = true
		_persist_channel(_material, channel, channel_state(channel))
		_mark_dirty(_material, false)
		var scene_root: Node = _owning_scene_root(_solid)
		_pending_scene_saves[_material.get_instance_id()] = {"root": weakref(scene_root) if scene_root != null else null}
	else:
		dirty = false
	_report("Texture saved to %s. The scene still needs saving." % path)
	changed.emit()
	return OK


func default_save_path(solid: Node3D = null) -> String:
	var node: Node3D = solid if solid != null else (_selection.solid if _selection != null else null)
	var name: String = node.name if node != null else "solid"
	var suffix := "" if channel == Channel.ALBEDO else "_%s" % channel_name(channel).to_lower()
	return "res://slab_paint/%s_m%d%s.png" % [name.validate_filename(), maxi(0, _slot), suffix]


func handle_3d(camera: Camera3D, event: InputEvent, world_root: Node) -> int:
	if not active:
		return VERDICT_PASS
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_left_gesture_owned = false
			if stroke_active:
				cancel_stroke()
			elif uv_drag_active:
				cancel_uv_drag()
			else:
				exit()
			return VERDICT_STOP
		return VERDICT_PASS
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		return VERDICT_PASS
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return VERDICT_PASS
	var hit: Dictionary = {}
	if world_root != null and camera != null:
		hit = SlabPick.pick_world_hit(world_root, camera, event.position)
	if event is InputEventMouseButton and event.pressed:
		_left_gesture_owned = not event.alt_pressed and not event.shift_pressed and not event.ctrl_pressed and not event.meta_pressed
		if hit.is_empty():
			return VERDICT_STOP if _left_gesture_owned else VERDICT_PASS
		var solid: Node3D = hit.get("solid")
		var face: int = int(hit.get("id", 0))
		if not SlabPaintUv.faces_camera(solid, face, camera, hit["world"]):
			_report("Ignored a backface.")
			return VERDICT_STOP
		if tool == Tool.MATERIAL_UV:
			if event.alt_pressed:
				sample_face(solid, face)
			else:
				var brush := _brush_material
				if brush == null:
					var owned_gesture := _left_gesture_owned
					_focus_target(solid)
					_selection.set_objects([solid])
					_selection.set_ids(PackedInt64Array([face]))
					_left_gesture_owned = owned_gesture
					_adopt_selection_material()
					if _brush_material != null:
						_report("Selected face and adopted %s as the Brush." % material_label(_brush_material, _actions.material_slot))
					else:
						_report("Selected face uses the default material. Choose a Brush to paint it.")
					return VERDICT_STOP
				_focus_target(solid)
				_selection.set_objects([solid])
				_selection.set_ids(PackedInt64Array([face]))
				pick_material(brush)
			return VERDICT_STOP
		var target: Dictionary = _face_paint_target(solid, face)
		if target.is_empty():
			return VERDICT_STOP
		_focus_target(solid)
		_selection.set_objects([solid])
		_selection.set_ids(PackedInt64Array([face]))
		_actions.material_slot = int(target["slot"])
		_bind_from_selection()
		if not begin_stroke():
			return VERDICT_STOP
		dab_uv(SlabPaintUv.point_uv(solid, face, hit["local"]))
		return VERDICT_STOP
	if event is InputEventMouseButton and not event.pressed:
		if stroke_active:
			end_stroke()
			_left_gesture_owned = false
			return VERDICT_STOP
		var owned := _left_gesture_owned
		_left_gesture_owned = false
		return VERDICT_STOP if owned else VERDICT_PASS
	if event is InputEventMouseMotion:
		_sync_brush_preview(world_root, camera, event.position)
	if event is InputEventMouseMotion and stroke_active:
		if hit.is_empty():
			_last_pixel = Vector2(-1, -1)
			return VERDICT_STOP
		var solid: Node3D = hit.get("solid")
		var face: int = int(hit.get("id", 0))
		if not SlabPaintUv.faces_camera(solid, face, camera, hit["world"]):
			_last_pixel = Vector2(-1, -1)
			return VERDICT_STOP
		var target: Dictionary = _face_paint_target(solid, face)
		if target.is_empty() or target["material"] != _stroke_material:
			_last_pixel = Vector2(-1, -1)
			return VERDICT_STOP
		dab_uv(SlabPaintUv.point_uv(solid, face, hit["local"]))
		return VERDICT_STOP
	return VERDICT_STOP if _left_gesture_owned else VERDICT_PASS


func _focus_target(solid: Node3D) -> void:
	if _host != null and solid != null:
		_host.focus_solid(solid, false)


func _create_undo_action(label: String, solid: Node3D) -> void:
	if _undo is EditorUndoRedoManager:
		_undo.create_action(label, UndoRedo.MERGE_DISABLE, solid)
	else:
		_undo.create_action(label, UndoRedo.MERGE_DISABLE)


func _add_do_method(method: Callable, arg: Variant) -> void:
	if _undo is EditorUndoRedoManager:
		_undo.add_do_method(method.get_object(), method.get_method(), arg)
	else:
		_undo.add_do_method(method.bind(arg))


func _add_undo_method(method: Callable, arg: Variant) -> void:
	if _undo is EditorUndoRedoManager:
		_undo.add_undo_method(method.get_object(), method.get_method(), arg)
	else:
		_undo.add_undo_method(method.bind(arg))


func _face_paint_target(solid: Node3D, face: int) -> Dictionary:
	if solid == null:
		return {}
	var attrs: Dictionary = solid.call("face_uv", face)
	if attrs.is_empty():
		return {}
	var slot: int = int(attrs.get("slot", -1))
	var mats: Array = solid.get("materials")
	if slot < 0 or slot >= mats.size() or not (mats[slot] is StandardMaterial3D):
		return {}
	return {"slot": slot, "material": mats[slot]}


func _dab_at(pixel: Vector2) -> void:
	_ensure_overlay()
	if _overlay_image == null or _overlay_image.is_empty():
		return
	if _last_pixel.x < 0.0:
		SlabPaintRaster.stamp(_overlay_image, pixel, brush_radius, brush_color, brush_opacity)
	else:
		SlabPaintRaster.stroke(_overlay_image, _last_pixel, pixel, brush_radius, brush_color, brush_opacity)
	_last_pixel = pixel
	_overlay_dirty = true
	_composite_overlay()


func rebind() -> void:
	cancel_stroke()
	cancel_uv_drag()
	if _selection != null and _selection.solid != null:
		_actions.clamp_material_slot()
		var mats: Array = _selection.solid.get("materials")
		var slot: int = _actions.material_slot
		_set_brush_material(mats[slot] if slot >= 0 and slot < mats.size() and mats[slot] is StandardMaterial3D else null)
	if tool == Tool.MATERIAL_UV and _brush_material == null:
		_bind_empty_selection_target()
	else:
		_bind_from_selection()
	layers_changed.emit()


func _bind_brush_to_selection() -> void:
	if _brush_material == null or _selection == null or _selection.solid == null:
		_bind_empty_selection_target()
		return
	var mats: Array = _selection.solid.get("materials")
	for i in mats.size():
		if mats[i] == _brush_material:
			_actions.material_slot = i
			_bind_from_selection()
			return
	_solid = _selection.solid
	_slot = -1
	_material = _brush_material
	_image = _image_from_material(_brush_material)
	_sync_texture_resolution_from_artwork(_brush_material, _image)
	_texture = _brush_material.albedo_texture as ImageTexture
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
	dirty = _is_dirty(_material)
	changed.emit()


func _bind_pixel_selection() -> void:
	var common := _common_selected_material()
	if common.is_empty() or not (common.get("material") is StandardMaterial3D):
		_bind_empty_selection_target()
		return
	_actions.material_slot = int(common["slot"])
	_bind_from_selection()


func _bind_empty_selection_target() -> void:
	_sync_uv_from_selection()
	_solid = _selection.solid if _selection != null else null
	_slot = -1
	_material = null
	_overlay_image = null
	_overlay_dirty = false
	_image = null
	_texture = null
	dirty = false
	_hide_brush()
	changed.emit()


func _bind_from_selection() -> void:
	for material_id: int in _material_states.keys():
		var entry: Dictionary = _material_states[material_id]
		if (entry["material"] as WeakRef).get_ref() == null:
			_material_states.erase(material_id)
			_dirty_ids.erase(material_id)
	if _selection == null or _selection.solid == null:
		_bind_empty_selection_target()
		return
	_sync_uv_from_selection()
	if _actions != null:
		_actions.clamp_material_slot()
		_slot = _actions.material_slot
	_solid = _selection.solid
	var mats: Array = _solid.get("materials")
	var src: Variant = mats[_slot] if _slot >= 0 and _slot < mats.size() else null
	if src is StandardMaterial3D:
		_material = src
		if not _is_unique(src):
			_material_states.erase(src.get_instance_id())
		_bind_channel_texture(channel)
		_sync_texture_resolution_from_artwork(src, _image)
		dirty = _is_dirty(_material)
	else:
		_material = null
		_image = _filled(DEFAULT_SIZE, Color(0.72, 0.55, 0.38))
		_texture = ImageTexture.create_from_image(_image)
		_overlay_image = null
		_overlay_dirty = false
		dirty = false
	changed.emit()


func _sync_uv_from_selection() -> void:
	if _actions == null or _selection == null or _selection.solid == null or _selection.ids.is_empty():
		return
	var attrs: Dictionary = _selection.solid.call("face_uv", _selection.ids[0])
	if attrs.is_empty():
		return
	_actions.uv_scale = attrs.get("scale", Vector2.ONE)
	_actions.uv_offset = attrs.get("offset", Vector2.ZERO)
	_actions.uv_rotation_degrees = rad_to_deg(float(attrs.get("rotation", 0.0)))


func _ensure_editable() -> bool:
	if _selection == null or _selection.solid == null:
		_report("Select a solid to paint.")
		return false
	if _image == null or _texture == null:
		_bind_from_selection()
	if _material == null or not _is_unique(_material):
		_report("Make Unique before painting so shared tiles are not overwritten.")
		return false
	if _image.get_format() != Image.FORMAT_RGBA8:
		_image.convert(Image.FORMAT_RGBA8)
		_texture.set_image(_image)
		_set_channel_texture(channel, _texture)
	return true


func _is_unique(mat: StandardMaterial3D) -> bool:
	return mat != null and bool(mat.get_meta(OWNED_META, false))


func _mark_dirty(mat: StandardMaterial3D, value: bool) -> void:
	if mat == null:
		return
	_state_for_material(mat, channel).dirty = value
	_refresh_material_dirty(mat)


func _refresh_material_dirty(mat: StandardMaterial3D) -> void:
	var any_dirty := false
	for state: ChannelState in _material_states.get(mat.get_instance_id(), {}).get("channels", {}).values():
		any_dirty = any_dirty or state.dirty
	if any_dirty:
		_dirty_ids[mat.get_instance_id()] = true
	else:
		_dirty_ids.erase(mat.get_instance_id())
	if mat == _material:
		dirty = any_dirty


func _is_dirty(mat: StandardMaterial3D) -> bool:
	return mat != null and _dirty_ids.has(mat.get_instance_id())


func _duplicate_material(src: Variant) -> StandardMaterial3D:
	if src is StandardMaterial3D:
		var copy: Resource = src.duplicate()
		if copy is StandardMaterial3D:
			return copy
	return StandardMaterial3D.new()


static func material_label(mat: Variant, slot: int) -> String:
	if mat is StandardMaterial3D:
		var named: String = str(mat.resource_name).strip_edges()
		if named != "":
			return named
		var path: String = str(mat.resource_path)
		if path != "" and not path.contains("::"):
			return path.get_file().get_basename()
	return "Material %d" % (slot + 1) if slot >= 0 else "New material"


func pick_material(mat: StandardMaterial3D) -> void:
	if _selection == null or _selection.solid == null or mat == null:
		return
	_set_brush_material(mat)
	var solid: Node3D = _selection.solid
	var before_mats: Array = (solid.get("materials") as Array).duplicate()
	var before_data: PackedByteArray = solid.get("data")
	var prev_slot: int = _actions.material_slot
	var mats: Array = before_mats.duplicate()
	var slot: int = mats.find(mat)
	if slot < 0:
		# Slot 0 is the implicit material of every newly-created face. Keep it
		# empty when importing the first material so only the selected faces
		# receive the resource.
		if mats.is_empty():
			mats.append(null)
		mats.append(mat)
		slot = mats.size() - 1
	solid.set("materials", mats)
	_actions.material_slot = slot
	if not _selection.ids.is_empty():
		solid.call("set_face_material", _selection.ids, slot)
	var after_data: PackedByteArray = solid.get("data")
	if _undo != null and (mats != before_mats or after_data != before_data or slot != prev_slot):
		_create_undo_action("Slab Pick Material", solid)
		_undo.add_do_property(solid, "materials", mats)
		_undo.add_undo_property(solid, "materials", before_mats)
		_undo.add_do_property(solid, "data", after_data)
		_undo.add_undo_property(solid, "data", before_data)
		_undo.add_do_property(_actions, "material_slot", slot)
		_undo.add_undo_property(_actions, "material_slot", prev_slot)
		_undo.commit_action(false)
	_bind_from_selection()
	_report("Using %s." % material_label(mat, slot))


func save_status() -> String:
	if dirty:
		return "Unsaved paint"
	if _material != null and _pending_scene_saves.has(_material.get_instance_id()):
		return "Texture saved. Scene still needs saving."
	return ""


func scene_saved(path: String, saved_root: Node = null) -> void:
	var saved_path: String = path.simplify_path()
	var cleared := false
	for material_id: Variant in _pending_scene_saves.keys():
		var pending: Dictionary = _pending_scene_saves[material_id]
		var root_ref: WeakRef = pending.get("root")
		var owner_root: Node = root_ref.get_ref() if root_ref != null else null
		if owner_root == null:
			_pending_scene_saves.erase(material_id)
			continue
		if saved_root != null and owner_root != saved_root:
			continue
		# EditorPlugin.scene_saved fires after Save As has updated the root path.
		# The explicit root is used by non-editor hosts and focused tests.
		if saved_root == null and str(owner_root.scene_file_path).simplify_path() != saved_path:
			continue
		_pending_scene_saves.erase(material_id)
		cleared = true
	if cleared:
		_report("")
		changed.emit()


func _owning_scene_root(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if _host != null:
		var hosted: Node = _host.scene_root()
		if hosted != null and (hosted == node or hosted.is_ancestor_of(node)):
			return hosted
	var current: Node = node
	var tree: SceneTree = current.get_tree()
	while current.get_parent() != null and (tree == null or current.get_parent() != tree.root):
		current = current.get_parent()
	return current


func _bind_editable(solid: Node3D, slot: int, mat: StandardMaterial3D, img: Image, tex: ImageTexture) -> void:
	_solid = solid
	_slot = slot
	_material = mat
	mat.albedo_texture = tex
	var state := _state_for_material(mat, Channel.ALBEDO)
	if not mat.has_meta(LAYERS_META):
		state.base_image = img
	_bind_channel_texture(channel)
	if _actions != null and _image != null:
		_actions.uv_texture_resolution = _image.get_width()


func _sync_texture_resolution_from_artwork(mat: StandardMaterial3D, img: Image) -> void:
	if _actions != null and mat != null and mat.albedo_texture != null and img != null and not img.is_empty():
		_actions.uv_texture_resolution = img.get_width()


func _image_from_material(src: Variant, blank_size: int = DEFAULT_SIZE) -> Image:
	if src is StandardMaterial3D and src.albedo_texture is ImageTexture:
		var live: Image = _cpu_image_from_texture(src.albedo_texture)
		if live != null and not live.is_empty():
			return live
	if src is StandardMaterial3D and src.has_meta(PNG_META) and not _is_dirty(src):
		var path: String = str(src.get_meta(PNG_META))
		if path != "" and FileAccess.file_exists(path):
			var loaded := Image.new()
			if loaded.load(path) == OK:
				return SlabPaintRaster.clone_rgba(loaded)
	if src is StandardMaterial3D and src.albedo_texture != null:
		var from_tex: Image = _cpu_image_from_texture(src.albedo_texture)
		if from_tex != null and not from_tex.is_empty():
			return from_tex
	var color := Color(0.72, 0.55, 0.38)
	if src is StandardMaterial3D:
		color = src.albedo_color
	return _filled(clampi(blank_size, 16, 16384), color)


func _new_texture_size() -> int:
	if _actions != null:
		return clampi(int(_actions.uv_texture_resolution), 16, 16384)
	return DEFAULT_SIZE


func cpu_image_from_texture(tex: Texture2D) -> Image:
	return _cpu_image_from_texture(tex)


func _cpu_image_from_texture(tex: Texture2D) -> Image:
	if tex == null:
		return null
	# ImageTexture owns CPU pixels. Black, dark, and transparent art is valid.
	if tex is ImageTexture:
		var owned: Image = tex.get_image()
		if owned == null or owned.is_empty():
			return null
		return SlabPaintRaster.clone_rgba(owned)
	# CompressedTexture2D.get_image() in the editor is not the GPU texels: it is
	# often empty, still compressed, or an uncompressed zero buffer. Read the RID.
	var gpu: Image = RenderingServer.texture_2d_get(tex.get_rid())
	if gpu != null and not gpu.is_empty():
		return SlabPaintRaster.clone_rgba(gpu)
	var got: Image = tex.get_image() if tex.has_method("get_image") else null
	if got == null or got.is_empty():
		return null
	return SlabPaintRaster.clone_rgba(got)


func _filled(size: int, color: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img


func _common_selected_material() -> Dictionary:
	if _selection == null or _selection.objects.size() != 1 or _selection.solid == null or _selection.ids.is_empty():
		return {}
	var mats: Array = _selection.solid.get("materials")
	var first_slot := -1
	var first_material: Variant = null
	for face in _selection.ids:
		var attrs: Dictionary = _selection.solid.call("face_uv", face)
		if attrs.is_empty(): return {}
		var slot := int(attrs.get("slot", 0))
		var mat: Variant = mats[slot] if slot >= 0 and slot < mats.size() else null
		if first_slot < 0:
			first_slot = slot
			first_material = mat
		elif mat != first_material:
			return {}
	return {"slot": first_slot, "material": first_material}


func _adopt_selection_material() -> void:
	var common := _common_selected_material()
	_set_brush_material(common.get("material") as StandardMaterial3D if common.get("material") is StandardMaterial3D else null)
	if _brush_material != null:
		_actions.material_slot = int(common["slot"])
		_bind_from_selection()
	else:
		_bind_empty_selection_target()


func _on_selection_changed() -> void:
	_left_gesture_owned = false
	if not active:
		return
	if _selection.mode != 3:
		exit()
		return
	cancel_stroke()
	cancel_uv_drag()
	_lock_transform_gizmo()
	if tool == Tool.PIXEL:
		_bind_pixel_selection()
	else:
		_bind_brush_to_selection()


func _on_mode_requested() -> void:
	if active:
		exit()


func _on_undo_version() -> void:
	if not active or _selection == null or _selection.solid == null:
		return
	if tool == Tool.PIXEL:
		_bind_pixel_selection()
	else:
		_bind_brush_to_selection()
	_sync_dirty_from_saved()


func _sync_dirty_from_saved() -> void:
	if _material == null or not _is_unique(_material):
		return
	for ch: int in _material_states.get(_material.get_instance_id(), {}).get("channels", {}):
		var state := _state_for_material(_material, ch)
		state.dirty = _channel_differs_from_saved(_material, ch, state)
	_refresh_material_dirty(_material)


func _png_meta(ch: int) -> String:
	return PNG_META if ch == Channel.ALBEDO else "%s_%s" % [PNG_META, channel_name(ch).to_lower()]


func _channel_differs_from_saved(mat: StandardMaterial3D, ch: int, state: ChannelState) -> bool:
	var path: String = str(mat.get_meta(_png_meta(ch), ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return state.dirty
	var saved := Image.load_from_file(path)
	if saved == null or saved.is_empty():
		return true
	# A PNG contains the base; editable overlay changes remain unsaved.
	return saved.save_png_to_buffer() != state.base_image.save_png_to_buffer() or state.has_visible_strokes()


func _ensure_dir(dir: String) -> void:
	if dir == "":
		return
	if dir.begins_with("res://") or dir.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	else:
		DirAccess.make_dir_recursive_absolute(dir)


func _sync_brush_preview(world_root: Node, camera: Camera3D, screen: Vector2) -> void:
	if not active or tool != Tool.PIXEL or camera == null:
		_hide_brush()
		return
	var hit: Dictionary = {}
	if world_root != null:
		hit = SlabPick.pick_world_hit(world_root, camera, screen)
	if hit.is_empty() or not hit.has("world"):
		_hide_brush()
		return
	var solid: Node3D = hit.get("solid")
	var face: int = int(hit.get("id", 0))
	if solid == null or not SlabPaintUv.faces_camera(solid, face, camera, hit["world"]):
		_hide_brush()
		return
	var target: Dictionary = _face_paint_target(solid, face)
	var target_material: StandardMaterial3D = target.get("material")
	if target_material == null or not _is_unique(target_material):
		_hide_brush()
		return
	if stroke_active and target_material != _stroke_material:
		_hide_brush()
		return
	if _brush_node == null or not is_instance_valid(_brush_node) or _brush_node.get_parent() != solid:
		_free_brush()
		_brush_node = MeshInstance3D.new()
		_brush_node.name = "SlabPaintBrush"
		_brush_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := SphereMesh.new()
		mesh.radial_segments = 12
		mesh.rings = 6
		_brush_node.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.35, 0.1, 0.45)
		mat.no_depth_test = true
		_brush_node.material_override = mat
		solid.add_child(_brush_node)
	var texture_width: int = target_material.albedo_texture.get_width() if target_material.albedo_texture != null else DEFAULT_SIZE
	var radius: float = _brush_world_radius(solid, face, texture_width)
	var sphere: SphereMesh = _brush_node.mesh
	sphere.radius = radius
	sphere.height = radius * 2.0
	_brush_node.global_position = hit["world"]
	_brush_node.visible = true


func _brush_world_radius(solid: Node3D, face: int, texture_width: int = 0) -> float:
	var corners: PackedVector3Array = solid.face_corners(face)
	if corners.size() < 2:
		return 0.04
	var uv0: Vector2 = SlabPaintUv.point_uv(solid, face, corners[0])
	var uv1: Vector2 = SlabPaintUv.point_uv(solid, face, corners[1])
	var width: int = texture_width if texture_width > 0 else (_image.get_width() if _image != null and not _image.is_empty() else DEFAULT_SIZE)
	var uv_px: float = uv0.distance_to(uv1) * float(width)
	var world: float = corners[0].distance_to(corners[1])
	if uv_px < 0.001:
		return 0.04
	return maxf(0.012, brush_radius * (world / uv_px))


func _hide_brush() -> void:
	if _brush_node != null and is_instance_valid(_brush_node):
		_brush_node.visible = false


func _free_brush() -> void:
	if _brush_node != null and is_instance_valid(_brush_node):
		_brush_node.queue_free()
	_brush_node = null


func _lock_transform_gizmo() -> void:
	var target: Node3D = _selection.solid if _selection != null else null
	if target == _locked_solid:
		return
	_unlock_transform_gizmo()
	if target == null or not is_instance_valid(target):
		return
	_locked_solid = target
	_had_prior_lock = _locked_solid.has_meta("_edit_lock_") and _locked_solid.get_meta("_edit_lock_") == true
	if not _had_prior_lock:
		_locked_solid.set_meta("_edit_lock_", true)
	if _host != null and _host.has_method("refresh_native_selection"):
		_host.refresh_native_selection(_locked_solid)


func _unlock_transform_gizmo() -> void:
	if _locked_solid == null:
		return
	var solid: Node3D = _locked_solid
	var restore_lock: bool = _had_prior_lock
	_locked_solid = null
	_had_prior_lock = false
	if not is_instance_valid(solid):
		return
	if restore_lock:
		pass
	elif solid.has_meta("_edit_lock_"):
		solid.remove_meta("_edit_lock_")
	if _host != null and _host.has_method("refresh_native_selection"):
		_host.refresh_native_selection(solid)


func _report(text: String) -> void:
	reported.emit(text)
