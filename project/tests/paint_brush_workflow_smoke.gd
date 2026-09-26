extends "res://tests/paint_state_smoke.gd"

func _run() -> void:
	_check_object_entry()
	for mode in [Paint.BrushMode.GRADIENT, Paint.BrushMode.CLONE, Paint.BrushMode.BLUR,
		Paint.BrushMode.SMUDGE, Paint.BrushMode.STAMP, Paint.BrushMode.FILL, Paint.BrushMode.AIRBRUSH]:
		_check_workflow(mode)
	_check_sample_and_channel_isolation()
	_check_masks()
	print("paint_brush_workflow_smoke failures=", failures)
	quit(1 if failures else 0)

func _seed(paint: RefCounted) -> void:
	paint.brush_color = Color.BLUE
	paint.brush_opacity = 1.0
	paint.brush_hardness = 1.0
	paint.fill_layer()
	paint.brush_mode = Paint.BrushMode.PAINT
	paint.brush_color = Color.RED
	paint.brush_radius = 3.0
	paint.begin_stroke()
	paint.dab_pixel(Vector2(8.5, 8.5))
	paint.end_stroke()

func _layer_pixels(paint: RefCounted) -> PackedByteArray:
	return paint.channel_state(paint.channel).active_layer().image.save_png_to_buffer()

func _gesture(paint: RefCounted, mode: int, alternate: bool = false) -> void:
	match mode:
		Paint.BrushMode.GRADIENT:
			paint.dab_pixel(Vector2(4.5, 8.5))
			paint.dab_pixel(Vector2(24.5, 8.5))
		Paint.BrushMode.CLONE:
			paint.dab_pixel(Vector2(24.5, 24.5) if alternate else Vector2(24.5, 8.5))
		Paint.BrushMode.BLUR:
			paint.dab_pixel(Vector2(10.5, 8.5))
		Paint.BrushMode.SMUDGE:
			paint.dab_pixel(Vector2(8.5, 8.5))
			paint.dab_pixel(Vector2(20.5, 24.5) if alternate else Vector2(20.5, 8.5))
		Paint.BrushMode.FILL:
			paint.dab_pixel(Vector2(8.5, 8.5))
		_:
			paint.dab_pixel(Vector2(24.5, 24.5) if alternate else Vector2(24.5, 8.5))
			if mode == Paint.BrushMode.AIRBRUSH:
				paint.tick_airbrush(0.05)
				paint.tick_airbrush(0.05)

func _check_workflow(mode: int) -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	_seed(paint)
	f.undo.clear_history()
	paint.brush_mode = mode
	paint.brush_color = Color.GREEN
	paint.gradient_color = Color.YELLOW
	paint.brush_radius = 4
	paint.brush_flow = .2
	paint.fill_tolerance = .01
	if mode == Paint.BrushMode.CLONE:
		var unbound_before := _pixels(paint.texture())
		_check(not paint.begin_stroke() and _pixels(paint.texture()) == unbound_before,
			"clone refuses before an Alt-click source has been set")
		paint.set_clone_source(Vector2(8.5, 8.5))
	if mode == Paint.BrushMode.STAMP:
		var tip := Image.create(5, 5, false, Image.FORMAT_RGBA8)
		tip.fill(Color.TRANSPARENT)
		tip.set_pixel(2, 2, Color.WHITE)
		_check(paint.set_stamp_image(tip), "controller accepts an alpha stamp image")
	var before := _pixels(paint.texture())
	var layer_before := _layer_pixels(paint)
	var version: int = f.undo.get_version()
	_check(paint.begin_stroke(), "brush mode %d starts a controller stroke" % mode)
	_gesture(paint, mode)
	if mode == Paint.BrushMode.AIRBRUSH:
		var first_alpha: float = paint.texture().get_image().get_pixel(24, 8).g
		paint.tick_airbrush(.05)
		_check(paint.texture().get_image().get_pixel(24, 8).g > first_alpha,
			"stationary airbrush accumulates colour on timer ticks")
		paint.suspend_airbrush()
		var suspended := _pixels(paint.texture())
		paint.tick_airbrush(.1)
		_check(_pixels(paint.texture()) == suspended, "airbrush stops depositing outside the canvas/model")
	paint.end_stroke()
	var after := _pixels(paint.texture())
	var layer_after := _layer_pixels(paint)
	_check(after != before and layer_after != layer_before, "brush mode %d changes actual channel pixels" % mode)
	_check(f.undo.get_version() == version + 1, "brush mode %d records exactly one Undo transaction" % mode)
	var image: Image = paint.texture().get_image()
	match mode:
		Paint.BrushMode.CLONE:
			_check(image.get_pixel(24, 8).r > .9 and image.get_pixel(24, 8).b < .1, "clone paints frozen source colour instead of brush colour")
		Paint.BrushMode.SMUDGE:
			_check(image.get_pixel(20, 8).r > .9, "smudge transports source colour along the drag")
		Paint.BrushMode.BLUR:
			var blurred := image.get_pixel(10, 8)
			_check(blurred.r > .05 and blurred.b > .05, "blur mixes source colours across a painted boundary")
		Paint.BrushMode.STAMP:
			_check(image.get_pixel(24, 8).g > .5 and image.get_pixel(27, 8).b > .9, "stamp alpha paints the tip while protecting transparent surroundings")
		Paint.BrushMode.FILL:
			_check(image.get_pixel(8, 8).g > .9 and image.get_pixel(24, 8).b > .9, "contiguous fill changes the seeded red region without crossing blue boundary")
		Paint.BrushMode.GRADIENT:
			_check(image.get_pixel(5, 8).r < image.get_pixel(23, 8).r, "gradient follows start-to-end colour direction")
	f.undo.undo()
	_check(_pixels(paint.texture()) == before and _layer_pixels(paint) == layer_before, "brush mode %d Undo restores exact composite and layer state" % mode)
	f.undo.redo()
	_check(_pixels(paint.texture()) == after and _layer_pixels(paint) == layer_after, "brush mode %d Redo restores exact pixels" % mode)
	version = f.undo.get_version()
	paint.brush_color = Color.MAGENTA
	paint.gradient_color = Color.CYAN
	_check(paint.begin_stroke(), "brush mode %d begins cancellable stroke" % mode)
	_gesture(paint, mode, true)
	paint.cancel_stroke()
	_check(_pixels(paint.texture()) == after and _layer_pixels(paint) == layer_after and f.undo.get_version() == version,
		"brush mode %d cancellation restores exact pixels without history" % mode)
	_dispose(f)

func _check_sample_and_channel_isolation() -> void:
	var f := _fixture()
	var paint: RefCounted = f.paint
	_seed(paint)
	var albedo := _pixels(paint.texture())
	var version: int = f.undo.get_version()
	paint.brush_mode = Paint.BrushMode.EYEDROPPER
	paint.sample_pixel(Vector2(8.5, 8.5))
	_check(paint.brush_color.r > .9 and paint.brush_color.b < .1, "eyedropper samples visible channel colour")
	_check(not paint.begin_stroke() and _pixels(paint.texture()) == albedo and f.undo.get_version() == version, "eyedropper creates no pixels or Undo entry")
	paint.set_clone_source(Vector2(8.5, 8.5))
	paint.channel = Paint.Channel.ROUGHNESS
	paint.make_unique_channel()
	paint.brush_mode = Paint.BrushMode.CLONE
	_check(not paint.begin_stroke(), "clone source cannot silently cross into another channel")
	paint.brush_mode = Paint.BrushMode.GRADIENT
	paint.brush_color = Color.BLACK
	paint.gradient_color = Color.WHITE
	var roughness := _pixels(paint.texture())
	paint.begin_stroke()
	_gesture(paint, Paint.BrushMode.GRADIENT)
	paint.end_stroke()
	_check(_pixels(paint.texture()) != roughness, "gradient edits active roughness channel")
	_check(_pixels(paint.material().albedo_texture) == albedo, "roughness brush leaves albedo pixels untouched")
	f.undo.undo()
	_check(_pixels(paint.texture()) == roughness and _pixels(paint.material().albedo_texture) == albedo, "channel stroke Undo restores only its target")
	f.undo.redo()
	var original_material: StandardMaterial3D = paint.material()
	paint.set_clone_source(Vector2(8.5, 8.5))
	var other := _fixture()
	var other_material: StandardMaterial3D = other.paint.material()
	var other_pixels := _pixels(other_material.albedo_texture)
	f.selection.set_objects([other.solid])
	f.selection.set_ids(PackedInt64Array([other.solid.call("get_faces")[0]]))
	paint.brush_mode = Paint.BrushMode.CLONE
	_check(not paint.begin_stroke(), "clone source cannot silently cross into another material")
	f.undo.undo()
	_check(_pixels(original_material.roughness_texture) == roughness and _pixels(other_material.albedo_texture) == other_pixels,
		"history remains bound to original channel/material after selecting another solid")
	_dispose(f)
	_dispose(other)

func _check_masks() -> void:
	for mode in [Paint.BrushMode.GRADIENT, Paint.BrushMode.FILL]:
		var f := _fixture()
		var paint: RefCounted = f.paint
		paint.brush_color = Color.BLUE
		paint.fill_layer()
		var face: int = f.selection.ids[0]
		f.solid.call("set_face_uv", PackedInt64Array([face]), Vector2(.5, .5), Vector2(.25, .25), 0.0)
		paint.mask_mode = Paint.MaskMode.FACES
		var mask: Image = paint.mask_image()
		var inside := Vector2i(-1, -1)
		for y in 32:
			for x in 32:
				if mask.get_pixel(x, y).r > .5: inside = Vector2i(x, y)
		_check(inside.x >= 0, "mask fixture has selected texels")
		if inside.x < 0:
			_dispose(f)
			continue
		paint.brush_mode = mode
		paint.brush_color = Color.GREEN
		paint.gradient_color = Color.YELLOW
		var before: Image = paint.texture().get_image()
		paint.begin_stroke()
		paint.dab_pixel(Vector2(inside) + Vector2(.5, .5))
		if mode == Paint.BrushMode.GRADIENT: paint.dab_pixel(Vector2(inside) + Vector2(8.5, .5))
		paint.end_stroke()
		var after: Image = paint.texture().get_image()
		var outside_unchanged := true
		var edited_inside := false
		for y in 32:
			for x in 32:
				if mask.get_pixel(x, y).r <= .5:
					outside_unchanged = outside_unchanged and before.get_pixel(x, y) == after.get_pixel(x, y)
				else:
					edited_inside = edited_inside or before.get_pixel(x, y) != after.get_pixel(x, y)
		_check(outside_unchanged and edited_inside, "masked mode %d changes selected texels and preserves every outside texel" % mode)
		_dispose(f)


func _check_object_entry() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3.ONE)
	var selection := Selection.new()
	selection.set_objects([solid])
	var actions := Actions.new(selection)
	actions.uv_texture_resolution = 32
	actions.uv_pixels_per_meter = 4.0
	actions.run("uv_auto_unwrap")
	var faces: PackedInt64Array = solid.call("get_faces")
	var all_unwrapped := true
	for face in faces:
		all_unwrapped = all_unwrapped and bool(solid.call("face_uv", face).unwrapped)
	_check(all_unwrapped and selection.mode == Selection.Mode.OBJECT and selection.ids.is_empty(),
		"Object Auto Unwrap prepares every face without manual selection")
	var undo := UndoRedo.new()
	var paint := Paint.new()
	paint.bind(selection, actions, undo)
	paint.enter()
	_check(selection.mode == Selection.Mode.FACE and selection.ids.size() == faces.size(),
		"entering Paint from Object mode selects the whole solid automatically")
	paint.tool = Paint.Tool.PIXEL
	_check(paint.make_unique() >= 0, "whole-object Paint can make an editable texture immediately")
	var assigned := true
	for face in faces:
		assigned = assigned and int(solid.call("face_uv", face).slot) == paint.slot()
	_check(assigned and paint.material() != null, "whole-object texture binding covers every face")
	paint.brush_color = Color.RED
	paint.brush_radius = 2
	var before := _pixels(paint.texture())
	_check(paint.begin_stroke(), "auto-unwrapped object immediately accepts a paint stroke")
	paint.dab_pixel(Vector2(8.5, 8.5))
	paint.end_stroke()
	_check(_pixels(paint.texture()) != before, "Auto Unwrap to Paint produces real edited texture pixels")
	_dispose({"solid": solid, "paint": paint, "undo": undo})
