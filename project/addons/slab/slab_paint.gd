@tool
extends RefCounted

const SlabPaintUv := preload("res://addons/slab/slab_paint_uv.gd")
const SlabPaintRaster := preload("res://addons/slab/slab_paint_raster.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")

signal changed
signal image_changed
signal reported(text: String)

enum Tool { MATERIAL_UV, PIXEL }

const PNG_META := "slab_paint_png"
const OWNED_META := "slab_paint_owned"
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
		active = value
		changed.emit()

var tool: int = Tool.MATERIAL_UV:
	set(value):
		if value == tool:
			return
		cancel_stroke()
		tool = value
		changed.emit()

var brush_color := Color(0.86, 0.18, 0.16)
var brush_radius: float = 8.0
var brush_opacity: float = 1.0
var dirty: bool = false
var stroke_active: bool = false

var _undo: Object = null
var _selection: RefCounted
var _actions: RefCounted
var _image: Image
var _texture: ImageTexture
var _material: StandardMaterial3D
var _solid: Node3D
var _slot: int = -1
var _stroke_before := PackedByteArray()
var _stroke_material: StandardMaterial3D
var _stroke_texture: ImageTexture
var _last_pixel := Vector2(-1, -1)
var _uv_offset_start := Vector2.ZERO
var _uv_scale_start := Vector2.ONE
var _uv_rotation_start := 0.0
var _uv_before_data := PackedByteArray()
var _brush_node: MeshInstance3D
var _dirty_ids: Dictionary = {}


func bind(selection: RefCounted, actions: RefCounted, undo: Object) -> void:
	if _undo != null and _undo.has_signal("version_changed"):
		if _undo.version_changed.is_connected(_on_undo_version):
			_undo.version_changed.disconnect(_on_undo_version)
	_selection = selection
	_actions = actions
	_undo = undo
	if _selection != null and _selection.has_signal("changed"):
		if not _selection.changed.is_connected(_on_selection_changed):
			_selection.changed.connect(_on_selection_changed)
	if _undo != null and _undo.has_signal("version_changed"):
		if not _undo.version_changed.is_connected(_on_undo_version):
			_undo.version_changed.connect(_on_undo_version)


func enter() -> void:
	active = true
	if _selection != null:
		_selection.mode = 3
	_bind_from_selection()
	_report("Surface Paint. Material/UV places textures; Pixel paints albedo.")


func exit() -> void:
	cancel_stroke()
	_free_brush()
	active = false
	_report("Surface Paint closed.")


func toggle() -> void:
	if active:
		exit()
	else:
		enter()


func image() -> Image:
	return _image


func texture() -> Texture2D:
	return _texture


func material() -> StandardMaterial3D:
	return _material


func slot() -> int:
	return _slot


func is_pixel() -> bool:
	return tool == Tool.PIXEL


func can_make_unique() -> bool:
	return _selection != null and _selection.solid != null and not _selection.ids.is_empty()


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


func make_unique() -> int:
	var solid: Node3D = _selection.solid if _selection != null else null
	if solid == null:
		_report("Select a solid before Make Unique.")
		return -1
	if _selection.ids.is_empty():
		_report("Select a face, then Make Unique so the copy attaches to that face.")
		return -1
	_actions.clamp_material_slot()
	var src_slot: int = _actions.material_slot
	var before_mats: Array = (solid.get("materials") as Array).duplicate()
	var before_data: PackedByteArray = solid.get("data")
	var mats: Array = before_mats.duplicate()
	var src: Variant = mats[src_slot] if src_slot >= 0 and src_slot < mats.size() else null
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
	_actions.material_slot = new_slot
	solid.call("set_face_material", _selection.ids, new_slot)
	if _undo != null:
		_undo.create_action("Slab Make Unique Material")
		_undo.add_do_property(solid, "materials", mats)
		_undo.add_undo_property(solid, "materials", before_mats)
		_undo.add_do_property(solid, "data", solid.get("data"))
		_undo.add_undo_property(solid, "data", before_data)
		_undo.add_do_property(_actions, "material_slot", new_slot)
		_undo.add_undo_property(_actions, "material_slot", src_slot)
		_undo.commit_action(false)
	_bind_editable(solid, new_slot, copy, img, tex)
	_mark_dirty(copy, true)
	_report("Unique material %d on the selected face. Pixel paint stays on this copy." % new_slot)
	changed.emit()
	return new_slot


func assign_active_to_selection() -> void:
	if _actions != null:
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
	_selection.set_objects([solid])
	_selection.set_ids(PackedInt64Array([face]))
	_bind_from_selection()
	_report("Sampled material %d." % _actions.material_slot)


func rotate_uv_90() -> void:
	if _actions != null:
		_actions.run("uv_rotate")
		changed.emit()


func apply_uv() -> void:
	if _actions != null:
		_actions.run("uv_apply")
		changed.emit()


func reset_uv() -> void:
	if _actions != null:
		_actions.run("uv_reset")
		changed.emit()


func begin_uv_drag() -> void:
	if _selection == null or _selection.solid == null:
		return
	_uv_offset_start = _actions.uv_offset
	_uv_scale_start = _actions.uv_scale
	_uv_rotation_start = _actions.uv_rotation_degrees
	_uv_before_data = _selection.solid.get("data")


func drag_uv(delta_uv: Vector2, mode: int = UV_MOVE) -> void:
	if _selection == null or _selection.solid == null or _selection.ids.is_empty():
		return
	if mode == UV_SCALE:
		_actions.uv_scale = Vector2(
			maxf(0.05, _uv_scale_start.x * (1.0 + delta_uv.x)),
			maxf(0.05, _uv_scale_start.y * (1.0 + delta_uv.y))
		)
	elif mode == UV_ROTATE:
		_actions.uv_rotation_degrees = _uv_rotation_start + delta_uv.x * 180.0
	else:
		_actions.uv_offset = _uv_offset_start + delta_uv
	_selection.solid.call("set_face_uv", _selection.ids, _actions.uv_scale, _actions.uv_offset, deg_to_rad(_actions.uv_rotation_degrees))
	changed.emit()


func end_uv_drag() -> void:
	if _selection == null or _selection.solid == null:
		return
	var solid: Node3D = _selection.solid
	var after: PackedByteArray = solid.get("data")
	if after == _uv_before_data:
		return
	if _undo != null:
		_undo.create_action("Slab UV Place")
		_undo.add_do_property(solid, "data", after)
		_undo.add_undo_property(solid, "data", _uv_before_data)
		_undo.add_do_property(_actions, "uv_offset", _actions.uv_offset)
		_undo.add_undo_property(_actions, "uv_offset", _uv_offset_start)
		_undo.add_do_property(_actions, "uv_scale", _actions.uv_scale)
		_undo.add_undo_property(_actions, "uv_scale", _uv_scale_start)
		_undo.add_do_property(_actions, "uv_rotation_degrees", _actions.uv_rotation_degrees)
		_undo.add_undo_property(_actions, "uv_rotation_degrees", _uv_rotation_start)
		_undo.commit_action(false)


func begin_stroke() -> bool:
	if not _ensure_editable():
		return false
	stroke_active = true
	_stroke_before = _image.save_png_to_buffer()
	_stroke_material = _material
	_stroke_texture = _texture
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
	if _image == null:
		return
	var after: PackedByteArray = _image.save_png_to_buffer()
	if after == _stroke_before:
		return
	# EditorUndoRedoManager aborts on Callable.bind(PackedByteArray). Record the
	# ImageTexture swap with add_do_property, matching Make Unique.
	if _undo != null and _stroke_material != null:
		var before_img := Image.new()
		var after_img: Image = _image.duplicate()
		if before_img.load_png_from_buffer(_stroke_before) == OK:
			var before_tex := ImageTexture.create_from_image(before_img)
			var after_tex := ImageTexture.create_from_image(after_img)
			_texture = after_tex
			_stroke_material.albedo_texture = after_tex
			_undo.create_action("Slab Paint Stroke")
			_undo.add_do_property(_stroke_material, "albedo_texture", after_tex)
			_undo.add_undo_property(_stroke_material, "albedo_texture", before_tex)
			_undo.commit_action(false)
	_report("Painted albedo.")
	changed.emit()


func cancel_stroke() -> void:
	if not stroke_active:
		return
	stroke_active = false
	if not _stroke_before.is_empty():
		apply_png(_stroke_before, _stroke_material, _stroke_texture)
	_report("Paint stroke cancelled.")


func apply_png(bytes: PackedByteArray, mat: StandardMaterial3D = null, tex: ImageTexture = null) -> void:
	if bytes.is_empty():
		return
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var target_mat: StandardMaterial3D = mat if mat != null else _material
	var target_tex: ImageTexture = tex if tex != null else _texture
	if target_tex == null:
		target_tex = ImageTexture.create_from_image(img)
	else:
		target_tex.set_image(img)
	if target_mat != null:
		target_mat.albedo_texture = target_tex
		_mark_dirty(target_mat, true)
	if target_mat == _material:
		_image = img
		_texture = target_tex
		image_changed.emit()
	changed.emit()


func save_png(path: String) -> int:
	if _image == null:
		_report("Nothing to save.")
		return ERR_DOES_NOT_EXIST
	_ensure_dir(path.get_base_dir())
	var err: int = _image.save_png(path)
	if err != OK:
		_report("Could not save %s." % path)
		return err
	if _material != null:
		_material.set_meta(PNG_META, path)
		_material.resource_local_to_scene = true
		_mark_dirty(_material, false)
	else:
		dirty = false
	_report("Texture saved to %s. The scene still needs saving." % path)
	changed.emit()
	return OK


func default_save_path(solid: Node3D = null) -> String:
	var node: Node3D = solid if solid != null else (_selection.solid if _selection != null else null)
	var name: String = node.name if node != null else "solid"
	return "res://slab_paint/%s_m%d.png" % [name.validate_filename(), maxi(0, _slot)]


func handle_3d(camera: Camera3D, event: InputEvent, world_root: Node) -> int:
	if not active:
		return VERDICT_PASS
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if stroke_active:
				cancel_stroke()
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
		if hit.is_empty():
			return VERDICT_PASS
		var solid: Node3D = hit.get("solid")
		var face: int = int(hit.get("id", 0))
		if not SlabPaintUv.faces_camera(solid, face, camera, hit["world"]):
			_report("Ignored a backface.")
			return VERDICT_STOP
		if tool == Tool.MATERIAL_UV:
			if event.alt_pressed:
				sample_face(solid, face)
			else:
				_selection.set_objects([solid])
				_selection.set_ids(PackedInt64Array([face]))
				assign_active_to_selection()
			return VERDICT_STOP
		if not begin_stroke():
			return VERDICT_STOP
		dab_uv(SlabPaintUv.point_uv(solid, face, hit["local"]))
		return VERDICT_STOP
	if event is InputEventMouseButton and not event.pressed:
		if stroke_active:
			end_stroke()
			return VERDICT_STOP
		return VERDICT_PASS
	if event is InputEventMouseMotion:
		_sync_brush_preview(world_root, camera, event.position)
	if event is InputEventMouseMotion and stroke_active:
		if hit.is_empty():
			return VERDICT_STOP
		var solid: Node3D = hit.get("solid")
		var face: int = int(hit.get("id", 0))
		if not SlabPaintUv.faces_camera(solid, face, camera, hit["world"]):
			return VERDICT_STOP
		dab_uv(SlabPaintUv.point_uv(solid, face, hit["local"]))
		return VERDICT_STOP
	return VERDICT_PASS


func _dab_at(pixel: Vector2) -> void:
	if _image != null and _image.is_compressed():
		_image.decompress()
	if _image != null and _image.get_format() != Image.FORMAT_RGBA8:
		_image.convert(Image.FORMAT_RGBA8)
	if _texture == null or not (_texture is ImageTexture):
		_texture = ImageTexture.create_from_image(_image)
	if _last_pixel.x < 0.0:
		SlabPaintRaster.stamp(_image, pixel, brush_radius, brush_color, brush_opacity)
	else:
		SlabPaintRaster.stroke(_image, _last_pixel, pixel, brush_radius, brush_color, brush_opacity)
	_last_pixel = pixel
	(_texture as ImageTexture).set_image(_image)
	if _material != null:
		_material.albedo_texture = _texture
		_material.emit_changed()
	_mark_dirty(_material, true)
	image_changed.emit()


func rebind() -> void:
	_bind_from_selection()


func _bind_from_selection() -> void:
	if _selection == null or _selection.solid == null:
		_solid = null
		_material = null
		_image = null
		_texture = null
		_slot = -1
		dirty = false
		_hide_brush()
		changed.emit()
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
		_image = _image_from_material(src)
		if src.albedo_texture is ImageTexture and _is_unique(src):
			_texture = src.albedo_texture
			(_texture as ImageTexture).set_image(_image)
		else:
			_texture = ImageTexture.create_from_image(_image)
			if _is_unique(src):
				src.albedo_texture = _texture
		dirty = _is_dirty(_material)
	else:
		_material = null
		_image = _filled(DEFAULT_SIZE, Color(0.72, 0.55, 0.38))
		_texture = ImageTexture.create_from_image(_image)
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
		_material.albedo_texture = _texture
	return true


func _is_unique(mat: StandardMaterial3D) -> bool:
	return mat != null and bool(mat.get_meta(OWNED_META, false))


func _mark_dirty(mat: StandardMaterial3D, value: bool) -> void:
	if mat == null:
		return
	var id := mat.get_instance_id()
	if value:
		_dirty_ids[id] = true
	else:
		_dirty_ids.erase(id)
	if mat == _material:
		dirty = value


func _is_dirty(mat: StandardMaterial3D) -> bool:
	return mat != null and _dirty_ids.has(mat.get_instance_id())


func _duplicate_material(src: Variant) -> StandardMaterial3D:
	if src is StandardMaterial3D:
		var copy: Resource = src.duplicate()
		if copy is StandardMaterial3D:
			return copy
	return StandardMaterial3D.new()


func material_label(mat: Variant, slot: int) -> String:
	if mat is StandardMaterial3D:
		var named: String = str(mat.resource_name).strip_edges()
		if named != "":
			return named
		var path: String = str(mat.resource_path)
		if path != "":
			return path.get_file().get_basename()
	return "Slot %d" % slot


func pick_material(mat: StandardMaterial3D) -> void:
	if _selection == null or _selection.solid == null or mat == null:
		return
	var mats: Array = (_selection.solid.get("materials") as Array).duplicate()
	var slot: int = mats.find(mat)
	if slot < 0:
		mats.append(mat)
		_selection.solid.set("materials", mats)
		slot = mats.size() - 1
	_actions.material_slot = slot
	if not _selection.ids.is_empty():
		_selection.solid.call("set_face_material", _selection.ids, slot)
	_bind_from_selection()
	_report("Using %s." % material_label(mat, slot))


func save_status() -> String:
	if dirty:
		return "Unsaved paint"
	if _material != null and _material.has_meta(PNG_META) and str(_material.get_meta(PNG_META)) != "":
		return "Texture saved. Scene still needs saving."
	return ""


func _bind_editable(solid: Node3D, slot: int, mat: StandardMaterial3D, img: Image, tex: ImageTexture) -> void:
	_solid = solid
	_slot = slot
	_material = mat
	_image = img
	_texture = tex
	mat.albedo_texture = tex
	if _actions != null and img != null and not img.is_empty():
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


func _on_selection_changed() -> void:
	if not active:
		return
	cancel_stroke()
	_bind_from_selection()


func _on_undo_version() -> void:
	if not active or _selection == null or _selection.solid == null:
		return
	_bind_from_selection()
	_sync_dirty_from_saved()


func _sync_dirty_from_saved() -> void:
	if _material == null or _image == null:
		return
	if not _is_unique(_material):
		return
	if not _material.has_meta(PNG_META) or str(_material.get_meta(PNG_META)) == "":
		_mark_dirty(_material, true)
		dirty = true
		return
	var path: String = str(_material.get_meta(PNG_META))
	if not FileAccess.file_exists(path):
		_mark_dirty(_material, true)
		dirty = true
		return
	var loaded := Image.new()
	if loaded.load(path) != OK:
		_mark_dirty(_material, true)
		dirty = true
		return
	loaded = SlabPaintRaster.clone_rgba(loaded)
	var diverged: bool = loaded.get_width() != _image.get_width() or loaded.get_height() != _image.get_height() or loaded.get_data() != _image.get_data()
	_mark_dirty(_material, diverged)
	dirty = diverged


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
	var radius: float = _brush_world_radius(solid, face)
	var sphere: SphereMesh = _brush_node.mesh
	sphere.radius = radius
	sphere.height = radius * 2.0
	_brush_node.global_position = hit["world"]
	_brush_node.visible = true


func _brush_world_radius(solid: Node3D, face: int) -> float:
	var corners: PackedVector3Array = solid.face_corners(face)
	if corners.size() < 2 or _image == null or _image.is_empty():
		return 0.04
	var uv0: Vector2 = SlabPaintUv.point_uv(solid, face, corners[0])
	var uv1: Vector2 = SlabPaintUv.point_uv(solid, face, corners[1])
	var uv_px: float = uv0.distance_to(uv1) * float(_image.get_width())
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


func _report(text: String) -> void:
	reported.emit(text)
