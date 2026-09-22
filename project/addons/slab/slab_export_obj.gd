@tool
extends RefCounted

const SlabExportMesh := preload("res://addons/slab/slab_export_mesh.gd")


static func write(path: String, export_mesh: SlabExportMesh) -> int:
	if export_mesh == null or export_mesh.vertex_count() == 0:
		return ERR_INVALID_PARAMETER
	# Build the entire bundle beside its destination, then replace with backups.
	var destination: String = path.get_base_dir()
	var staging: String = destination.path_join(".slab-export-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var error: int = DirAccess.make_dir_absolute(staging)
	if error != OK:
		return error
	error = _write_staged(staging.path_join(path.get_file()), export_mesh)
	if error != OK:
		_remove_staging(staging)
		return error
	var files: PackedStringArray = DirAccess.get_files_at(staging)
	# Install the entry point last, after every dependency is present.
	var mtl_name: String = path.get_file().get_basename() + ".mtl"
	files.erase(mtl_name)
	files.erase(path.get_file())
	files.append(mtl_name)
	files.append(path.get_file())
	var result: Dictionary = _replace_bundle(staging, destination, files)
	if not result.get("recovery_needed", false):
		_remove_staging(staging)
	return int(result["error"])


static func _replace_bundle(staging: String, destination: String, files: PackedStringArray) -> Dictionary:
	# Probe existing files without truncating them before changing any dependency.
	for name in files:
		var target: String = destination.path_join(name)
		if DirAccess.dir_exists_absolute(target):
			return {"error": ERR_FILE_CANT_WRITE}
		if FileAccess.file_exists(target):
			var probe := FileAccess.open(target, FileAccess.READ_WRITE)
			if probe == null:
				return {"error": FileAccess.get_open_error()}
			probe.close()
	var backup_directory: String = staging.path_join("previous")
	var error: int = DirAccess.make_dir_absolute(backup_directory)
	if error != OK:
		return {"error": error}
	var installed: Array[String] = []
	var backed_up: Array[String] = []
	for name in files:
		var target: String = destination.path_join(name)
		if FileAccess.file_exists(target):
			error = DirAccess.rename_absolute(target, backup_directory.path_join(name))
			if error != OK:
				break
			backed_up.append(name)
		error = DirAccess.rename_absolute(staging.path_join(name), target)
		if error != OK:
			break
		installed.append(name)
	if error == OK:
		return {"error": OK}
	var restored := true
	for name in installed:
		if DirAccess.remove_absolute(destination.path_join(name)) != OK:
			restored = false
	for name in backed_up:
		if DirAccess.rename_absolute(backup_directory.path_join(name), destination.path_join(name)) != OK:
			restored = false
	if not restored:
		push_error("OBJ export could not restore every file. Original backups remain in: %s" % backup_directory)
	return {"error": error, "recovery_needed": not restored}


static func _remove_staging(staging: String) -> void:
	var backup_directory: String = staging.path_join("previous")
	if DirAccess.dir_exists_absolute(backup_directory):
		for name in DirAccess.get_files_at(backup_directory):
			DirAccess.remove_absolute(backup_directory.path_join(name))
		DirAccess.remove_absolute(backup_directory)
	for name in DirAccess.get_files_at(staging):
		DirAccess.remove_absolute(staging.path_join(name))
	DirAccess.remove_absolute(staging)


static func _write_staged(path: String, export_mesh: SlabExportMesh) -> int:
	# These files remain isolated until the complete bundle is ready.
	var base_name: String = path.get_file().get_basename()
	var mtl_name: String = base_name + ".mtl"
	var mtl_path: String = path.get_base_dir().path_join(mtl_name)
	var mtl_err: int = _write_mtl(mtl_path, export_mesh)
	if mtl_err != OK:
		return mtl_err
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

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

	file.flush()
	var write_error: int = file.get_error()
	file.close()
	return write_error


static func _write_mtl(path: String, export_mesh: SlabExportMesh) -> int:
	var texture_files: Dictionary = {}
	var colors: Array[Color] = []
	for i in export_mesh.material_names.size():
		var material: Material = export_mesh.materials[i] if i < export_mesh.materials.size() else null
		if material != null and not material is StandardMaterial3D:
			return ERR_UNAVAILABLE
		var color := Color(0.8, 0.8, 0.8, 1.0)
		if material is StandardMaterial3D:
			color = material.albedo_color
			if material.albedo_texture != null:
				var image: Image = material.albedo_texture.get_image()
				if image == null or image.is_empty():
					return ERR_INVALID_DATA
				if image.is_compressed() and image.decompress() != OK:
					return ERR_INVALID_DATA
				var png: PackedByteArray = image.save_png_to_buffer()
				if png.is_empty():
					return ERR_INVALID_DATA
				var hash := HashingContext.new()
				hash.start(HashingContext.HASH_SHA256)
				hash.update(png)
				var digest: String = hash.finish().hex_encode().substr(0, 16)
				var texture_name: String = "%s_%s_albedo_%s.png" % [path.get_file().get_basename(), export_mesh.material_names[i], digest]
				texture_files[i] = {"name": texture_name, "bytes": png}
		colors.append(color)
	for texture in texture_files.values():
		var texture_file := FileAccess.open(path.get_base_dir().path_join(texture.name), FileAccess.WRITE)
		if texture_file == null:
			return FileAccess.get_open_error()
		texture_file.store_buffer(texture.bytes)
		texture_file.flush()
		var texture_error: int = texture_file.get_error()
		texture_file.close()
		if texture_error != OK:
			return texture_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_line("# Slab MTL Export: diffuse color, opacity and albedo texture; no PBR/shaders")
	file.store_line("")
	for i in export_mesh.material_names.size():
		var color: Color = colors[i]
		file.store_line("newmtl " + export_mesh.material_names[i])
		file.store_line("Kd %.6f %.6f %.6f" % [color.r, color.g, color.b])
		file.store_line("d %.6f" % color.a)
		file.store_line("illum 2")
		if texture_files.has(i):
			file.store_line("map_Kd " + str(texture_files[i].name))
		file.store_line("")
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	return write_error
