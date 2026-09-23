@tool
extends RefCounted

const PaintUv := preload("res://addons/slab/slab_paint_uv.gd")


static func rasterize(solid: Node3D, faces: PackedInt64Array, size: Vector2i) -> Image:
	var triangles: Array[PackedVector2Array] = []
	for face in faces:
		var data: Dictionary = solid.call("face_uv", face)
		var points: PackedVector2Array = data.get("points", PackedVector2Array())
		var indices: PackedInt32Array = data.get("triangles", PackedInt32Array())
		for i in range(0, indices.size(), 3):
			triangles.append(PackedVector2Array([points[indices[i]], points[indices[i + 1]], points[indices[i + 2]]]))
	return rasterize_triangles(triangles, size)


static func rasterize_triangles(triangles: Array[PackedVector2Array], size: Vector2i) -> Image:
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	mask.fill(Color.BLACK)
	for triangle in triangles:
		for tile: PackedVector2Array in PaintUv.tiled_loops(triangle):
			_fill_polygon(mask, tile)
	return mask


static func _fill_polygon(mask: Image, polygon: PackedVector2Array) -> void:
	if polygon.size() < 3:
		return
	var size := Vector2(mask.get_size())
	var bounds := Rect2(polygon[0] * size, Vector2.ZERO)
	var pixels := PackedVector2Array()
	for point in polygon:
		pixels.append(point * size)
		bounds = bounds.expand(point * size)
	for y in range(maxi(0, int(floor(bounds.position.y))), mini(mask.get_height(), int(ceil(bounds.end.y)))):
		for x in range(maxi(0, int(floor(bounds.position.x))), mini(mask.get_width(), int(ceil(bounds.end.x)))):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pixels):
				mask.set_pixel(x, y, Color.WHITE)
