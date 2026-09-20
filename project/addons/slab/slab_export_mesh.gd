@tool
extends RefCounted

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabExternalMesh := preload("res://addons/slab/slab_external_mesh.gd")

var positions: PackedVector3Array = PackedVector3Array()
var normals: PackedVector3Array = PackedVector3Array()
var uvs: PackedVector2Array = PackedVector2Array()
var indices: PackedInt32Array = PackedInt32Array()
var material_per_triangle: PackedInt32Array = PackedInt32Array()
var material_names: PackedStringArray = PackedStringArray()
var solid_count: int = 0


func clear() -> void:
	positions = PackedVector3Array()
	normals = PackedVector3Array()
	uvs = PackedVector2Array()
	indices = PackedInt32Array()
	material_per_triangle = PackedInt32Array()
	material_names = PackedStringArray()
	solid_count = 0


func bake(solids: Array[Node3D]) -> int:
	clear()
	if solids.is_empty():
		return ERR_INVALID_PARAMETER
	var valid: Array[Node3D] = []
	for solid in solids:
		if solid != null and is_instance_valid(solid) and SlabSelection.is_slab_object(solid):
			valid.append(solid)
	if valid.is_empty():
		return ERR_INVALID_PARAMETER

	var global_material_index: int = 0
	var material_to_index: Dictionary = {}

	for solid in valid:
		var mesh: ArrayMesh = _get_mesh(solid)
		if mesh == null:
			continue
		var materials: Array = _get_materials(solid)
		var solid_xform: Transform3D = solid.global_transform if solid.is_inside_tree() else solid.transform
		var base_vertex: int = positions.size()

		for surface_idx in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface_idx)
			if arrays.is_empty():
				continue
			var surf_verts: PackedVector3Array = _get_vector3_array(arrays, Mesh.ARRAY_VERTEX)
			var surf_normals: PackedVector3Array = _get_vector3_array(arrays, Mesh.ARRAY_NORMAL)
			var surf_uvs: PackedVector2Array = _get_vector2_array(arrays, Mesh.ARRAY_TEX_UV)
			var surf_indices: PackedInt32Array = _get_int32_array(arrays, Mesh.ARRAY_INDEX)
			var mat: Material = materials[surface_idx] if surface_idx < materials.size() else null
			var mat_name: String = _material_name(mat, surface_idx)
			var mat_global_idx: int
			if material_to_index.has(mat_name):
				mat_global_idx = material_to_index[mat_name]
			else:
				mat_global_idx = global_material_index
				material_to_index[mat_name] = mat_global_idx
				material_names.append(mat_name)
				global_material_index += 1
			var surf_base: int = positions.size()
			var has_normals: bool = not surf_normals.is_empty()
			var has_uvs: bool = not surf_uvs.is_empty()
			var xform_normal: Basis = solid_xform.basis.inverse().transposed()

			for i in surf_verts.size():
				positions.append(solid_xform * surf_verts[i])
				if has_normals and i < surf_normals.size():
					normals.append((xform_normal * surf_normals[i]).normalized())
				else:
					normals.append(Vector3.UP)
				if has_uvs and i < surf_uvs.size():
					uvs.append(surf_uvs[i])
				else:
					uvs.append(Vector2.ZERO)

			if surf_indices.is_empty():
				for i in range(0, surf_verts.size(), 3):
					indices.append(surf_base + i)
					indices.append(surf_base + i + 1)
					indices.append(surf_base + i + 2)
					material_per_triangle.append(mat_global_idx)
			else:
				for i in range(0, surf_indices.size(), 3):
					indices.append(surf_base + surf_indices[i])
					indices.append(surf_base + surf_indices[i + 1])
					indices.append(surf_base + surf_indices[i + 2])
					material_per_triangle.append(mat_global_idx)

		solid_count += 1

	if solid_count == 0:
		return ERR_INVALID_DATA
	return OK


func _get_mesh(node: Node3D) -> ArrayMesh:
	if SlabSelection.is_external_mesh(node):
		return node.build_mesh() if node.has_method("build_mesh") else null
	if SlabSelection.is_solid(node):
		return node.call("build_mesh") if node.has_method("build_mesh") else null
	return null


func _get_materials(node: Node3D) -> Array:
	if SlabSelection.is_external_mesh(node):
		return node.get_materials() if node.has_method("get_materials") else []
	if SlabSelection.is_solid(node):
		return node.get("materials") if "materials" in node else []
	return []


static func _get_vector3_array(arrays: Array, idx: int) -> PackedVector3Array:
	if idx >= arrays.size():
		return PackedVector3Array()
	var value: Variant = arrays[idx]
	if value is PackedVector3Array:
		return value
	return PackedVector3Array()


static func _get_vector2_array(arrays: Array, idx: int) -> PackedVector2Array:
	if idx >= arrays.size():
		return PackedVector2Array()
	var value: Variant = arrays[idx]
	if value is PackedVector2Array:
		return value
	return PackedVector2Array()


static func _get_int32_array(arrays: Array, idx: int) -> PackedInt32Array:
	if idx >= arrays.size():
		return PackedInt32Array()
	var value: Variant = arrays[idx]
	if value is PackedInt32Array:
		return value
	return PackedInt32Array()


func triangle_count() -> int:
	return indices.size() / 3


func vertex_count() -> int:
	return positions.size()


func has_normals() -> bool:
	return not normals.is_empty() and normals.size() == positions.size()


func has_uvs() -> bool:
	return not uvs.is_empty() and uvs.size() == positions.size()


func _material_name(mat: Material, slot: int) -> String:
	if mat == null:
		return "material_%d" % slot
	var res_name: String = mat.resource_name
	if res_name != "":
		return _sanitize_name(res_name)
	var path: String = mat.resource_path
	if path != "":
		return _sanitize_name(path.get_file().get_basename())
	return "material_%d" % slot


static func _sanitize_name(name: String) -> String:
	var out := ""
	for c in name:
		if c.is_valid_identifier() or c == "_":
			out += c
		elif c == " " or c == "-":
			out += "_"
	if out == "" or out[0].is_valid_int():
		out = "mat_" + out
	return out
