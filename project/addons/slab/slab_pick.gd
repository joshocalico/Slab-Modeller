@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabTopology := preload("res://addons/slab/slab_topology.gd")

const SCREEN_RADIUS := 14.0

const POSITION_QUERY: Dictionary = {
	SlabSelection.Mode.VERTEX: "vertex_position",
	SlabSelection.Mode.EDGE: "edge_endpoints",
	SlabSelection.Mode.FACE: "face_corners",
}


static func pick(solid: Node3D, mode: int, camera: Camera3D, screen: Vector2) -> int:
	if solid == null or camera == null or not POSITION_QUERY.has(mode):
		return 0
	var list := SlabTopology.query_for(mode)
	if not solid.has_method(list) or not solid.has_method(POSITION_QUERY[mode]):
		return 0
	if mode == SlabSelection.Mode.FACE:
		return _pick_face(solid, camera, screen)
	return _pick_point(solid, mode, camera, screen)


static func _pick_point(solid: Node3D, mode: int, camera: Camera3D, screen: Vector2) -> int:
	var best: int = 0
	var best_score: float = SCREEN_RADIUS
	for id in solid.call(SlabTopology.query_for(mode)):
		var world: Vector3 = _anchor(solid, mode, id)
		if camera.is_position_behind(world):
			continue
		var distance: float = camera.unproject_position(world).distance_to(screen)
		if distance < best_score:
			best_score = distance
			best = id
	return best


static func _pick_face(solid: Node3D, camera: Camera3D, screen: Vector2) -> int:
	var best: int = 0
	var best_depth: float = INF
	var eye: Vector3 = camera.global_position
	for id in solid.get_faces():
		var corners: PackedVector3Array = solid.face_corners(id)
		if corners.size() < 3:
			continue
		var outline := PackedVector2Array()
		var behind := false
		for corner in corners:
			var world: Vector3 = solid.to_global(corner)
			if camera.is_position_behind(world):
				behind = true
				break
			outline.append(camera.unproject_position(world))
		if behind or not Geometry2D.is_point_in_polygon(screen, outline):
			continue
		var depth: float = eye.distance_to(solid.to_global(solid.face_centroid(id)))
		if depth < best_depth:
			best_depth = depth
			best = id
	return best


static func _anchor(solid: Node3D, mode: int, id: int) -> Vector3:
	if mode == SlabSelection.Mode.VERTEX:
		return solid.to_global(solid.vertex_position(id))
	var ends: PackedVector3Array = solid.edge_endpoints(id)
	return solid.to_global((ends[0] + ends[1]) * 0.5)
