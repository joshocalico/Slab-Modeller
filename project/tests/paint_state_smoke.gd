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
	_check_emission_operator()
	_check_fill_layer()
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

func _check_emission_operator() -> void:
	for operator in [BaseMaterial3D.EMISSION_OP_ADD, BaseMaterial3D.EMISSION_OP_MULTIPLY]:
		var f := _fixture()
		var paint: RefCounted = f.paint
		var mat: StandardMaterial3D = paint.material()
		mat.emission_enabled = true
		mat.emission = Color(1, 0.72, 0.12)
		mat.emission_operator = operator
		mat.emission_energy_multiplier = 3.2
		var original_color := mat.emission
		var mask := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		mask.fill(Color.BLACK)
		var original := ImageTexture.create_from_image(mask)
		mat.emission_texture = original
		paint.channel = Paint.Channel.EMISSION
		_check(mat.emission_texture == original and mat.emission == original_color
			and mat.emission_operator == operator, "Emission preview preserves imported material settings")
		paint.begin_stroke()
		paint.dab_pixel(Vector2(16, 16))
		paint.cancel_stroke()
		_check(mat.emission_texture == original and mat.emission == original_color
			and mat.emission_operator == operator, "Emission Escape restores original texture, color and operator")
		_stroke(paint)
		var pixels := mat.emission_texture.get_image()
		# Godot's shader uses (color * texture) * energy for MULTIPLY,
		# versus (color + texture) * energy for ADD. Black must emit no light.
		var outside := mat.emission * pixels.get_pixel(0, 0) if mat.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY else mat.emission + pixels.get_pixel(0, 0)
		var inside := mat.emission * pixels.get_pixel(16, 16) if mat.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY else mat.emission + pixels.get_pixel(16, 16)
		_check(mat.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY and mat.emission == Color.WHITE
			and is_zero_approx(outside.r + outside.g + outside.b)
			and inside.r > 0.1 and is_zero_approx(inside.g + inside.b)
			and is_equal_approx(mat.emission_energy_multiplier, 3.2),
			"Emission paint publishes absolute colored pixels with black outside the mask (legacy operator=%s)" % operator)
		var painted := _pixels(mat.emission_texture)
		f.undo.undo()
		_check(mat.emission_enabled and mat.emission_texture == original and mat.emission == original_color
			and mat.emission_operator == operator and is_equal_approx(mat.emission_energy_multiplier, 3.2),
			"Emission Undo restores exact legacy color, operator, texture and energy")
		f.undo.redo()
		_check(mat.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY and mat.emission == Color.WHITE
			and _pixels(mat.emission_texture) == painted, "Emission Redo restores masked output and exact pixels")
		var path := "user://slab_paint_test/emission_operator.tres"
		_check(ResourceSaver.save(mat, path) == OK, "masked Emission resource saves")
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as StandardMaterial3D
		_check(loaded.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY and loaded.emission == Color.WHITE
			and _pixels(loaded.emission_texture) == painted and is_equal_approx(loaded.emission_energy_multiplier, 3.2),
			"Emission mask settings and exact pixels survive resource reload")
		_dispose(f)


func _check_fill_layer() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	var mat: StandardMaterial3D = paint.material()
	var albedo := _pixels(mat.albedo_texture)
	paint.channel = Paint.Channel.EMISSION
	var reports: Array[String] = []
	paint.reported.connect(func(message: String) -> void: reports.append(message))
	paint.exit()
	paint.enter()
	_check(paint.channel == Paint.Channel.EMISSION and reports.back().contains("paints emission"),
		"reopening Paint reports the preserved active channel")
	paint.add_layer("Indicator")
	_stroke(paint)
	paint.set_layer_visible(1, false)
	paint.set_active_layer(0)
	var state = paint.channel_state(Paint.Channel.EMISSION)
	var base: PackedByteArray = state.base_image.save_png_to_buffer()
	var hidden: PackedByteArray = state.layers[1].image.save_png_to_buffer()
	var before: Dictionary = mat.get_meta("slab_paint_layers").duplicate(true)
	var panel := preload("res://addons/slab/slab_panel.gd").new()
	panel.setup(f.selection, f.actions)
	panel.bind_paint(paint)
	var fill: Button = panel.find_child("PaintFillLayer", true, false)
	_check(fill != null and not fill.disabled, "Fill Layer is available on an editable Paint target")
	paint.brush_color = Color.BLACK
	paint.brush_opacity = 1.0
	var version: int = f.undo.get_version()
	fill.pressed.emit()
	_check(f.undo.get_version() == version + 1, "Fill Layer creates one Undo action")
	var expected := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	expected.fill(Color.BLACK)
	_check(_pixels(mat.emission_texture) == expected.save_png_to_buffer(), "Fill Layer makes every Emission texel exact black")
	_check(state.base_image.save_png_to_buffer() == base and state.layers[1].image.save_png_to_buffer() == hidden
		and not state.layers[1].visible and _pixels(mat.albedo_texture) == albedo,
		"Fill preserves base, hidden artwork, visibility and other channels")
	var filled: Dictionary = mat.get_meta("slab_paint_layers").duplicate(true)
	paint.channel = Paint.Channel.ALBEDO
	f.undo.undo()
	_check(mat.get_meta("slab_paint_layers") == before and _pixels(mat.albedo_texture) == albedo,
		"Fill Undo restores exact layer state after switching channel")
	f.undo.redo()
	_check(mat.get_meta("slab_paint_layers") == filled and _pixels(mat.emission_texture) == expected.save_png_to_buffer(),
		"Fill Redo restores exact black pixels on its original channel")
	paint.channel = Paint.Channel.EMISSION
	paint.brush_color = Color(0.8, 0.4, 0.2, 0.5)
	paint.brush_opacity = 0.5
	_check(paint.fill_layer(), "Fill accepts brush opacity and color alpha")
	var pixel: Color = paint.channel_state(Paint.Channel.EMISSION).active_layer().image.get_pixel(0, 0)
	_check(absf(pixel.a - 0.25) < 0.005 and absf(pixel.r - 0.8) < 0.005,
		"Fill stores brush color with combined alpha and opacity")
	paint.begin_stroke()
	_check(fill.disabled and not paint.fill_layer(), "Fill refuses and disables during a stroke")
	paint.end_stroke()
	_check(not fill.disabled, "ending an empty stroke restores Fill availability")
	f.actions.operation_active = true
	_check(not paint.can_fill_layer(), "Fill refuses during a modelling operation")
	f.actions.operation_active = false
	mat.set_meta(Paint.OWNED_META, false)
	_check(not paint.can_fill_layer() and not paint.fill_layer(), "Fill refuses an unowned material")
	panel.free()
	_dispose(f)
