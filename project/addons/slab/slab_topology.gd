@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")

const ELEMENT_QUERY: Dictionary = {
	SlabSelection.Mode.VERTEX: "get_vertices",
	SlabSelection.Mode.EDGE: "get_edges",
	SlabSelection.Mode.FACE: "get_faces",
}


static func query_for(mode: int) -> String:
	return ELEMENT_QUERY.get(mode, "get_faces")


static func all_ids(solid: Node3D, mode: int) -> PackedInt64Array:
	if solid == null or not ELEMENT_QUERY.has(mode):
		return PackedInt64Array()
	return solid.call(ELEMENT_QUERY[mode])


static func invert(solid: Node3D, mode: int, ids: PackedInt64Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for id in all_ids(solid, mode):
		if ids.find(id) == -1:
			out.append(id)
	return out


static func grow(solid: Node3D, mode: int, ids: PackedInt64Array) -> PackedInt64Array:
	if ids.is_empty():
		return ids
	if mode == SlabSelection.Mode.FACE:
		return _grow_faces(solid, ids)
	if mode == SlabSelection.Mode.EDGE:
		return _grow_edges(solid, ids)
	if mode == SlabSelection.Mode.VERTEX:
		return _grow_vertices(solid, ids)
	return ids


static func connected_coplanar_faces(solid: Node3D, seeds: PackedInt64Array, tolerance: float = 0.0001) -> PackedInt64Array:
	if solid == null or seeds.is_empty():
		return PackedInt64Array()
	var out := PackedInt64Array(seeds)
	var queued: Dictionary = {}
	for face in seeds:
		queued[face] = true
	var cursor := 0
	while cursor < out.size():
		var face: int = out[cursor]
		cursor += 1
		var normal: Vector3 = solid.call("face_normal", face)
		var plane_offset: float = normal.dot(solid.call("face_centroid", face))
		for edge in solid.call("face_edges", face):
			for neighbour in solid.call("edge_faces", edge):
				if queued.has(neighbour):
					continue
				var other_normal: Vector3 = solid.call("face_normal", neighbour)
				var other_offset: float = other_normal.dot(solid.call("face_centroid", neighbour))
				if normal.dot(other_normal) >= 1.0 - tolerance and absf(plane_offset - other_offset) <= tolerance:
					queued[neighbour] = true
					out.append(neighbour)
	return out


static func edge_ring(solid: Node3D, start: int) -> PackedInt64Array:
	var seen: Dictionary = { start: true }
	var out := PackedInt64Array([start])
	for face in solid.edge_faces(start):
		var edge: int = start
		var current: int = face
		while true:
			var next_edge: int = _opposite_edge(solid, current, edge)
			if next_edge == 0 or seen.has(next_edge):
				break
			seen[next_edge] = true
			out.append(next_edge)
			var across: int = _other_face(solid, next_edge, current)
			if across == 0:
				break
			edge = next_edge
			current = across
	return out


static func edge_loop(solid: Node3D, start: int) -> PackedInt64Array:
	var seen: Dictionary = { start: true }
	var out := PackedInt64Array([start])
	var index: Dictionary = _edges_by_corner(solid)
	for end_index in [0, 1]:
		var edge: int = start
		var corner: Vector3 = solid.edge_endpoints(start)[end_index]
		while true:
			var next_edge: int = _continue_across(solid, index, edge, corner)
			if next_edge == 0 or seen.has(next_edge):
				break
			seen[next_edge] = true
			out.append(next_edge)
			corner = _far_corner(solid, next_edge, corner)
			edge = next_edge
	return out


static func _grow_faces(solid: Node3D, ids: PackedInt64Array) -> PackedInt64Array:
	var out := PackedInt64Array(ids)
	for face in ids:
		for edge in solid.face_edges(face):
			for neighbour in solid.edge_faces(edge):
				if out.find(neighbour) == -1:
					out.append(neighbour)
	return out


static func _grow_edges(solid: Node3D, ids: PackedInt64Array) -> PackedInt64Array:
	var index: Dictionary = _edges_by_corner(solid)
	var out := PackedInt64Array(ids)
	for edge in ids:
		for corner in solid.edge_endpoints(edge):
			for touching in index.get(corner, []):
				if out.find(touching) == -1:
					out.append(touching)
	return out


static func _grow_vertices(solid: Node3D, ids: PackedInt64Array) -> PackedInt64Array:
	var by_position: Dictionary = {}
	for vertex in solid.get_vertices():
		by_position[solid.vertex_position(vertex)] = vertex
	var chosen: Dictionary = {}
	for vertex in ids:
		chosen[solid.vertex_position(vertex)] = true
	var out := PackedInt64Array(ids)
	for edge in solid.get_edges():
		var ends: PackedVector3Array = solid.edge_endpoints(edge)
		for side in [0, 1]:
			if not chosen.has(ends[side]):
				continue
			var far: Vector3 = ends[1 - side]
			if not by_position.has(far):
				continue
			var id: int = by_position[far]
			if out.find(id) == -1:
				out.append(id)
	return out


# Corner positions come back dequantized from the same integer lattice, so two
# half-edges meeting at one vertex produce bit-identical floats and hash equal.
static func _edges_by_corner(solid: Node3D) -> Dictionary:
	var index: Dictionary = {}
	for edge in solid.get_edges():
		for corner in solid.edge_endpoints(edge):
			if not index.has(corner):
				index[corner] = []
			index[corner].append(edge)
	return index


static func _opposite_edge(solid: Node3D, face: int, edge: int) -> int:
	var edges: PackedInt64Array = solid.face_edges(face)
	if edges.size() != 4:
		return 0
	var ends: PackedVector3Array = solid.edge_endpoints(edge)
	for candidate in edges:
		if candidate == edge:
			continue
		var other: PackedVector3Array = solid.edge_endpoints(candidate)
		if other[0] == ends[0] or other[0] == ends[1] or other[1] == ends[0] or other[1] == ends[1]:
			continue
		return candidate
	return 0


static func _other_face(solid: Node3D, edge: int, face: int) -> int:
	for candidate in solid.edge_faces(edge):
		if candidate != face:
			return candidate
	return 0


static func _far_corner(solid: Node3D, edge: int, corner: Vector3) -> Vector3:
	var ends: PackedVector3Array = solid.edge_endpoints(edge)
	return ends[1] if ends[0] == corner else ends[0]


static func _continue_across(solid: Node3D, index: Dictionary, edge: int, corner: Vector3) -> int:
	var spokes: Array = index.get(corner, [])
	if spokes.size() != 4:
		return 0
	var blocked: Dictionary = {}
	for face in solid.edge_faces(edge):
		blocked[face] = true
	for candidate in spokes:
		if candidate == edge:
			continue
		var shared := false
		for face in solid.edge_faces(candidate):
			if blocked.has(face):
				shared = true
				break
		if not shared:
			return candidate
	return 0
