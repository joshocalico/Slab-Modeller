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
	if solid == null or camera == null or not POSITION_QUERY.has(mode):
		return 0
	var list := SlabTopology.query_for(mode)
	if not solid.has_method(list) or not solid.has_method(POSITION_QUERY[mode]):
		return 0
	if mode == SlabSelection.Mode.FACE:
		return _pick_face(solid, camera, screen)
	if mode == SlabSelection.Mode.EDGE:
		return _pick_edge(solid, camera, screen, radius)
	return _pick_vertex(solid, camera, screen, radius)


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
		var a: Vector3 = solid.to_global(corners[0])
		for i in range(1, corners.size() - 1):
			var hit: Variant = Geometry3D.ray_intersects_triangle(
				origin,
				direction,
				a,
				solid.to_global(corners[i]),
				solid.to_global(corners[i + 1])
			)
			if hit == null:
				continue
			var depth: float = origin.distance_to(hit)
			if best < 0.0 or depth < best:
				best = depth
	return best


static func _pick_vertex(solid: Node3D, camera: Camera3D, screen: Vector2, radius: float) -> int:
	var best: int = 0
	var best_score: float = radius
	for id in solid.get_vertices():
		var world: Vector3 = solid.to_global(solid.vertex_position(id))
		if camera.is_position_behind(world):
			continue
		var distance: float = camera.unproject_position(world).distance_to(screen)
		if distance < best_score:
			best_score = distance
			best = id
	return best


static func _pick_edge(solid: Node3D, camera: Camera3D, screen: Vector2, radius: float) -> int:
	var best: int = 0
	var best_score: float = radius
	for id in solid.get_edges():
		var ends: PackedVector3Array = solid.edge_endpoints(id)
		var a_world: Vector3 = solid.to_global(ends[0])
		var b_world: Vector3 = solid.to_global(ends[1])
		if camera.is_position_behind(a_world) and camera.is_position_behind(b_world):
			continue
		var distance: float = _screen_segment_distance(
			screen,
			camera.unproject_position(a_world),
			camera.unproject_position(b_world)
		)
		if distance < best_score:
			best_score = distance
			best = id
	return best


static func _pick_face(solid: Node3D, camera: Camera3D, screen: Vector2) -> int:
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var best: int = 0
	var best_depth: float = INF
	for id in solid.get_faces():
		var corners: PackedVector3Array = solid.face_corners(id)
		if corners.size() < 3:
			continue
		var a: Vector3 = solid.to_global(corners[0])
		for i in range(1, corners.size() - 1):
			var hit: Variant = Geometry3D.ray_intersects_triangle(
				origin,
				direction,
				a,
				solid.to_global(corners[i]),
				solid.to_global(corners[i + 1])
			)
			if hit == null:
				continue
			var depth: float = origin.distance_to(hit)
			if depth < best_depth:
				best_depth = depth
				best = id
	return best


static func _screen_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_sq: float = ab.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)
