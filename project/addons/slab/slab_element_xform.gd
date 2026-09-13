@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")

const MIN_STEP := 0.0002


static func vertices(solid: Node3D, mode: int, ids: PackedInt64Array) -> PackedInt64Array:
	if mode == SlabSelection.Mode.VERTEX:
		return ids
	var seen: Dictionary = {}
	var out := PackedInt64Array()
	for id in ids:
		var verts: PackedInt64Array = solid.face_vertices(id) if mode == SlabSelection.Mode.FACE else solid.edge_vertices(id)
		for vertex in verts:
			if seen.has(vertex):
				continue
			seen[vertex] = true
			out.append(vertex)
	return out


static func centroid(solid: Node3D, mode: int, ids: PackedInt64Array) -> Vector3:
	var verts: PackedInt64Array = vertices(solid, mode, ids)
	if verts.is_empty():
		return Vector3.ZERO
	var acc := Vector3.ZERO
	for vertex in verts:
		acc += solid.vertex_position(vertex)
	return acc / float(verts.size())


static func translate(solid: Node3D, mode: int, ids: PackedInt64Array, delta: Vector3) -> int:
	if delta.length() < MIN_STEP:
		return OK
	var verts: PackedInt64Array = vertices(solid, mode, ids)
	if verts.is_empty():
		return OK
	return solid.move_vertices(verts, delta)


static func transform(solid: Node3D, mode: int, ids: PackedInt64Array, xform: Transform3D) -> int:
	var verts: PackedInt64Array = vertices(solid, mode, ids)
	if verts.is_empty() or xform.is_equal_approx(Transform3D.IDENTITY):
		return OK
	return solid.transform_vertices(verts, xform)
