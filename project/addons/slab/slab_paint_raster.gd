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


static func stamp(image: Image, center: Vector2, radius: float, color: Color, opacity: float) -> void:
	if image == null or image.is_empty() or radius <= 0.0 or opacity <= 0.0:
		return
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var w: int = image.get_width()
	var h: int = image.get_height()
	var r: float = maxf(0.5, radius)
	var r2: float = r * r
	var min_x: int = int(floor(center.x - r - 1.0))
	var max_x: int = int(ceil(center.x + r + 1.0))
	var min_y: int = int(floor(center.y - r - 1.0))
	var max_y: int = int(ceil(center.y + r + 1.0))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx: float = float(x) + 0.5 - center.x
			var dy: float = float(y) + 0.5 - center.y
			var d2: float = dx * dx + dy * dy
			if d2 > r2:
				continue
			var falloff: float = 1.0 - sqrt(d2) / r
			var a: float = clampf(opacity * falloff, 0.0, 1.0)
			var px: int = posmod(x, w)
			var py: int = posmod(y, h)
			var dst: Color = image.get_pixel(px, py)
			image.set_pixel(px, py, dst.lerp(color, a))


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


static func stroke(image: Image, from: Vector2, to: Vector2, radius: float, color: Color, opacity: float) -> void:
	var spacing: float = maxf(0.5, radius * 0.45)
	for dab in interpolate(from, to, spacing):
		stamp(image, dab, radius, color, opacity)
