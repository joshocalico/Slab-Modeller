@tool
extends RefCounted

const SlabExternalMesh := preload("res://addons/slab/slab_external_mesh.gd")


static func load_from_file(path: String) -> Dictionary:
	var ext: String = path.get_extension().to_lower()
	match ext:
		"obj":
			return _load_obj(path)
		"stl":
			return _load_stl(path)
		_:
			return {"error": ERR_FILE_UNRECOGNIZED, "message": "Unsupported file format: %s" % ext}


static func _load_obj(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error(), "message": "Could not open file: %s" % path}

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var vertices := PackedVector3Array()
	var vertex_normals := PackedVector3Array()
	var vertex_uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		var parts: PackedStringArray = line.split(" ", false)
		if parts.is_empty():
			continue

		var command: String = parts[0]
		match command:
			"v":
				if parts.size() >= 4:
					positions.append(Vector3(
						float(parts[1]),
						float(parts[2]),
						float(parts[3])
					))
			"vn":
				if parts.size() >= 4:
					normals.append(Vector3(
						float(parts[1]),
						float(parts[2]),
						float(parts[3])
					).normalized())
			"vt":
				if parts.size() >= 3:
					uvs.append(Vector2(
						float(parts[1]),
						1.0 - float(parts[2])
					))
			"f":
				var face_verts: Array[Dictionary] = []
				for i in range(1, parts.size()):
					var vert_data: Dictionary = _parse_obj_vertex(parts[i])
					face_verts.append(vert_data)
				if face_verts.size() >= 3:
					for i in range(1, face_verts.size() - 1):
						for vert_idx in [0, i, i + 1]:
							var vert: Dictionary = face_verts[vert_idx]
							var pos_idx: int = vert.get("v", 1) - 1
							var uv_idx: int = vert.get("vt", 0) - 1
							var norm_idx: int = vert.get("vn", 0) - 1

							indices.append(vertices.size())
							vertices.append(positions[pos_idx] if pos_idx >= 0 and pos_idx < positions.size() else Vector3.ZERO)
							vertex_normals.append(normals[norm_idx] if norm_idx >= 0 and norm_idx < normals.size() else Vector3.ZERO)
							vertex_uvs.append(uvs[uv_idx] if uv_idx >= 0 and uv_idx < uvs.size() else Vector2.ZERO)

	file.close()

	if vertices.is_empty():
		return {"error": ERR_INVALID_DATA, "message": "No valid geometry found in OBJ file"}

	var has_normals: bool = false
	for n in vertex_normals:
		if n.length_squared() > 0.001:
			has_normals = true
			break

	if not has_normals:
		vertex_normals = _compute_normals(vertices, indices)

	var mesh: ArrayMesh = _build_array_mesh(vertices, vertex_normals, vertex_uvs, indices)
	var external := SlabExternalMesh.from_mesh(mesh, path)
	external.name = path.get_file().get_basename()

	return {
		"error": OK,
		"mesh": external,
		"status": "Imported as External mesh (not a Slab solid)."
	}


static func _parse_obj_vertex(token: String) -> Dictionary:
	var result: Dictionary = {}
	var parts: PackedStringArray = token.split("/")
	if parts.size() >= 1 and parts[0] != "":
		result["v"] = int(parts[0])
	if parts.size() >= 2 and parts[1] != "":
		result["vt"] = int(parts[1])
	if parts.size() >= 3 and parts[2] != "":
		result["vn"] = int(parts[2])
	return result


static func _load_stl(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error(), "message": "Could not open file: %s" % path}

	var first_line: String = file.get_line().strip_edges()
	if first_line.begins_with("solid"):
		var second_line: String = ""
		while not file.eof_reached():
			second_line = file.get_line().strip_edges()
			if not second_line.is_empty():
				break
		file.seek(0)
		if second_line.begins_with("facet") or second_line.begins_with("endsolid"):
			return _load_stl_ascii(path, file)

	file.seek(0)
	var header: PackedByteArray = file.get_buffer(80)
	if header.size() < 80:
		file.close()
		return {"error": ERR_INVALID_DATA, "message": "File too small to be valid STL"}

	return _load_stl_binary(path, file)


static func _load_stl_ascii(path: String, file: FileAccess) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var current_normal := Vector3.ZERO
	var face_vertices := PackedVector3Array()

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty():
			continue

		var parts: PackedStringArray = line.split(" ", false)
		if parts.is_empty():
			continue

		if parts[0] == "facet" and parts.size() >= 5 and parts[1] == "normal":
			current_normal = Vector3(float(parts[2]), float(parts[3]), float(parts[4])).normalized()
			face_vertices.clear()
		elif parts[0] == "vertex" and parts.size() >= 4:
			face_vertices.append(Vector3(float(parts[1]), float(parts[2]), float(parts[3])))
		elif parts[0] == "endfacet":
			if face_vertices.size() >= 3:
				for i in range(face_vertices.size()):
					indices.append(vertices.size())
					vertices.append(face_vertices[i])
					normals.append(current_normal)
			face_vertices.clear()

	file.close()

	if vertices.is_empty():
		return {"error": ERR_INVALID_DATA, "message": "No valid geometry found in STL file"}

	var mesh: ArrayMesh = _build_array_mesh(vertices, normals, PackedVector2Array(), indices)
	var external := SlabExternalMesh.from_mesh(mesh, path)
	external.name = path.get_file().get_basename()

	return {
		"error": OK,
		"mesh": external,
		"status": "Imported as External mesh (not a Slab solid)."
	}


static func _load_stl_binary(path: String, file: FileAccess) -> Dictionary:
	file.seek(80)
	var triangle_count: int = file.get_32()

	if triangle_count <= 0 or triangle_count > 10000000:
		file.close()
		return {"error": ERR_INVALID_DATA, "message": "Invalid triangle count in STL file: %d" % triangle_count}

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for _i in range(triangle_count):
		if file.eof_reached():
			break
		var nx: float = file.get_float()
		var ny: float = file.get_float()
		var nz: float = file.get_float()
		var normal := Vector3(nx, ny, nz).normalized()

		for _v in range(3):
			var vx: float = file.get_float()
			var vy: float = file.get_float()
			var vz: float = file.get_float()
			indices.append(vertices.size())
			vertices.append(Vector3(vx, vy, vz))
			normals.append(normal)

		file.get_16()

	file.close()

	if vertices.is_empty():
		return {"error": ERR_INVALID_DATA, "message": "No valid geometry found in binary STL file"}

	var mesh: ArrayMesh = _build_array_mesh(vertices, normals, PackedVector2Array(), indices)
	var external := SlabExternalMesh.from_mesh(mesh, path)
	external.name = path.get_file().get_basename()

	return {
		"error": OK,
		"mesh": external,
		"status": "Imported as External mesh (not a Slab solid)."
	}


static func _build_array_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if not normals.is_empty() and normals.size() == vertices.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	if not uvs.is_empty() and uvs.size() == vertices.size():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _compute_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(vertices.size()):
		normals[i] = Vector3.ZERO

	for i in range(0, indices.size(), 3):
		if i + 2 >= indices.size():
			break
		var i0: int = indices[i]
		var i1: int = indices[i + 1]
		var i2: int = indices[i + 2]
		if i0 >= vertices.size() or i1 >= vertices.size() or i2 >= vertices.size():
			continue
		var v0: Vector3 = vertices[i0]
		var v1: Vector3 = vertices[i1]
		var v2: Vector3 = vertices[i2]
		var face_normal: Vector3 = (v1 - v0).cross(v2 - v0)
		normals[i0] += face_normal
		normals[i1] += face_normal
		normals[i2] += face_normal

	for i in range(normals.size()):
		if normals[i].length_squared() > 0.0001:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP

	return normals
