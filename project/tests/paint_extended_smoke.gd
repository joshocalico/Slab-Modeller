extends "res://tests/paint_state_smoke.gd"

const Raster := preload("res://addons/slab/slab_paint_raster.gd")
const Mask := preload("res://addons/slab/slab_paint_mask.gd")
const Channels := preload("res://addons/slab/slab_paint_channels.gd")


func _run() -> void:
	_check_brush_pixels()
	_check_concave_mask()
	_check_masked_edits()
	_check_layer_order()
	_check_added_channels()
	_check_native_mask_triangles()
	_check_metallic_import()
	_check_island_mask()
	_check_height_neutral()
	print("paint_extended_smoke failures=", failures)
	quit(1 if failures else 0)


func _check_brush_pixels() -> void:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	Raster.stamp(image, Vector2(8.5, 8.5), 5, Color.RED, 0.5, 1.0)
	var pixel := image.get_pixel(8, 8)
	_check(pixel.r == 1.0 and absf(pixel.a - 0.5) < 0.005,
		"translucent paint keeps straight RGB without double-darkening at composite time")
	var state := Paint.ChannelState.new(Vector2i(16, 16))
	state.layers[0].image = image.duplicate()
	var composite: Image = state.composite_all_layers(state.base_image)
	_check(composite.get_pixel(8, 8).r == 1.0 and absf(composite.get_pixel(8, 8).a - 0.5) < 0.005,
		"layer composite retains straight RGB over a transparent base")
	var soft := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	soft.fill(Color.TRANSPARENT)
	Raster.stamp(soft, Vector2(8.5, 8.5), 5, Color.RED, 0.5, 0.0)
	_check(image.get_pixel(12, 8).a > soft.get_pixel(12, 8).a + 0.3,
		"hardness changes the edge footprint without changing brush size")
	Raster.stamp(image, Vector2(8.5, 8.5), 5, Color.BLUE, 0.5, 1.0, true)
	_check(absf(image.get_pixel(8, 8).a - 0.25) < 0.005 and image.get_pixel(8, 8).r == 1.0,
		"eraser removes active-layer coverage without painting its brush color")
	Raster.stamp(image, Vector2(8.5, 8.5), 5, Color.WHITE, 1.0, 1.0, true)
	_check(image.get_pixel(8, 8) == Color.TRANSPARENT, "full eraser removes the layer pixel completely")
	var wrapped := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	wrapped.fill(Color.TRANSPARENT)
	Raster.stamp(wrapped, Vector2(0.5, 0.5), 12, Color.RED, 0.5, 1.0)
	_check(absf(wrapped.get_pixel(0, 0).a - 0.5) < 0.005,
		"a brush larger than a repeated tile applies opacity once per texel")


func _check_concave_mask() -> void:
	var concave := PackedVector2Array([Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.9, 0.3), Vector2(0.3, 0.3), Vector2(0.3, 0.9), Vector2(0.1, 0.9)])
	var mask := _polygon_mask(concave)
	_check(mask.get_pixel(5, 24).r == 1 and mask.get_pixel(24, 5).r == 1 and mask.get_pixel(24, 24).r == 0,
		"concave face mask includes both arms and excludes the empty notch")
	var across_seam := PackedVector2Array([Vector2(0.9, 0.2), Vector2(1.1, 0.2), Vector2(1.1, 0.4), Vector2(0.9, 0.4)])
	mask = _polygon_mask(across_seam)
	_check(mask.get_pixel(0, 9).r == 1 and mask.get_pixel(31, 9).r == 1 and mask.get_pixel(16, 9).r == 0,
		"UV mask crossing a tile seam protects the middle of the image")
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	Raster.stamp(image, Vector2(0.5, 9.5), 20, Color.RED, 1.0, 1.0, false, mask)
	_check(image.get_pixel(0, 9).a == 1 and image.get_pixel(31, 9).a == 1 and image.get_pixel(16, 9).a == 0,
		"wrapped brush and mask use the same texture coordinates")


func _check_masked_edits() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	var face: int = f.selection.ids[0]
	f.solid.call("set_face_uv", PackedInt64Array([face]), Vector2(0.25, 0.25), Vector2(0.25, 0.25), 0.0)
	paint.mask_mode = Paint.MaskMode.FACES
	var mask: Image = paint.mask_image()
	var inside := Vector2i(-1, -1)
	var outside := Vector2i(-1, -1)
	for y in 32:
		for x in 32:
			if mask.get_pixel(x, y).r > 0.5: inside = Vector2i(x, y)
			else: outside = Vector2i(x, y)
	_check(inside.x >= 0 and outside.x >= 0, "selected face creates a bounded texture mask")
	if inside.x < 0 or outside.x < 0:
		_dispose(f)
		return
	var outside_before: Color = paint.channel_state(paint.channel).active_layer().image.get_pixelv(outside)
	paint.brush_color = Color.RED
	_check(paint.fill_layer(), "Fill Layer accepts the face mask")
	var layer: Image = paint.channel_state(paint.channel).active_layer().image
	_check(layer.get_pixelv(inside) == Color.RED and layer.get_pixelv(outside) == outside_before,
		"masked Fill leaves every outside texel unchanged")
	var filled := layer.save_png_to_buffer()
	paint.brush_mode = Paint.BrushMode.ERASE
	paint.brush_hardness = 1.0
	paint.brush_radius = 64
	_check(paint.begin_stroke(), "masked erase starts")
	paint.dab_pixel(Vector2(inside) + Vector2(0.5, 0.5))
	paint.end_stroke()
	_check(not paint.has_channel_overlay_strokes(), "masked erase reveals the base beneath filled artwork")
	f.undo.undo()
	_check(paint.channel_state(paint.channel).active_layer().image.save_png_to_buffer() == filled,
		"eraser Undo restores exact masked pixels")
	f.selection.set_ids(PackedInt64Array())
	var version: int = f.undo.get_version()
	_check(not paint.begin_stroke() and not paint.fill_layer() and f.undo.get_version() == version,
		"empty face mask cannot become an unrestricted stroke or Fill")
	_dispose(f)


func _check_layer_order() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	var material: StandardMaterial3D = paint.material()
	paint.brush_color = Color.RED
	paint.fill_layer()
	paint.set_layer_name(0, "Red below")
	paint.add_layer("Blue above")
	paint.brush_color = Color.BLUE
	paint.fill_layer()
	_check(material.albedo_texture.get_image().get_pixel(0, 0) == Color.BLUE, "upper opaque layer determines the composite")
	_check(paint.move_layer(1, 0) and paint.active_layer_index() == 0,
		"reorder keeps the moved layer selected")
	_check(material.albedo_texture.get_image().get_pixel(0, 0) == Color.RED, "lowering a layer changes real composite pixels")
	f.undo.undo()
	_check(paint.active_layer_index() == 1 and paint.layer_info(0).name == "Red below"
		and material.albedo_texture.get_image().get_pixel(0, 0) == Color.BLUE,
		"reorder Undo restores order, active layer and pixels")
	paint.set_layer_name(1, "Renamed blue")
	var path := "user://slab_paint_test/organized_layers.tres"
	_check(ResourceSaver.save(material, path) == OK, "organized layers save as a material")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as StandardMaterial3D
	var stored: Dictionary = loaded.get_meta("slab_paint_layers")
	_check(stored[Paint.Channel.ALBEDO].layers[1].name == "Renamed blue",
		"renamed layer persists in its compositing order")
	_dispose(f)


func _check_added_channels() -> void:
	for channel in [Paint.Channel.METALLIC, Paint.Channel.NORMAL, Paint.Channel.HEIGHT]:
		var f := _fixture()
		var paint: RefCounted = f.paint
		var material: StandardMaterial3D = paint.material()
		material.metallic = 0.35
		material.normal_scale = 0.7
		material.heightmap_scale = 2.4
		material.heightmap_flip_texture = true
		var original := Channels.capture(material, channel)
		var albedo := _pixels(material.albedo_texture)
		paint.channel = channel
		_check(Channels.capture(material, channel) == original, "%s preview does not mutate material settings" % paint.current_channel_name())
		var expected_default := Channels.default_color(material, channel)
		_check(_color_close(paint.image().get_pixel(0, 0), expected_default),
			"%s starts from its neutral or scalar material value" % paint.current_channel_name())
		paint.brush_color = Color(0.7, 0.5, 1.0) if channel == Paint.Channel.NORMAL else Color.WHITE
		paint.brush_hardness = 1.0
		paint.brush_radius = 2
		_check(paint.begin_stroke(), "new channel accepts a stroke")
		paint.dab_pixel(Vector2(16.5, 16.5))
		paint.end_stroke()
		_check(Channels.has_texture(material, channel) and _pixels(material.albedo_texture) == albedo,
			"%s publishes only its selected material channel" % paint.current_channel_name())
		var edited := Channels.capture(material, channel)
		var pixels := _pixels(Channels.texture_for(material, channel))
		f.undo.undo()
		_check(Channels.capture(material, channel) == original, "new channel Undo restores original texture and settings")
		f.undo.redo()
		_check(Channels.capture(material, channel) == edited and _pixels(Channels.texture_for(material, channel)) == pixels,
			"new channel Redo restores binding and exact pixels")
		_check(is_equal_approx(material.normal_scale, 0.7) and is_equal_approx(material.heightmap_scale, 2.4)
			and material.heightmap_flip_texture, "normal strength and legacy height settings are preserved")
		var path := "user://slab_paint_test/channel_%s.tres" % paint.current_channel_name()
		_check(ResourceSaver.save(material, path) == OK, "new channel material saves")
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as StandardMaterial3D
		var reopened: RefCounted = Paint.new()
		var restored: RefCounted = reopened._state_for_material(loaded, channel)
		_check(restored.layers.size() == 1 and not restored.active_layer().is_empty()
			and restored.composite_all_layers(restored.base_image).save_png_to_buffer() == pixels,
			"new channel reload restores editable layers and exact composite")
		_check(Channels.has_texture(loaded, channel) and _pixels(Channels.texture_for(loaded, channel)) == pixels,
			"new channel material bindings and pixels survive reload")
		_check(paint.default_save_path().ends_with("_%s.png" % paint.current_channel_name().to_lower()),
			"new channel uses an independent PNG path")
		var png_path := "user://slab_paint_test/export_%s.png" % paint.current_channel_name()
		_check(paint.save_png(png_path) == OK and Image.load_from_file(png_path).save_png_to_buffer() == pixels,
			"new channel PNG exports exact visible pixels")
		_dispose(f)


func _polygon_mask(polygon: PackedVector2Array) -> Image:
	var indices := Geometry2D.triangulate_polygon(polygon)
	var triangles: Array[PackedVector2Array] = []
	for i in range(0, indices.size(), 3):
		triangles.append(PackedVector2Array([polygon[indices[i]], polygon[indices[i + 1]], polygon[indices[i + 2]]]))
	return Mask.rasterize_triangles(triangles, Vector2i(32, 32))


func _color_close(actual: Color, expected: Color) -> bool:
	return absf(actual.r - expected.r) < 0.005 and absf(actual.g - expected.g) < 0.005 \
		and absf(actual.b - expected.b) < 0.005 and absf(actual.a - expected.a) < 0.005


func _check_native_mask_triangles() -> void:
	var f := _fixture()
	var face: int = f.selection.ids[0]
	# The authored quad is folded in UV space. Its coverage is the union of
	# geometry triangles, which differs from triangulating this UV outline.
	var folded := PackedVector2Array([Vector2(0.1, 0.1), Vector2(0.9, 0.9), Vector2(0.1, 0.9), Vector2(0.9, 0.1)])
	_check(f.solid.call("set_face_uv_points", face, folded) == OK, "folded per-corner UV fixture is accepted")
	var data: Dictionary = f.solid.call("face_uv", face)
	var triangles: PackedInt32Array = data.triangles
	var mask := Mask.rasterize(f.solid, PackedInt64Array([face]), Vector2i(32, 32))
	var mismatch := 0
	for y in 32:
		for x in 32:
			var uv := Vector2(x + 0.5, y + 0.5) / 32.0
			var expected := false
			for i in range(0, triangles.size(), 3):
				var a := folded[triangles[i]]
				var b := folded[triangles[i + 1]]
				var c := folded[triangles[i + 2]]
				expected = expected or _inside_triangle(uv, a, b, c)
			if (mask.get_pixel(x, y).r > 0.5) != expected:
				mismatch += 1
	_check(mismatch == 0, "folded mask follows emitted geometry triangles at every texel")
	_dispose(f)


func _check_metallic_import() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	var material: StandardMaterial3D = paint.material()
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.8, 0.4, 1.0))
	material.metallic_texture = ImageTexture.create_from_image(image)
	material.metallic = 0.5
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	var original := Channels.capture(material, Paint.Channel.METALLIC)
	paint.channel = Paint.Channel.METALLIC
	_check(absf(paint.image().get_pixel(0, 0).r - 0.4) < 0.005,
		"Metallic imports effective scalar times the selected texture component")
	paint.brush_radius = 2
	paint.brush_hardness = 1.0
	paint.begin_stroke()
	paint.dab_pixel(Vector2(16.5, 16.5))
	paint.end_stroke()
	_check(material.metallic == 1.0 and material.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED
		and absf(material.metallic_texture.get_image().get_pixel(0, 0).r - 0.4) < 0.005,
		"Metallic publication preserves untouched effective values")
	f.undo.undo()
	_check(Channels.capture(material, Paint.Channel.METALLIC) == original,
		"Metallic Undo restores legacy scalar, channel selection and texture")
	_dispose(f)


func _check_island_mask() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	var solid: Node3D = f.solid
	var faces: PackedInt64Array = solid.call("get_faces")
	var first: int = f.selection.ids[0]
	var slot: int = solid.call("face_uv", first).slot
	solid.call("set_face_material", faces, slot)
	# A continuous projection across every shared edge forms one UV island.
	for face in faces:
		var points := PackedVector2Array()
		for point: Vector3 in solid.call("face_corners", face):
			points.append(Vector2(point.x + point.z * 0.3, point.y + point.z * 0.4) * 0.25 + Vector2(0.5, 0.5))
		solid.call("set_face_uv_points", face, points)
	paint.mask_mode = Paint.MaskMode.ISLANDS
	_check(paint.mask_face_ids().size() == faces.size(), "island mask follows shared continuous UV edges")
	var island_mask: Image = paint.mask_image()
	paint.brush_color = Color.RED
	paint.fill_layer()
	var image: Image = paint.channel_state(paint.channel).active_layer().image
	var mismatches := 0
	for y in 32:
		for x in 32:
			if (image.get_pixel(x, y).a > 0.5) != (island_mask.get_pixel(x, y).r > 0.5):
				mismatches += 1
	_check(mismatches == 0, "island Fill covers exactly the selected island texels")
	solid.call("mark_uv_seams", solid.call("face_edges", first), true)
	_check(paint.mask_face_ids() == PackedInt64Array([first]), "marked seams bound island mask traversal")
	solid.call("mark_uv_seams", solid.call("face_edges", first), false)
	var materials: Array = solid.get("materials")
	materials.append(StandardMaterial3D.new())
	solid.set("materials", materials)
	solid.call("set_face_material", PackedInt64Array([faces[1]]), materials.size() - 1)
	_check(paint.mask_face_ids().size() == faces.size() - 1 and not paint.mask_face_ids().has(faces[1]),
		"island membership cannot paint a face using another material")
	_dispose(f)


func _inside_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab := (b - a).cross(p - a)
	var bc := (c - b).cross(p - b)
	var ca := (a - c).cross(p - c)
	return not ((ab < -0.000001 or bc < -0.000001 or ca < -0.000001)
		and (ab > 0.000001 or bc > 0.000001 or ca > 0.000001))


func _check_height_neutral() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	var material: StandardMaterial3D = paint.material()
	paint.channel = Paint.Channel.HEIGHT
	_check(not material.heightmap_flip_texture and paint.image().get_pixel(0, 0) == Color.WHITE,
		"default Height starts white for zero parallax displacement")
	paint.brush_color = Color.BLACK
	paint.brush_hardness = 1.0
	paint.brush_radius = 2
	paint.begin_stroke()
	paint.dab_pixel(Vector2(16.5, 16.5))
	paint.end_stroke()
	var image := material.heightmap_texture.get_image()
	_check(material.heightmap_enabled and image.get_pixel(0, 0) == Color.WHITE and image.get_pixel(16, 16) == Color.BLACK,
		"Height publishes a depth mark while untouched pixels stay neutral")
	_dispose(f)
