@tool
extends RefCounted


static func clone_rgba(image: Image) -> Image:
	if image == null or image.is_empty():
		return image
	var copy: Image = image.duplicate()
	if copy.is_compressed():
		copy.decompress()
	if copy.get_format() != Image.FORMAT_RGBA8:
		copy.convert(Image.FORMAT_RGBA8)
	return copy


static func stamp(image: Image, center: Vector2, radius: float, color: Color, opacity: float, hardness: float = 0.0, erase: bool = false, mask: Image = null) -> bool:
	if image == null or image.is_empty() or radius <= 0.0 or opacity <= 0.0:
		return false
	var w := image.get_width()
	var h := image.get_height()
	var r := maxf(0.5, radius)
	hardness = clampf(hardness, 0.0, 1.0)
	var coverage: Dictionary = {}
	for y in range(int(floor(center.y - r)), int(ceil(center.y + r)) + 1):
		for x in range(int(floor(center.x - r)), int(ceil(center.x + r)) + 1):
			var distance := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center) / r
			if distance > 1.0:
				continue
			var px := posmod(x, w)
			var py := posmod(y, h)
			if mask != null and mask.get_pixel(px, py).r < 0.5:
				continue
			var falloff := 1.0 if distance <= hardness else (1.0 - distance) / (1.0 - hardness)
			var key := py * w + px
			# A large wrapped brush may visit a texel repeatedly. Apply its strongest coverage once.
			coverage[key] = maxf(float(coverage.get(key, 0.0)), falloff)
	var changed := false
	for key: int in coverage:
		var px := key % w
		var py := key / w
		var dst := image.get_pixel(px, py)
		var weight := clampf(opacity * float(coverage[key]), 0.0, 1.0)
		var result := dst
		if erase:
			result.a *= 1.0 - weight
			if result.a <= 0.0:
				result = Color.TRANSPARENT
		else:
			var alpha := color.a * weight
			var combined := alpha + dst.a * (1.0 - alpha)
			if combined > 0.0:
				result = Color((color.r * alpha + dst.r * dst.a * (1.0 - alpha)) / combined,
					(color.g * alpha + dst.g * dst.a * (1.0 - alpha)) / combined,
					(color.b * alpha + dst.b * dst.a * (1.0 - alpha)) / combined, combined)
		if result != dst:
			image.set_pixel(px, py, result)
			changed = true
	return changed


static func interpolate(from: Vector2, to: Vector2, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(from)
	var dist: float = from.distance_to(to)
	if dist < 0.001:
		return out
	var step: float = maxf(0.5, spacing)
	var n: int = maxi(1, int(ceil(dist / step)))
	for i in range(1, n + 1):
		out.append(from.lerp(to, float(i) / float(n)))
	return out


static func stroke(image: Image, from: Vector2, to: Vector2, radius: float, color: Color, opacity: float, hardness: float = 0.0, erase: bool = false, mask: Image = null) -> bool:
	var changed := false
	var spacing: float = maxf(0.5, radius * 0.45)
	for dab in interpolate(from, to, spacing):
		changed = stamp(image, dab, radius, color, opacity, hardness, erase, mask) or changed
	return changed
