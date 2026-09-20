@tool
extends RefCounted

const SlabExportMesh := preload("res://addons/slab/slab_export_mesh.gd")


static func write(path: String, export_mesh: SlabExportMesh) -> int:
	if export_mesh == null or export_mesh.vertex_count() == 0:
		return ERR_INVALID_PARAMETER
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	var base_name: String = path.get_file().get_basename()
	var mtl_name: String = base_name + ".mtl"

	file.store_line("# Slab OBJ Export")
	file.store_line("mtllib " + mtl_name)
	file.store_line("")

	for pos in export_mesh.positions:
		file.store_line("v %.6f %.6f %.6f" % [pos.x, pos.y, pos.z])

	if export_mesh.has_uvs():
		file.store_line("")
		for uv in export_mesh.uvs:
			file.store_line("vt %.6f %.6f" % [uv.x, 1.0 - uv.y])

	if export_mesh.has_normals():
		file.store_line("")
		for n in export_mesh.normals:
			file.store_line("vn %.6f %.6f %.6f" % [n.x, n.y, n.z])

	file.store_line("")
	file.store_line("g mesh")

	var has_uvs: bool = export_mesh.has_uvs()
	var has_normals: bool = export_mesh.has_normals()
	var current_mat: int = -1
	var tri_count: int = export_mesh.triangle_count()

	for tri_idx in tri_count:
		var mat_idx: int = export_mesh.material_per_triangle[tri_idx] if tri_idx < export_mesh.material_per_triangle.size() else 0
		if mat_idx != current_mat:
			var mat_name: String = export_mesh.material_names[mat_idx] if mat_idx < export_mesh.material_names.size() else "material_0"
			file.store_line("usemtl " + mat_name)
			current_mat = mat_idx

		var i0: int = export_mesh.indices[tri_idx * 3] + 1
		var i1: int = export_mesh.indices[tri_idx * 3 + 1] + 1
		var i2: int = export_mesh.indices[tri_idx * 3 + 2] + 1

		if has_uvs and has_normals:
			file.store_line("f %d/%d/%d %d/%d/%d %d/%d/%d" % [i0, i0, i0, i1, i1, i1, i2, i2, i2])
		elif has_uvs:
			file.store_line("f %d/%d %d/%d %d/%d" % [i0, i0, i1, i1, i2, i2])
		elif has_normals:
			file.store_line("f %d//%d %d//%d %d//%d" % [i0, i0, i1, i1, i2, i2])
		else:
			file.store_line("f %d %d %d" % [i0, i1, i2])

	file.close()

	var mtl_path: String = path.get_base_dir().path_join(mtl_name)
	var mtl_err: int = _write_mtl(mtl_path, export_mesh)
	if mtl_err != OK:
		return mtl_err

	return OK


static func _write_mtl(path: String, export_mesh: SlabExportMesh) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_line("# Slab MTL Export")
	file.store_line("")

	for mat_name in export_mesh.material_names:
		file.store_line("newmtl " + mat_name)
		file.store_line("Kd 0.8 0.8 0.8")
		file.store_line("Ka 0.2 0.2 0.2")
		file.store_line("Ks 0.1 0.1 0.1")
		file.store_line("Ns 10.0")
		file.store_line("d 1.0")
		file.store_line("illum 2")
		file.store_line("")

	file.close()
	return OK
