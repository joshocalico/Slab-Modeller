@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabElementXform := preload("res://addons/slab/slab_element_xform.gd")


static func compute_weights(solid: Node3D, mode: int, ids: PackedInt64Array, radius: float, falloff: int) -> Dictionary:
	if solid == null or ids.is_empty() or radius <= 0.0:
		return {}
	var selected_verts := SlabElementXform.vertices(solid, mode, ids)
	if selected_verts.is_empty():
		return {}
	var selected_positions: Array[Vector3] = []
	for vertex in selected_verts:
		selected_positions.append(solid.vertex_position(vertex))
	var weights: Dictionary = {}
	for vertex in selected_verts:
		weights[vertex] = 1.0
	var all_verts: PackedInt64Array = solid.get_vertices()
	for vertex in all_verts:
		if weights.has(vertex):
			continue
		var pos: Vector3 = solid.vertex_position(vertex)
		var min_dist := INF
		for sel_pos in selected_positions:
			var dist: float = pos.distance_to(sel_pos)
			if dist < min_dist:
				min_dist = dist
		if min_dist >= radius:
			continue
		var t: float = min_dist / radius
		var weight: float = _falloff_curve(t, falloff)
		if weight > 0.0:
			weights[vertex] = weight
	return weights


static func _falloff_curve(t: float, falloff: int) -> float:
	t = clampf(t, 0.0, 1.0)
	match falloff:
		SlabSelection.Falloff.LINEAR:
			return 1.0 - t
		SlabSelection.Falloff.SMOOTH, _:
			return smoothstep(1.0, 0.0, t)
