extends SceneTree

const Brushes := preload("res://addons/slab/slab_paint_brushes.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_clone()
	_blur()
	_smudge()
	_stamp()
	_gradient()
	_fill()
	_invalid_inputs()
	print("paint_brushes_smoke: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _image(w: int = 8, h: int = 8, color: Color = Color.TRANSPARENT) -> Image:
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(label)


func _near(a: Color, b: Color, epsilon: float = 0.012) -> bool:
	return absf(a.r - b.r) <= epsilon and absf(a.g - b.g) <= epsilon and absf(a.b - b.b) <= epsilon and absf(a.a - b.a) <= epsilon


func _clone() -> void:
	var source := _image()
	source.set_pixel(2, 2, Color.RED)
	var image := _image()
	_check(Brushes.clone(image, source, Vector2(5.5, 2.5), Vector2(-3, 0), 0.5, 1, 1), "clone changes destination")
	_check(_near(image.get_pixel(5, 2), Color.RED) and image.get_pixel(2, 2).a == 0, "clone uses persistent source offset")
	_check(not Brushes.clone(image, source, Vector2(5.5, 2.5), Vector2(-3, 0), 0.5, 1, 1), "identical clone returns unchanged")
	var mask := _image(8, 8, Color.BLACK)
	_check(not Brushes.clone(image, source, Vector2(4.5, 2.5), Vector2(-2, 0), 0.5, 1, 1, mask), "clone respects mask")
	image = _image()
	Brushes.clone(image, source, Vector2(7.5, 2.5), Vector2(3, 0), 0.5, 1, 1)
	_check(_near(image.get_pixel(7, 2), Color.RED), "clone source wraps across image edge")
	image = _image()
	Brushes.clone(image, source, Vector2(4.5, 2.5), Vector2(-1.5, 0), 0.5, 1, 1)
	_check(_near(image.get_pixel(4, 2), Color(1, 0, 0, 0.5)), "bilinear clone retains red next to transparent black")
	var other := _image()
	Brushes.clone(other, source, Vector2(4.5, 2.5), Vector2(-1.5, 0), 0.5, 1, 1)
	_check(image.get_data() == other.get_data(), "clone frozen source is deterministic")


func _blur() -> void:
	var source := _image()
	source.set_pixel(0, 0, Color.RED)
	var image: Image = source.duplicate()
	_check(Brushes.blur(image, source, Vector2(7.5, 0.5), 0.5, 1, 1, null, 1), "blur samples across wrapped seam")
	_check(_near(image.get_pixel(7, 0), Color(1, 0, 0, 1.0 / 9.0)), "blur averages premultiplied alpha without black fringe")
	var mask := _image(8, 8, Color.BLACK)
	mask.set_pixel(0, 0, Color.WHITE)
	image = source.duplicate()
	_check(not Brushes.blur(image, source, Vector2(0.5, 0.5), 2, 1, 1, mask, 1), "blur excludes masked neighbours and cannot bleed outside selection")
	_check(image.get_data() == source.get_data(), "masked blur leaves isolated source texel exact")
	image = source.duplicate()
	var other: Image = source.duplicate()
	Brushes.blur(image, source, Vector2(0.5, 0.5), 2, 0.7, 0.5)
	Brushes.blur(other, source, Vector2(0.5, 0.5), 2, 0.7, 0.5)
	_check(image.get_data() == other.get_data(), "blur frozen-source traversal is deterministic")


func _smudge() -> void:
	var source := _image()
	source.set_pixel(7, 3, Color.BLUE)
	var image: Image = source.duplicate()
	_check(Brushes.smudge(image, source, Vector2(7.5, 3.5), Vector2(8.5, 3.5), 0.5, 1, 1), "smudge moves paint across wrapped edge")
	_check(_near(image.get_pixel(0, 3), Color.BLUE), "smudge samples previous point at destination")
	_check(_near(image.get_pixel(7, 3), Color.BLUE), "smudge does not erase source outside destination footprint")
	_check(not Brushes.smudge(image, image.duplicate(), Vector2(0.5, 3.5), Vector2(0.5, 3.5), 1, 1, 1), "stationary smudge is unchanged")


func _stamp() -> void:
	var tip := _image(1, 1, Color.WHITE)
	var image := _image()
	_check(Brushes.stamp(image, tip, Vector2(0.5, 0.5), 0.5, Color.RED, 1), "stamp paints at texel center")
	_check(_near(image.get_pixel(0, 0), Color.RED), "stamp tint applies to tip RGB")
	var mask := _image(8, 8, Color.BLACK)
	mask.set_pixel(7, 0, Color.WHITE)
	image = _image()
	Brushes.stamp(image, tip, Vector2(0, 0.5), 2, Color.BLUE, 1, 1, 0, mask)
	_check(image.get_pixel(7, 0).b > 0.99 and image.get_pixel(7, 0).a > 0, "stamp wraps footprint across edge")
	_check(image.get_pixel(0, 0).a == 0, "stamp mask blocks opposite seam texel")
	var asymmetric := _image(2, 2)
	asymmetric.set_pixel(0, 0, Color.RED)
	var unrotated := _image()
	var rotated := _image()
	Brushes.stamp(unrotated, asymmetric, Vector2(4, 4), 2, Color.WHITE, 1)
	Brushes.stamp(rotated, asymmetric, Vector2(4, 4), 2, Color.WHITE, 1, 1, PI)
	_check(unrotated.get_pixel(3, 3).a > unrotated.get_pixel(4, 4).a and rotated.get_pixel(4, 4).a > rotated.get_pixel(3, 3).a, "stamp rotation rotates asymmetric tip")
	_check(unrotated.get_pixel(3, 3).r > 0.99, "stamp transparent tip edges do not darken tint")
	var square_tip := _image(16, 16, Color.WHITE)
	var round_tip := _image(16, 16)
	for y in 16:
		for x in 16:
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8)) <= 8:
				round_tip.set_pixel(x, y, Color.WHITE)
	var square := _image(16, 16)
	var round_image := _image(16, 16)
	Brushes.stamp(square, square_tip, Vector2(8, 8), 4, Color.RED, 1)
	Brushes.stamp(round_image, round_tip, Vector2(8, 8), 4, Color.RED, 1)
	_check(square.get_pixel(5, 5).a > 0.9 and round_image.get_pixel(5, 5).a < 0.01,
		"square tip retains corners that distinguish it from round tip")


func _gradient() -> void:
	var source := _image()
	var image := _image()
	_check(Brushes.gradient(image, source, Vector2(0, 4), Vector2(8, 4), Color.RED, Color.BLUE), "gradient paints full-width ramp")
	_check(_near(image.get_pixel(0, 4), Color(0.9375, 0, 0.0625)) and _near(image.get_pixel(7, 4), Color(0.0625, 0, 0.9375)), "gradient endpoints interpolate across full image")
	Brushes.gradient(image, source, Vector2(7, 4), Vector2(9, 4), Color.RED, Color.BLUE)
	_check(_near(image.get_pixel(7, 4), Color(0.75, 0, 0.25)) and _near(image.get_pixel(0, 4), Color(0.25, 0, 0.75)), "gradient crosses tile seam in gesture direction")
	var once := image.get_data()
	_check(not Brushes.gradient(image, source, Vector2(7, 4), Vector2(9, 4), Color.RED, Color.BLUE) and image.get_data() == once, "gradient preview repeats from snapshot without accumulating")
	var mask := _image(8, 8, Color.BLACK)
	mask.set_pixel(3, 3, Color.WHITE)
	image = _image()
	Brushes.gradient(image, source, Vector2(0, 4), Vector2(8, 4), Color.RED, Color.TRANSPARENT, 1, mask)
	_check(_near(image.get_pixel(3, 3), Color(1, 0, 0, 0.5625)), "gradient alpha interpolation retains saturated red")
	_check(image.get_pixel(4, 3).a == 0, "gradient respects mask")
	_check(not Brushes.gradient(image, source, Vector2.ONE, Vector2.ONE, Color.RED, Color.BLUE), "zero-length gradient does not divide by zero")


func _fill() -> void:
	var source := _image(8, 8, Color.WHITE)
	source.set_pixel(0, 3, Color.BLACK)
	source.set_pixel(7, 3, Color.BLACK)
	source.set_pixel(4, 3, Color.BLACK)
	var image: Image = source.duplicate()
	_check(Brushes.contiguous_fill(image, source, Vector2(0.5, 3.5), Color.RED), "contiguous fill changes matching component")
	_check(_near(image.get_pixel(0, 3), Color.RED) and _near(image.get_pixel(7, 3), Color.RED), "fill connects matching pixels over wrapped seam")
	_check(_near(image.get_pixel(4, 3), Color.BLACK) and _near(image.get_pixel(1, 3), Color.WHITE), "fill excludes disconnected equal colors and unlike neighbors")
	var mask := _image(8, 8, Color.BLACK)
	mask.set_pixel(0, 3, Color.WHITE)
	image = source.duplicate()
	Brushes.contiguous_fill(image, source, Vector2(0.5, 3.5), Color.BLUE, 1, 0, mask)
	_check(_near(image.get_pixel(0, 3), Color.BLUE) and _near(image.get_pixel(7, 3), Color.BLACK), "fill mask blocks traversal across seam")
	source = _image()
	source.set_pixel(2, 2, Color(1, 0, 0, 0))
	image = source.duplicate()
	Brushes.contiguous_fill(image, source, Vector2(0, 0), Color.GREEN)
	_check(_near(image.get_pixel(2, 2), Color.GREEN), "fill treats invisible RGB as same transparent region")
	source = _image(8, 8, Color.WHITE)
	source.set_pixel(2, 2, Color(0.95, 0.95, 0.95))
	image = source.duplicate()
	Brushes.contiguous_fill(image, source, Vector2(0, 0), Color.BLUE, 1, 0.06)
	_check(_near(image.get_pixel(2, 2), Color.BLUE), "fill tolerance includes close premultiplied colors")
	var underlay := _image(8, 8, Color.BLUE)
	var layer := _image()
	var before := layer.get_data()
	_check(not Brushes.contiguous_fill(layer, underlay, Vector2.ZERO, Color.TRANSPARENT)
		and layer.get_data() == before, "transparent fill never bakes visible underlay into active layer")
	Brushes.contiguous_fill(layer, underlay, Vector2.ZERO, Color(1, 0, 0, 0.5))
	_check(_near(layer.get_pixel(0, 0), Color(1, 0, 0, 0.5)),
		"fill uses composite only for membership and blends into active layer")


func _invalid_inputs() -> void:
	var image := _image()
	var source := _image(2, 2)
	_check(not Brushes.clone(image, source, Vector2.ZERO, Vector2.ZERO, 1, 1), "source size mismatch is rejected")
	_check(not Brushes.gradient(image, image.duplicate(), Vector2.ZERO, Vector2.ONE, Color.RED, Color.BLUE, 1, _image(2, 2)), "mask size mismatch is rejected")
	_check(not Brushes.stamp(image, null, Vector2.ZERO, 1, Color.WHITE, 1), "missing stamp tip is unchanged")
	_check(not Brushes.clone(image, image.duplicate(), Vector2.ZERO, Vector2.ONE, 0, 1), "zero radius is unchanged")
