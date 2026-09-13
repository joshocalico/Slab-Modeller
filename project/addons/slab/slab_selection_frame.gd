@tool
extends RefCounted

const SlabElementXform := preload("res://addons/slab/slab_element_xform.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")

enum Pivot { SELECTION, ACTIVE, CUSTOM }
enum Orientation { WORLD, LOCAL, FACE }


static func from_selection(selection: RefCounted) -> Dictionary:
	if selection == null:
		return { "valid": false }
	return make(selection.solid, selection.mode, selection.ids, selection.pivot_mode,
			selection.orientation, selection.active_id, selection.custom_pivot_world)


static func make(solid: Node3D, mode: int, ids: PackedInt64Array,
		pivot_mode: int = Pivot.SELECTION,
		axis_mode: int = Orientation.WORLD, active_id: int = 0,
		custom_pivot_world := Vector3.ZERO) -> Dictionary:
	if solid == null or not is_instance_valid(solid) or not solid.is_class("SlabSolid"):
		return { "valid": false }
	var pivot_local := _pivot(solid, mode, ids, pivot_mode, active_id, custom_pivot_world)
	if pivot_local == null:
		return { "valid": false }
	var world_basis := Basis.IDENTITY
	if axis_mode == Orientation.LOCAL:
		world_basis = solid.global_transform.basis.orthonormalized()
	elif axis_mode == Orientation.FACE:
		var face_basis: Variant = _face_basis(solid, mode, ids, active_id)
		if face_basis == null:
			return { "valid": false }
		world_basis = face_basis
	elif axis_mode != Orientation.WORLD:
		return { "valid": false }
	var world := Transform3D(world_basis, solid.to_global(pivot_local))
	var local := solid.global_transform.affine_inverse() * world
	return {
		"valid": true,
		"local": local,
		"world": world,
		"pivot_local": pivot_local,
		"pivot_world": world.origin,
	}


static func _pivot(solid: Node3D, mode: int, ids: PackedInt64Array,
		pivot_mode: int, active_id: int, custom: Vector3) -> Variant:
	if pivot_mode == Pivot.CUSTOM:
		return solid.to_local(custom)
	if mode == SlabSelection.Mode.OBJECT:
		return solid.call("get_local_aabb").get_center() if pivot_mode == Pivot.SELECTION else Vector3.ZERO
	if ids.is_empty():
		return null
	if pivot_mode == Pivot.ACTIVE:
		var chosen := active_id if active_id != 0 and ids.find(active_id) != -1 else _lowest(ids)
		if mode == SlabSelection.Mode.VERTEX:
			return solid.call("vertex_position", chosen)
		if mode == SlabSelection.Mode.EDGE:
			var ends: PackedVector3Array = solid.call("edge_endpoints", chosen)
			return (ends[0] + ends[1]) * 0.5 if ends.size() == 2 else null
		if mode == SlabSelection.Mode.FACE:
			var corners: PackedVector3Array = solid.call("face_corners", chosen)
			return solid.call("face_centroid", chosen) if corners.size() >= 3 else null
		return null
	if pivot_mode != Pivot.SELECTION:
		return null
	var vertices := SlabElementXform.vertices(solid, mode, ids)
	if vertices.is_empty():
		return null
	var centre := Vector3.ZERO
	for vertex in vertices:
		centre += solid.call("vertex_position", vertex)
	return centre / float(vertices.size())


static func _face_basis(solid: Node3D, mode: int, ids: PackedInt64Array, active_id: int) -> Variant:
	if mode != SlabSelection.Mode.FACE or ids.is_empty():
		return null
	var face := active_id if active_id != 0 and ids.find(active_id) != -1 else _lowest(ids)
	var corners: PackedVector3Array = solid.call("face_corners", face)
	if corners.size() < 3:
		return null
	var normal_local: Vector3 = solid.call("face_normal", face)
	var normal_world := (solid.global_transform.basis.inverse().transposed() * normal_local).normalized()
	if normal_world.is_zero_approx():
		return null
	var tangent_world := Vector3.ZERO
	for index in corners.size():
		var candidate := solid.global_transform.basis * (corners[(index + 1) % corners.size()] - corners[index])
		candidate -= normal_world * candidate.dot(normal_world)
		if candidate.length_squared() > tangent_world.length_squared():
			tangent_world = candidate
	if tangent_world.is_zero_approx():
		return null
	tangent_world = tangent_world.normalized()
	var z_axis := tangent_world.cross(normal_world).normalized()
	var x_axis := normal_world.cross(z_axis).normalized()
	return Basis(x_axis, normal_world, z_axis)


static func _lowest(ids: PackedInt64Array) -> int:
	var result: int = ids[0]
	for id in ids:
		if id < result:
			result = id
	return result
