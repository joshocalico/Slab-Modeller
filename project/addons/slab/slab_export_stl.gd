@tool
extends RefCounted

const SlabExportMesh := preload("res://addons/slab/slab_export_mesh.gd")


static func write(path: String, export_mesh: SlabExportMesh) -> int:
	if export_mesh == null or export_mesh.vertex_count() == 0:
		return ERR_INVALID_PARAMETER
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	var header := "Slab STL Export".to_ascii_buffer()
	header.resize(80)
	file.store_buffer(header)

	var tri_count: int = export_mesh.triangle_count()
	file.store_32(tri_count)

	for tri_idx in tri_count:
		var i0: int = export_mesh.indices[tri_idx * 3]
		var i1: int = export_mesh.indices[tri_idx * 3 + 1]
		var i2: int = export_mesh.indices[tri_idx * 3 + 2]

		var v0: Vector3 = export_mesh.positions[i0]
		var v1: Vector3 = export_mesh.positions[i1]
		var v2: Vector3 = export_mesh.positions[i2]

		var normal: Vector3
		if export_mesh.has_normals():
			normal = (export_mesh.normals[i0] + export_mesh.normals[i1] + export_mesh.normals[i2]).normalized()
		else:
			normal = (v1 - v0).cross(v2 - v0).normalized()

		file.store_float(normal.x)
		file.store_float(normal.y)
		file.store_float(normal.z)

		file.store_float(v0.x)
		file.store_float(v0.y)
		file.store_float(v0.z)

		file.store_float(v1.x)
		file.store_float(v1.y)
		file.store_float(v1.z)

		file.store_float(v2.x)
		file.store_float(v2.y)
		file.store_float(v2.z)

		file.store_16(0)

	file.close()
	return OK
