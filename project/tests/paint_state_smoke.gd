extends SceneTree

const Paint := preload("res://addons/slab/slab_paint.gd")
const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
	print("%s %s" % ["PASS" if value else "FAIL", label])

func _fixture() -> Dictionary:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3.ONE)
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([solid.call("get_faces")[0]]))
	var actions := Actions.new(selection)
	actions.uv_texture_resolution = 32
	var undo := UndoRedo.new()
	var paint := Paint.new()
	paint.bind(selection, actions, undo)
	paint.enter()
	paint.tool = Paint.Tool.PIXEL
	paint.make_unique()
	return {"solid": solid, "selection": selection, "actions": actions, "undo": undo, "paint": paint}

func _dispose(f: Dictionary) -> void:
	f.paint.exit()
	f.undo.clear_history()
	f.undo.free()
	f.solid.free()

func _pixels(texture: Texture2D) -> PackedByteArray:
	return texture.get_image().save_png_to_buffer()

func _stroke(paint: RefCounted) -> void:
	paint.brush_opacity = 0.5
	paint.brush_radius = 3
	paint.brush_color = Color(1, 0, 0)
	_check(paint.begin_stroke(), "owned stroke starts")
	paint.dab_pixel(Vector2(16, 16))
	paint.end_stroke()

func _run() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	_stroke(paint)
	var mat: StandardMaterial3D = paint.material()
	var painted := _pixels(mat.albedo_texture)
	paint.channel = Paint.Channel.ROUGHNESS
	paint.channel = Paint.Channel.ALBEDO
	_check(_pixels(mat.albedo_texture) == painted, "channel round trip preserves exact composite pixels")
	paint.overlay_opacity = 0.5
	var faded := _pixels(mat.albedo_texture)
	_check(paint.flatten() and _pixels(mat.albedo_texture) == faded, "Flatten preserves active layer opacity pixels")
	_dispose(f)

	f = _fixture()
	paint = f.paint
	_stroke(paint)
	mat = paint.material()
	painted = _pixels(mat.albedo_texture)
	paint.add_layer()
	var path := "user://slab_paint_test/nonactive_layer.png"
	_check(paint.save_png(path) == OK, "save with an empty active layer succeeds")
	var saved := Image.load_from_file(path)
	_check(saved.save_png_to_buffer() == painted, "saved PNG contains strokes from non-active layers")
	_stroke(paint)
	paint.add_layer()
	var count: int = paint.layer_count()
	_check(paint.remove_layer() and paint.layer_count() == count - 1, "Delete Layer removes selected layer")
	f.undo.undo()
	_check(paint.layer_count() == count, "Delete Layer Undo restores complete layer stack")
	_dispose(f)

	f = _fixture()
	paint = f.paint
	mat = paint.material()
	var clean := _pixels(mat.albedo_texture)
	_stroke(paint)
	painted = _pixels(mat.albedo_texture)
	var other := _fixture()
	f.selection.set_objects([other.solid])
	f.selection.set_ids(PackedInt64Array([other.solid.call("get_faces")[0]]))
	var other_mat: StandardMaterial3D = other.paint.material()
	var other_pixels := _pixels(other_mat.albedo_texture)
	f.undo.undo()
	_check(_pixels(mat.albedo_texture) == clean, "Undo restores original material while another solid is selected")
	f.undo.redo()
	_check(_pixels(mat.albedo_texture) == painted, "Redo restores original material while another solid is selected")
	paint.overlay_opacity = 0.25
	_check(_pixels(other_mat.albedo_texture) == other_pixels, "changing empty target layer opacity cannot import another material's paint")
	f.selection.set_objects([f.solid])
	f.selection.set_ids(PackedInt64Array([f.solid.call("get_faces")[0]]))
	paint.rebind()
	_check(_pixels(mat.albedo_texture) == painted and paint.has_channel_overlay_strokes(), "returning to material restores pixels and editable layers")
	_dispose(other)
	_dispose(f)

	f = _fixture()
	paint = f.paint
	mat = paint.material()
	clean = _pixels(mat.albedo_texture)
	paint.channel = Paint.Channel.ROUGHNESS
	_stroke(paint)
	var rough := _pixels(mat.roughness_texture)
	_check(paint.resize_image(64, 48, false), "Roughness Resize succeeds")
	_check(mat.roughness_texture.get_size() == Vector2(64, 48) and _pixels(mat.albedo_texture) == clean, "Roughness Resize preserves Albedo and resizes selected channel")
	f.undo.undo()
	_check(_pixels(mat.roughness_texture) == rough and _pixels(mat.albedo_texture) == clean, "Roughness Resize Undo restores exact channel pixels")
	var rough_path: String = paint.default_save_path()
	paint.channel = Paint.Channel.ALBEDO
	_check(paint.default_save_path() != rough_path, "channels have distinct default PNG paths")
	paint.channel = Paint.Channel.ROUGHNESS
	paint.save_png("user://slab_paint_test/roughness.png")
	paint.channel = Paint.Channel.ALBEDO
	_check(_pixels(mat.albedo_texture) == clean, "saving Roughness leaves Albedo pixels intact")
	_dispose(f)
	_check_layer_persistence()
	_check_inactive_channel_undo()
	_check_unique_layers()
	_check_failed_save()
	_check_roughness_scalar()
	quit(1 if failures else 0)

func _check_layer_persistence() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	var mat: StandardMaterial3D = paint.material()
	var albedo_texture := mat.albedo_texture
	paint.channel = Paint.Channel.EMISSION
	_check(not mat.emission_enabled and mat.emission_texture == null and mat.albedo_texture == albedo_texture,
		"browsing an unused channel does not change material properties")
	_stroke(paint)
	paint.set_layer_name(0, "Hidden emission")
	paint.set_layer_visible(0, false)
	var hidden_png: PackedByteArray = paint.channel_state(Paint.Channel.EMISSION).layers[0].image.save_png_to_buffer()
	paint.add_layer("Visible emission")
	_stroke(paint)
	paint.overlay_opacity = 0.4
	var emission_pixels := _pixels(mat.emission_texture)
	paint.flatten()
	_check(_pixels(mat.emission_texture) == emission_pixels and paint.layer_count() == 2,
		"Flatten preserves rendered pixels and retains hidden artwork")
	_check(paint.channel_state(Paint.Channel.EMISSION).layers[0].image.save_png_to_buffer() == hidden_png,
		"Flatten retains exact hidden layer pixels")
	paint.channel = Paint.Channel.ALBEDO
	_stroke(paint)
	paint.set_layer_name(0, "Red albedo")
	paint.add_layer("Empty albedo")
	var albedo_pixels := _pixels(mat.albedo_texture)
	var path := "user://slab_paint_test/layers.tres"
	_check(ResourceSaver.save(mat, path) == OK, "layered material saves to disk")
	var loaded := ResourceLoader.load(path, "StandardMaterial3D", ResourceLoader.CACHE_MODE_IGNORE) as StandardMaterial3D
	var mats: Array = f.solid.get("materials")
	mats[paint.slot()] = loaded
	f.solid.set("materials", mats)
	paint.rebind()
	_check(paint.material() == loaded and paint.layer_count() == 2 and paint.active_layer_index() == 1
		and paint.layer_info(0).name == "Red albedo" and _pixels(loaded.albedo_texture) == albedo_pixels,
		"disk reload restores material pixels, named layers and active layer")
	paint.channel = Paint.Channel.EMISSION
	_check(paint.layer_count() == 2 and not paint.layer_info(0).visible
		and paint.channel_state(Paint.Channel.EMISSION).layers[0].image.save_png_to_buffer() == hidden_png
		and _pixels(loaded.emission_texture) == emission_pixels,
		"disk reload restores other channels and hidden layer pixels")
	paint.set_layer_visible(0, true)
	_check(_pixels(loaded.emission_texture) != emission_pixels, "restored hidden artwork can be shown again")
	_dispose(f)

func _check_inactive_channel_undo() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	var mat: StandardMaterial3D = paint.material()
	paint.channel = Paint.Channel.EMISSION
	_stroke(paint)
	var emission_pixels := _pixels(mat.emission_texture)
	paint.channel = Paint.Channel.ALBEDO
	var albedo_pixels := _pixels(mat.albedo_texture)
	f.undo.undo()
	_check(mat.emission_texture == null and not mat.emission_enabled and _pixels(mat.albedo_texture) == albedo_pixels,
		"Undo while another channel is selected changes only its recorded channel")
	f.undo.redo()
	_check(_pixels(mat.emission_texture) == emission_pixels and _pixels(mat.albedo_texture) == albedo_pixels,
		"Redo while another channel is selected restores exact recorded channel pixels")
	paint.channel = Paint.Channel.EMISSION
	paint.save_png("user://slab_paint_test/emission.png")
	_check(str(mat.get_meta("slab_paint_png_emission", "")) == "user://slab_paint_test/emission.png"
		and not mat.has_meta("slab_paint_png"), "Emission Save records its own path without changing Albedo's path")
	_dispose(f)

func _check_unique_layers() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	_stroke(paint)
	var original: StandardMaterial3D = paint.material()
	var original_pixels := _pixels(original.albedo_texture)
	paint.make_unique()
	_check(paint.material() != original and paint.has_channel_overlay_strokes()
		and _pixels(paint.material().albedo_texture) == original_pixels,
		"Make Unique duplicates editable layers without applying them twice")
	paint.overlay_opacity = 0.2
	_check(_pixels(original.albedo_texture) == original_pixels
		and _pixels(paint.material().albedo_texture) != original_pixels,
		"editing copied layers cannot change the original material")
	_dispose(f)

func _check_failed_save() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	_stroke(paint)
	paint.add_layer()
	var mat: StandardMaterial3D = paint.material()
	var state: Dictionary = mat.get_meta("slab_paint_layers").duplicate(true)
	var pixels := _pixels(mat.albedo_texture)
	var version: int = f.undo.get_version()
	var blocker := "user://slab_paint_test/blocked_parent"
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("This is a file, not a directory.")
	file.close()
	_check(paint.save_png(blocker + "/image.png") != OK, "invalid parent path rejects Save")
	_check(mat.get_meta("slab_paint_layers") == state and _pixels(mat.albedo_texture) == pixels
		and f.undo.get_version() == version and paint.layer_count() == 2,
		"failed Save preserves layers, base pixels, display and Undo history")
	DirAccess.remove_absolute(blocker)
	_dispose(f)

func _check_roughness_scalar() -> void:
	for textured in [false, true]:
		var f := _fixture()
		var paint: RefCounted = f.paint
		var mat: StandardMaterial3D = paint.material()
		mat.roughness = 0.37
		var original: Texture2D
		if textured:
			var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			image.fill(Color(0.8, 0.6, 0.2, 1))
			original = ImageTexture.create_from_image(image)
			mat.roughness_texture = original
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		paint.channel = Paint.Channel.ROUGHNESS
		var expected := 0.37 * (0.6 if textured else 1.0)
		_check(is_equal_approx(mat.roughness, 0.37) and mat.roughness_texture == original,
			"Roughness preview leaves original material settings unchanged")
		paint.begin_stroke()
		paint.dab_pixel(Vector2(16, 16))
		paint.cancel_stroke()
		_check(is_equal_approx(mat.roughness, 0.37) and mat.roughness_texture == original,
			"Roughness Escape restores original scalar and texture before first stroke")
		_stroke(paint)
		_check(is_equal_approx(mat.roughness, 1.0)
			and absf(mat.roughness_texture.get_image().get_pixel(0, 0).r - expected) < 0.005
			and mat.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED,
			"Roughness stroke preserves effective untouched values and normalizes scalar (texture=%s)" % textured)
		var painted := _pixels(mat.roughness_texture)
		f.undo.undo()
		_check(is_equal_approx(mat.roughness, 0.37) and mat.roughness_texture == original
			and mat.roughness_texture_channel == (BaseMaterial3D.TEXTURE_CHANNEL_GREEN if textured else BaseMaterial3D.TEXTURE_CHANNEL_RED),
			"Roughness Undo restores original scalar, texture and component (texture=%s)" % textured)
		f.undo.redo()
		_check(is_equal_approx(mat.roughness, 1.0) and _pixels(mat.roughness_texture) == painted,
			"Roughness Redo restores normalized material and exact pixels")
		var path := "user://slab_paint_test/roughness_scalar.tres"
		_check(ResourceSaver.save(mat, path) == OK, "normalized Roughness resource saves")
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as StandardMaterial3D
		_check(is_equal_approx(loaded.roughness, 1.0) and _pixels(loaded.roughness_texture) == painted,
			"normalized Roughness and pixel values survive resource reload")
		_dispose(f)
