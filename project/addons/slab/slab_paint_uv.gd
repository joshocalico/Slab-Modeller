@tool
extends RefCounted

# Matches src/kernel/emit.cpp apply_uv / project_uv / dominant_axis.

const AXIS_AUTO := 0
const AXIS_X := 1
const AXIS_Y := 2
const AXIS_Z := 3


static func dominant_axis(normal: Vector3) -> int:
	var ax: float = absf(normal.x)
	var ay: float = absf(normal.y)
	var az: float = absf(normal.z)
	if az >= ax and az >= ay:
		return AXIS_Z
	if ay >= ax:
		return AXIS_Y
	return AXIS_X


static func project_uv(point: Vector3, axis: int) -> Vector2:
	match axis:
		AXIS_X:
			return Vector2(point.y, point.z)
		AXIS_Y:
			return Vector2(point.x, point.z)
		_:
			return Vector2(point.x, point.y)


static func apply_uv(point: Vector3, centroid: Vector2, scale: Vector2, offset: Vector2, rotation: float, axis: int) -> Vector2:
	var uv: Vector2 = project_uv(point, axis)
	return apply_projected_uv(uv, centroid, scale, offset, rotation)


static func apply_projected_uv(uv: Vector2, centroid: Vector2, scale: Vector2, offset: Vector2, rotation: float) -> Vector2:
	uv.x *= scale.x
	uv.y *= scale.y
	var c: Vector2 = centroid
	c.x *= scale.x
	c.y *= scale.y
	var s: float = sin(rotation)
	var co: float = cos(rotation)
	var d: Vector2 = uv - c
	uv = Vector2(d.x * co - d.y * s, d.x * s + d.y * co) + c
	uv += offset
	return uv


static func attrs_of(solid: Node3D, face: int) -> Dictionary:
	if solid == null or not solid.has_method("face_uv"):
		return {}
	return solid.face_uv(face)


static func resolved_axis(solid: Node3D, face: int) -> int:
	var attrs: Dictionary = attrs_of(solid, face)
	var axis: int = int(attrs.get("axis", AXIS_AUTO))
	if axis == AXIS_AUTO:
		return dominant_axis(solid.face_normal(face))
	return axis


static func point_uv(solid: Node3D, face: int, local_point: Vector3) -> Vector2:
	var attrs: Dictionary = attrs_of(solid, face)
	if bool(attrs.get("unwrapped", false)):
		var u: Vector3 = attrs["u"]
		var v: Vector3 = attrs["v"]
		var origin: Vector2 = attrs["origin"]
		var center: Vector3 = solid.face_centroid(face)
		return apply_projected_uv(Vector2(local_point.dot(u), local_point.dot(v)) + origin,
			Vector2(center.dot(u), center.dot(v)) + origin,
			attrs.get("scale", Vector2.ONE), attrs.get("offset", Vector2.ZERO),
			float(attrs.get("rotation", 0.0)))
	var axis: int = resolved_axis(solid, face)
	var centroid: Vector2 = project_uv(solid.face_centroid(face), axis)
	return apply_uv(
		local_point,
		centroid,
		attrs.get("scale", Vector2.ONE),
		attrs.get("offset", Vector2.ZERO),
		float(attrs.get("rotation", 0.0)),
		axis
	)


static func face_uvs(solid: Node3D, face: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if solid == null:
		return out
	for corner in solid.face_corners(face):
		out.append(point_uv(solid, face, corner))
	return out


static func wrap01(value: float) -> float:
	var wrapped: float = fposmod(value, 1.0)
	if wrapped < 0.0:
		wrapped += 1.0
	if wrapped >= 1.0:
		return 0.0
	return wrapped


static func uv_to_pixel(uv: Vector2, width: int, height: int) -> Vector2i:
	var w: int = maxi(1, width)
	var h: int = maxi(1, height)
	var x: int = int(floor(wrap01(uv.x) * float(w)))
	var y: int = int(floor(wrap01(uv.y) * float(h)))
	return Vector2i(clampi(x, 0, w - 1), clampi(y, 0, h - 1))


static func pixel_to_uv(pixel: Vector2, width: int, height: int) -> Vector2:
	return Vector2(pixel.x / float(maxi(1, width)), pixel.y / float(maxi(1, height)))


static func faces_camera(solid: Node3D, face: int, camera: Camera3D, world_hit: Vector3) -> bool:
	if solid == null or camera == null:
		return false
	var world_normal: Vector3 = (solid.global_transform.basis * solid.face_normal(face)).normalized()
	return world_normal.dot(camera.global_position - world_hit) > 0.0


static func crosses_wrap(uvs: PackedVector2Array) -> bool:
	return tiled_loops(uvs).size() > 1


static func tiled_loops(uvs: PackedVector2Array) -> Array:
	var loops: Array = []
	if uvs.size() < 2:
		return loops
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for uv in uvs:
		mn.x = minf(mn.x, uv.x)
		mn.y = minf(mn.y, uv.y)
		mx.x = maxf(mx.x, uv.x)
		mx.y = maxf(mx.y, uv.y)
	var ox0: int = int(floor(mn.x))
	var oy0: int = int(floor(mn.y))
	var ox1: int = int(floor(mx.x - 0.0000001))
	var oy1: int = int(floor(mx.y - 0.0000001))
	for ox in range(ox0, ox1 + 1):
		for oy in range(oy0, oy1 + 1):
			var shifted := PackedVector2Array()
			for uv in uvs:
				shifted.append(uv - Vector2(ox, oy))
			var clipped: PackedVector2Array = clip_to_unit(shifted)
			if clipped.size() >= 2:
				loops.append(clipped)
	return loops


static func clip_to_unit(poly: PackedVector2Array) -> PackedVector2Array:
	var clipped: PackedVector2Array = poly
	clipped = _clip_halfplane(clipped, Vector2(1, 0), 0.0)
	clipped = _clip_halfplane(clipped, Vector2(-1, 0), -1.0)
	clipped = _clip_halfplane(clipped, Vector2(0, 1), 0.0)
	clipped = _clip_halfplane(clipped, Vector2(0, -1), -1.0)
	return clipped


static func _clip_halfplane(poly: PackedVector2Array, normal: Vector2, constant: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if poly.is_empty():
		return out
	var prev: Vector2 = poly[poly.size() - 1]
	var prev_in: bool = normal.dot(prev) >= constant - 0.0000001
	for curr in poly:
		var curr_in: bool = normal.dot(curr) >= constant - 0.0000001
		if curr_in:
			if not prev_in:
				out.append(_intersect_halfplane(prev, curr, normal, constant))
			out.append(curr)
		elif prev_in:
			out.append(_intersect_halfplane(prev, curr, normal, constant))
		prev = curr
		prev_in = curr_in
	return out


static func _intersect_halfplane(a: Vector2, b: Vector2, normal: Vector2, constant: float) -> Vector2:
	var da: float = normal.dot(a) - constant
	var db: float = normal.dot(b) - constant
	var denom: float = da - db
	if absf(denom) < 0.0000001:
		return b
	return a.lerp(b, da / denom)
