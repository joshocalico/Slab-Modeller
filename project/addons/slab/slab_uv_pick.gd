@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabPaintUv := preload("res://addons/slab/slab_paint_uv.gd")

const PICK_RADIUS := 12.0


static func pick_uv_element(solid: Node3D, faces: PackedInt64Array, uv_mode: int,
		canvas_pos: Vector2, uv_to_canvas: Callable, radius: float = PICK_RADIUS) -> Dictionary:
	if solid == null or faces.is_empty():
		return {}
	
	match uv_mode:
		SlabSelection.UVMode.UV_VERT:
			return _pick_uv_vert(solid, faces, canvas_pos, uv_to_canvas, radius)
		SlabSelection.UVMode.UV_EDGE:
			return _pick_uv_edge(solid, faces, canvas_pos, uv_to_canvas, radius)
		SlabSelection.UVMode.UV_FACE:
			return _pick_uv_face(solid, faces, canvas_pos, uv_to_canvas)
	return {}


static func _pick_uv_vert(solid: Node3D, faces: PackedInt64Array, canvas_pos: Vector2,
		uv_to_canvas: Callable, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	var vert_index := 0
	
	for face in faces:
		var uvs := SlabPaintUv.face_uvs(solid, face)
		for i in uvs.size():
			var uv := uvs[i]
			var canvas_pt: Vector2 = uv_to_canvas.call(uv)
			var dist := canvas_pos.distance_to(canvas_pt)
			if dist <= radius and dist < best_dist:
				best_dist = dist
				best = {
					"type": "vert",
					"face": face,
					"corner": i,
					"uv": uv,
					"id": _encode_uv_vert(solid, face, i),
				}
		vert_index += uvs.size()
	
	return best


static func _pick_uv_edge(solid: Node3D, faces: PackedInt64Array, canvas_pos: Vector2,
		uv_to_canvas: Callable, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	
	for face in faces:
		var uvs := SlabPaintUv.face_uvs(solid, face)
		if uvs.size() < 2:
			continue
		for i in uvs.size():
			var uv_a := uvs[i]
			var uv_b := uvs[(i + 1) % uvs.size()]
			var canvas_a: Vector2 = uv_to_canvas.call(uv_a)
			var canvas_b: Vector2 = uv_to_canvas.call(uv_b)
			var dist := _point_to_segment_distance(canvas_pos, canvas_a, canvas_b)
			if dist <= radius and dist < best_dist:
				best_dist = dist
				best = {
					"type": "edge",
					"face": face,
					"edge_index": i,
					"uv_a": uv_a,
					"uv_b": uv_b,
					"id": _encode_uv_edge(solid, face, i),
				}
	
	return best


static func _pick_uv_face(solid: Node3D, faces: PackedInt64Array, canvas_pos: Vector2,
		uv_to_canvas: Callable) -> Dictionary:
	for face in faces:
		var uvs := SlabPaintUv.face_uvs(solid, face)
		if uvs.size() < 3:
			continue
		var canvas_poly := PackedVector2Array()
		for uv in uvs:
			canvas_poly.append(uv_to_canvas.call(uv))
		var triangles: PackedInt32Array = solid.face_uv(face)["triangles"]
		for i in range(0, triangles.size(), 3):
			var triangle := PackedVector2Array([canvas_poly[triangles[i]], canvas_poly[triangles[i + 1]], canvas_poly[triangles[i + 2]]])
			if Geometry2D.is_point_in_polygon(canvas_pos, triangle):
				return {"type": "face", "face": face, "id": face}
	return {}


static func _point_to_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a.lerp(b, t))


static func _encode_uv_vert(solid: Node3D, face: int, corner: int) -> int:
	return solid.face_uv(face)["ids"][corner]


static func _decode_uv_vert(solid: Node3D, id: int) -> Dictionary:
	return solid.uv_corner(id)


static func _encode_uv_edge(solid: Node3D, face: int, edge_index: int) -> int:
	return solid.face_uv(face)["ids"][edge_index]


static func _decode_uv_edge(solid: Node3D, id: int) -> Dictionary:
	return solid.uv_corner(id)


static func box_select_uv_elements(solid: Node3D, faces: PackedInt64Array, uv_mode: int,
		rect: Rect2, uv_to_canvas: Callable) -> PackedInt64Array:
	var result := PackedInt64Array()
	if solid == null or faces.is_empty():
		return result
	
	match uv_mode:
		SlabSelection.UVMode.UV_VERT:
			return _box_select_uv_verts(solid, faces, rect, uv_to_canvas)
		SlabSelection.UVMode.UV_EDGE:
			return _box_select_uv_edges(solid, faces, rect, uv_to_canvas)
		SlabSelection.UVMode.UV_FACE:
			return _box_select_uv_faces(solid, faces, rect, uv_to_canvas)
	return result


static func _box_select_uv_verts(solid: Node3D, faces: PackedInt64Array, rect: Rect2,
		uv_to_canvas: Callable) -> PackedInt64Array:
	var result := PackedInt64Array()
	
	for face in faces:
		var uvs := SlabPaintUv.face_uvs(solid, face)
		for i in uvs.size():
			var uv := uvs[i]
			var canvas_pt: Vector2 = uv_to_canvas.call(uv)
			if rect.has_point(canvas_pt):
				result.append(_encode_uv_vert(solid, face, i))
	
	return result


static func _box_select_uv_edges(solid: Node3D, faces: PackedInt64Array, rect: Rect2,
		uv_to_canvas: Callable) -> PackedInt64Array:
	var result := PackedInt64Array()
	
	for face in faces:
		var uvs := SlabPaintUv.face_uvs(solid, face)
		if uvs.size() < 2:
			continue
		for i in uvs.size():
			var uv_a := uvs[i]
			var uv_b := uvs[(i + 1) % uvs.size()]
			var canvas_a: Vector2 = uv_to_canvas.call(uv_a)
			var canvas_b: Vector2 = uv_to_canvas.call(uv_b)
			if rect.has_point(canvas_a) and rect.has_point(canvas_b):
				result.append(_encode_uv_edge(solid, face, i))
	
	return result


static func _box_select_uv_faces(solid: Node3D, faces: PackedInt64Array, rect: Rect2,
		uv_to_canvas: Callable) -> PackedInt64Array:
	var result := PackedInt64Array()
	
	for face in faces:
		var uvs := SlabPaintUv.face_uvs(solid, face)
		if uvs.size() < 3:
			continue
		var all_inside := true
		for uv in uvs:
			var canvas_pt: Vector2 = uv_to_canvas.call(uv)
			if not rect.has_point(canvas_pt):
				all_inside = false
				break
		if all_inside:
			result.append(face)
	
	return result


static func get_related_3d_faces(solid: Node3D, uv_mode: int, uv_selection: PackedInt64Array) -> PackedInt64Array:
	var faces := PackedInt64Array()
	if solid == null or uv_selection.is_empty():
		return faces
	
	match uv_mode:
		SlabSelection.UVMode.UV_VERT:
			for id in uv_selection:
				var decoded := _decode_uv_vert(solid, id)
				if decoded.is_empty():
					continue
				if not faces.has(decoded["face"]):
					faces.append(decoded["face"])
		SlabSelection.UVMode.UV_EDGE:
			for id in uv_selection:
				var decoded := _decode_uv_edge(solid, id)
				if decoded.is_empty():
					continue
				if not faces.has(decoded["face"]):
					faces.append(decoded["face"])
		SlabSelection.UVMode.UV_FACE:
			faces = uv_selection
	
	return faces
