@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabTopology := preload("res://addons/slab/slab_topology.gd")

const BASE_RADIUS := 24.0

const POSITION_QUERY: Dictionary = {
	SlabSelection.Mode.VERTEX: "vertex_position",
	SlabSelection.Mode.EDGE: "edge_endpoints",
	SlabSelection.Mode.FACE: "face_corners",
}


static func pick(solid: Node3D, mode: int, camera: Camera3D, screen: Vector2, radius: float = BASE_RADIUS) -> int:
	var found := candidates(solid, mode, camera, screen, radius, true)
	return int(found[0].get("id", 0)) if not found.is_empty() else 0


static func candidates(solid: Node3D, mode: int, camera: Camera3D, screen: Vector2,
		radius: float = BASE_RADIUS, visible_only: bool = true) -> Array[Dictionary]:
	if solid == null or camera == null or not POSITION_QUERY.has(mode):
		return []
	var list := SlabTopology.query_for(mode)
	if not solid.has_method(list) or not solid.has_method(POSITION_QUERY[mode]):
		return []
	if mode == SlabSelection.Mode.FACE:
		return _face_candidates(solid, camera, screen, visible_only)
	if mode == SlabSelection.Mode.EDGE:
		return _edge_candidates(solid, camera, screen, radius, visible_only)
	return _vertex_candidates(solid, camera, screen, radius, visible_only)


static func pick_solid(root: Node, camera: Camera3D, screen: Vector2) -> Node3D:
	if root == null or camera == null:
		return null
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	if direction.length_squared() < 0.0001:
		return null
	var best: Node3D = null
	var best_depth: float = INF
	for solid in all_solids(root):
		var depth: float = _ray_depth(solid, origin, direction)
		if depth >= 0.0 and depth < best_depth:
			best_depth = depth
			best = solid
	return best


static func scene_candidates(root: Node, mode: int, camera: Camera3D, screen: Vector2,
		radius: float = BASE_RADIUS, visible_only: bool = true) -> Array[Dictionary]:
	if root == null or camera == null:
		return []
	var out: Array[Dictionary] = []
	var solids := all_solids(root)
	for solid_index in solids.size():
		var solid: Node3D = solids[solid_index]
		for item in candidates(solid, mode, camera, screen, radius, false):
			var candidate: Dictionary = item.duplicate()
			candidate["solid"] = solid
			candidate["solid_order"] = solid_index
			var world: Vector3 = candidate.get("world", Vector3.ZERO)
			var at_screen := camera.unproject_position(world)
			var origin := camera.project_ray_origin(at_screen)
			var surface_depth := _world_ray_depth(root, origin, camera.project_ray_normal(at_screen))
			var visible := surface_depth < 0.0 or origin.distance_to(world) <= surface_depth + 0.002
			candidate["visible"] = visible
			if not visible_only or visible:
				out.append(candidate)
	_sort_candidates(out)
	return out


static func all_solids(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	_collect_solids(root, out)
	return out


static func _collect_solids(node: Node, out: Array[Node3D]) -> void:
	if node is Node3D and SlabSelection.is_solid(node):
		out.append(node)
	for child in node.get_children():
		_collect_solids(child, out)


static func _ray_depth(solid: Node3D, origin: Vector3, direction: Vector3) -> float:
	var best: float = -1.0
	for id in solid.get_faces():
		var corners: PackedVector3Array = solid.face_corners(id)
		if corners.size() < 3:
			continue
		var hit: Variant = _ray_face_hit(solid, id, corners, origin, direction)
		if hit == null:
			continue
		var depth: float = origin.distance_to(hit)
		if best < 0.0 or depth < best:
			best = depth
	return best


static func _world_ray_depth(root: Node, origin: Vector3, direction: Vector3) -> float:
	var best := -1.0
	for solid in all_solids(root):
		var depth := _ray_depth(solid, origin, direction)
		if depth >= 0.0 and (best < 0.0 or depth < best):
			best = depth
	return best


static func _pick_vertex(solid: Node3D, camera: Camera3D, screen: Vector2, radius: float) -> int:
	var found := _vertex_candidates(solid, camera, screen, radius, true)
	return int(found[0].get("id", 0)) if not found.is_empty() else 0


static func _vertex_candidates(solid: Node3D, camera: Camera3D, screen: Vector2, radius: float,
		visible_only: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in solid.get_vertices():
		var world: Vector3 = solid.to_global(solid.vertex_position(id))
		if camera.is_position_behind(world):
			continue
		var distance: float = camera.unproject_position(world).distance_to(screen)
		if distance > radius:
			continue
		var depth := camera.project_ray_origin(camera.unproject_position(world)).distance_to(world)
		var visible := _point_visible(solid, camera, camera.unproject_position(world), world)
		if visible_only and not visible:
			continue
		out.append({ "id": id, "distance": distance, "depth": depth, "visible": visible, "world": world })
	_sort_candidates(out)
	return out


static func _pick_edge(solid: Node3D, camera: Camera3D, screen: Vector2, radius: float) -> int:
	var found := _edge_candidates(solid, camera, screen, radius, true)
	return int(found[0].get("id", 0)) if not found.is_empty() else 0


static func _edge_candidates(solid: Node3D, camera: Camera3D, screen: Vector2, radius: float,
		visible_only: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in solid.get_edges():
		var ends: PackedVector3Array = solid.edge_endpoints(id)
		if ends.size() < 2:
			continue
		var a_world: Vector3 = solid.to_global(ends[0])
		var b_world: Vector3 = solid.to_global(ends[1])
		if camera.is_position_behind(a_world) and camera.is_position_behind(b_world):
			continue
		var a_screen := camera.unproject_position(a_world)
		var b_screen := camera.unproject_position(b_world)
		var t := _screen_segment_t(screen, a_screen, b_screen)
		var nearest_screen := a_screen.lerp(b_screen, t)
		var distance: float = nearest_screen.distance_to(screen)
		if distance > radius:
			continue
		var world := a_world.lerp(b_world, t)
		var depth := camera.project_ray_origin(nearest_screen).distance_to(world)
		var visible := _point_visible(solid, camera, nearest_screen, world)
		if visible_only and not visible:
			continue
		out.append({ "id": id, "distance": distance, "depth": depth, "visible": visible, "world": world })
	_sort_candidates(out)
	return out


static func pick_face_hit(solid: Node3D, camera: Camera3D, screen: Vector2) -> Dictionary:
	var found := _face_candidates(solid, camera, screen, true)
	return found[0].duplicate() if not found.is_empty() else {}


static func _face_candidates(solid: Node3D, camera: Camera3D, screen: Vector2,
		visible_only: bool) -> Array[Dictionary]:
	if solid == null or camera == null:
		return []
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var by_id: Dictionary = {}
	for id in solid.get_faces():
		var corners: PackedVector3Array = solid.face_corners(id)
		if corners.size() < 3:
			continue
		var hit: Variant = _ray_face_hit(solid, id, corners, origin, direction)
		if hit == null:
			continue
		var depth: float = origin.distance_to(hit)
		by_id[id] = { "id": id, "world": hit, "local": solid.to_local(hit),
			"depth": depth, "distance": 0.0, "visible": true }
	var out: Array[Dictionary] = []
	for hit in by_id.values():
		out.append(hit)
	_sort_candidates(out)
	if not out.is_empty():
		var nearest: float = float(out[0]["depth"])
		for item in out:
			item["visible"] = absf(float(item["depth"]) - nearest) <= 0.002
		if visible_only:
			out = out.filter(func(item: Dictionary) -> bool: return bool(item["visible"]))
	return out


static func pick_world_hit(root: Node, camera: Camera3D, screen: Vector2, excluded: Node3D = null) -> Dictionary:
	var best: Dictionary = {}
	var best_depth: float = INF
	for solid in all_solids(root):
		if solid == excluded:
			continue
		var hit: Dictionary = pick_face_hit(solid, camera, screen)
		if hit.is_empty():
			continue
		var depth: float = float(hit["depth"])
		if depth < best_depth:
			best_depth = depth
			best = hit.duplicate()
			best["solid"] = solid
	return best


static func _pick_face(solid: Node3D, camera: Camera3D, screen: Vector2) -> int:
	var hit: Dictionary = pick_face_hit(solid, camera, screen)
	return int(hit.get("id", 0))


static func _screen_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(a.lerp(b, _screen_segment_t(point, a, b)))


static func _screen_segment_t(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_sq: float = ab.length_squared()
	if length_sq < 0.0001:
		return 0.0
	return clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)


static func _point_visible(solid: Node3D, camera: Camera3D, screen: Vector2, world: Vector3) -> bool:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var surface_depth := _ray_depth(solid, origin, direction)
	return surface_depth < 0.0 or origin.distance_to(world) <= surface_depth + 0.002


static func _ray_face_hit(solid: Node3D, face: int, corners: PackedVector3Array,
		origin: Vector3, direction: Vector3) -> Variant:
	var local_normal: Vector3 = solid.face_normal(face)
	var normal: Vector3 = solid.global_transform.basis.inverse().transposed() * local_normal
	normal = normal.normalized()
	var plane_point := solid.to_global(corners[0])
	var denominator := normal.dot(direction)
	if absf(denominator) < 0.000001:
		return null
	var t := normal.dot(plane_point - origin) / denominator
	if t < 0.0:
		return null
	var hit := origin + direction * t
	var local_hit := solid.to_local(hit)
	var polygon := PackedVector2Array()
	var abs_normal := Vector3(absf(local_normal.x), absf(local_normal.y), absf(local_normal.z))
	var drop_axis := 0 if abs_normal.x >= abs_normal.y and abs_normal.x >= abs_normal.z else (1 if abs_normal.y >= abs_normal.z else 2)
	for corner in corners:
		polygon.append(_drop_axis(corner, drop_axis))
	return hit if Geometry2D.is_point_in_polygon(_drop_axis(local_hit, drop_axis), polygon) else null


static func _drop_axis(point: Vector3, axis: int) -> Vector2:
	if axis == 0:
		return Vector2(point.y, point.z)
	if axis == 1:
		return Vector2(point.x, point.z)
	return Vector2(point.x, point.y)


static func _sort_candidates(items: Array[Dictionary]) -> void:
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var distance_delta := float(a["distance"]) - float(b["distance"])
		if absf(distance_delta) > 0.0001:
			return distance_delta < 0.0
		var depth_delta := float(a["depth"]) - float(b["depth"])
		if absf(depth_delta) > 0.0001:
			return depth_delta < 0.0
		if int(a.get("solid_order", 0)) != int(b.get("solid_order", 0)):
			return int(a.get("solid_order", 0)) < int(b.get("solid_order", 0))
		return int(a["id"]) < int(b["id"])
	)
