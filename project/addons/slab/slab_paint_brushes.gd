@tool
extends RefCounted

# Pixel-space tools for tileable RGBA images. Source is a frozen snapshot;
# destinations are masked, while clone/smudge may sample outside that mask.
# Callers own stroke interpolation and Undo. Rotation is in radians.

static func blur(image: Image, source: Image, center: Vector2, radius: float, opacity: float, hardness: float = 0.0, mask: Image = null, kernel_radius: int = 2) -> bool:
	if not _valid(image, source, mask) or kernel_radius < 1:
		return false
	var changed := false
	var w := image.get_width()
	var h := image.get_height()
	var coverage := _coverage(image, center, radius, hardness, mask)
	for key: int in coverage:
		var x := key % w
		var y := key / w
		var sum := Color(0, 0, 0, 0)
		var count := 0
		for dy in range(-kernel_radius, kernel_radius + 1):
			for dx in range(-kernel_radius, kernel_radius + 1):
				var sx := posmod(x + dx, w)
				var sy := posmod(y + dy, h)
				if not _allowed(mask, sx, sy):
					continue
				sum += _premultiply(source.get_pixel(sx, sy))
				count += 1
		if count == 0:
			continue
		var weight := float(coverage[key]) * clampf(opacity, 0, 1)
		var result := _mix(image.get_pixel(x, y), _unpremultiply(sum / float(count)), weight)
		changed = _write(image, x, y, result) or changed
	return changed


static func smudge(image: Image, source: Image, from: Vector2, to: Vector2, radius: float, opacity: float, hardness: float = 0.0, mask: Image = null) -> bool:
	return clone(image, source, to, from - to, radius, opacity, hardness, mask)


# Positive offset samples to the right/down of the destination.
static func clone(image: Image, source: Image, center: Vector2, source_offset: Vector2, radius: float, opacity: float, hardness: float = 0.0, mask: Image = null) -> bool:
	if not _valid(image, source, mask):
		return false
	var changed := false
	var coverage := _coverage(image, center, radius, hardness, mask)
	var w := image.get_width()
	for key: int in coverage:
		var x := key % w
		var y := key / w
		var sample := _sample(source, Vector2(x + 0.5, y + 0.5) + source_offset)
		var result := _mix(image.get_pixel(x, y), sample, float(coverage[key]) * clampf(opacity, 0, 1))
		changed = _write(image, x, y, result) or changed
	return changed


# Fit the entire square tip inside the circular brush footprint, preserving
# square/star corners. Tip RGB is tinted by color RGB; both alphas contribute.
# Outside the tip is transparent, not wrapped.
static func stamp(image: Image, tip: Image, center: Vector2, radius: float, color: Color, opacity: float, hardness: float = 1.0, rotation: float = 0.0, mask: Image = null) -> bool:
	if not _valid(image, image, mask) or tip == null or tip.is_empty() or tip.is_compressed():
		return false
	var coverage := _coverage(image, center, radius, hardness, mask)
	var changed := false
	var w := image.get_width()
	for key: int in coverage:
		var x := key % w
		var y := key / w
		var delta := _wrapped_delta(image, Vector2(x + 0.5, y + 0.5) - center).rotated(-rotation)
		var uv := delta / (sqrt(2.0) * radius) + Vector2(0.5, 0.5)
		var sample := _sample(tip, uv * Vector2(tip.get_size()), false) * color
		var result := _over(image.get_pixel(x, y), sample, float(coverage[key]) * clampf(opacity, 0, 1))
		changed = _write(image, x, y, result) or changed
	return changed


# The unwrapped from/to positions define direction and length. Each texel uses
# the tile nearest the segment midpoint, so a boundary-crossing gesture stays continuous.
static func gradient(image: Image, source: Image, from: Vector2, to: Vector2, color_from: Color, color_to: Color, opacity: float = 1.0, mask: Image = null) -> bool:
	if not _valid(image, source, mask):
		return false
	var direction := to - from
	if direction.length_squared() < 0.000001:
		return false
	var changed := false
	for y in image.get_height():
		for x in image.get_width():
			if not _allowed(mask, x, y):
				continue
			var delta := _wrapped_delta(image, Vector2(x + 0.5, y + 0.5) - (from + to) * 0.5) + direction * 0.5
			var t := clampf(delta.dot(direction) / direction.length_squared(), 0, 1)
			var color := _mix(color_from, color_to, t)
			changed = _write(image, x, y, _over(source.get_pixel(x, y), color, clampf(opacity, 0, 1))) or changed
	return changed


# Four-neighbour flood fill. The mask blocks traversal, not just writes.
# Compare premultiplied RGBA so invisible RGB does not split transparent regions.
static func contiguous_fill(image: Image, source: Image, seed: Vector2, color: Color, opacity: float = 1.0, tolerance: float = 0.0, mask: Image = null) -> bool:
	if not _valid(image, source, mask):
		return false
	var w := image.get_width()
	var h := image.get_height()
	var x0 := posmod(int(floor(seed.x)), w)
	var y0 := posmod(int(floor(seed.y)), h)
	if not _allowed(mask, x0, y0):
		return false
	var target := _premultiply(source.get_pixel(x0, y0))
	var visited := PackedByteArray()
	visited.resize(w * h)
	var pending := PackedInt32Array([y0 * w + x0])
	visited[y0 * w + x0] = 1
	var cursor := 0
	var changed := false
	while cursor < pending.size():
		var key := pending[cursor]
		cursor += 1
		var x := key % w
		var y := key / w
		var sample := source.get_pixel(x, y)
		if not _allowed(mask, x, y) or not _matches(_premultiply(sample), target, clampf(tolerance, 0, 1)):
			continue
		changed = _write(image, x, y, _over(image.get_pixel(x, y), color, clampf(opacity, 0, 1))) or changed
		for next in [y * w + posmod(x - 1, w), y * w + posmod(x + 1, w), posmod(y - 1, h) * w + x, posmod(y + 1, h) * w + x]:
			if visited[next] == 0:
				visited[next] = 1
				pending.append(next)
	return changed


static func _valid(image: Image, source: Image, mask: Image) -> bool:
	return image != null and source != null and not image.is_empty() and not source.is_empty() \
		and not image.is_compressed() and not source.is_compressed() and image.get_size() == source.get_size() \
		and (mask == null or (not mask.is_compressed() and mask.get_size() == image.get_size()))


static func _allowed(mask: Image, x: int, y: int) -> bool:
	return mask == null or mask.get_pixel(x, y).r >= 0.5


static func _coverage(image: Image, center: Vector2, radius: float, hardness: float, mask: Image) -> Dictionary:
	var coverage: Dictionary = {}
	if radius <= 0.0:
		return coverage
	var w := image.get_width()
	var h := image.get_height()
	var x0 := int(floor(center.x - radius))
	var y0 := int(floor(center.y - radius))
	for iy in mini(h, int(ceil(radius * 2.0)) + 2):
		var y := posmod(y0 + iy, h)
		for ix in mini(w, int(ceil(radius * 2.0)) + 2):
			var x := posmod(x0 + ix, w)
			if not _allowed(mask, x, y):
				continue
			var weight := _weight(image, center, Vector2(x + 0.5, y + 0.5), radius, hardness)
			if weight > 0.0:
				coverage[y * w + x] = weight
	return coverage


static func _weight(image: Image, center: Vector2, point: Vector2, radius: float, hardness: float) -> float:
	var distance := _wrapped_delta(image, point - center).length() / radius
	if distance > 1.0:
		return 0.0
	hardness = clampf(hardness, 0, 1)
	return 1.0 if distance <= hardness else (1.0 - distance) / (1.0 - hardness)


static func _wrapped_delta(image: Image, delta: Vector2) -> Vector2:
	return Vector2(wrapf(delta.x, -image.get_width() * 0.5, image.get_width() * 0.5),
		wrapf(delta.y, -image.get_height() * 0.5, image.get_height() * 0.5))


# Bilinear sampling operates on premultiplied values, avoiding dark fringes.
static func _sample(image: Image, point: Vector2, wrap: bool = true) -> Color:
	var p := point - Vector2(0.5, 0.5)
	var x := int(floor(p.x))
	var y := int(floor(p.y))
	var fx := p.x - x
	var fy := p.y - y
	var a := _premultiply(_texel(image, x, y, wrap)).lerp(_premultiply(_texel(image, x + 1, y, wrap)), fx)
	var b := _premultiply(_texel(image, x, y + 1, wrap)).lerp(_premultiply(_texel(image, x + 1, y + 1, wrap)), fx)
	return _unpremultiply(a.lerp(b, fy))


static func _texel(image: Image, x: int, y: int, wrap: bool) -> Color:
	if wrap:
		return image.get_pixel(posmod(x, image.get_width()), posmod(y, image.get_height()))
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return Color.TRANSPARENT
	return image.get_pixel(x, y)


static func _premultiply(color: Color) -> Color:
	return Color(color.r * color.a, color.g * color.a, color.b * color.a, color.a)


static func _unpremultiply(color: Color) -> Color:
	return Color(color.r / color.a, color.g / color.a, color.b / color.a, color.a) if color.a > 0.000001 else Color.TRANSPARENT


static func _mix(a: Color, b: Color, weight: float) -> Color:
	return _unpremultiply(_premultiply(a).lerp(_premultiply(b), clampf(weight, 0, 1)))


static func _over(dst: Color, src: Color, weight: float) -> Color:
	var alpha := src.a * weight
	return _unpremultiply(Color(src.r * alpha, src.g * alpha, src.b * alpha, alpha) + _premultiply(dst) * (1.0 - alpha))


static func _matches(a: Color, b: Color, tolerance: float) -> bool:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))) <= tolerance


static func _write(image: Image, x: int, y: int, result: Color) -> bool:
	var before := image.get_pixel(x, y)
	if before == result:
		return false
	image.set_pixel(x, y, result)
	return image.get_pixel(x, y) != before
