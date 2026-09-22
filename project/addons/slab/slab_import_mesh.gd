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
		var line: String = file.get_line().split("#", true, 1)[0].strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		var parts: PackedStringArray = line.replace("\t", " ").split(" ", false)
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
				var face_positions := PackedVector3Array()
				var face_normals := PackedVector3Array()
				var face_uvs := PackedVector2Array()
				for i in range(1, parts.size()):
					var vert: Dictionary = _parse_obj_vertex(parts[i])
					var pos_idx: int = _obj_index(int(vert.get("v", 0)), positions.size())
					var uv_idx: int = _obj_index(int(vert.get("vt", 0)), uvs.size())
					var norm_idx: int = _obj_index(int(vert.get("vn", 0)), normals.size())
					if pos_idx < 0 or (vert.has("vt") and uv_idx < 0) or (vert.has("vn") and norm_idx < 0):
						file.close()
						return {"error": ERR_INVALID_DATA, "message": "Invalid OBJ face index"}
					face_positions.append(positions[pos_idx])
					face_normals.append(normals[norm_idx] if norm_idx >= 0 else Vector3.ZERO)
					face_uvs.append(uvs[uv_idx] if uv_idx >= 0 else Vector2.ZERO)
				var triangles := _triangulate_obj_face(face_positions)
				if triangles.is_empty():
					file.close()
					return {"error": ERR_INVALID_DATA, "message": "Invalid or degenerate OBJ face"}
				for i in range(0, triangles.size(), 3):
					# OBJ is counterclockwise; ArrayMesh fronts are clockwise.
					for corner in [triangles[i], triangles[i + 2], triangles[i + 1]]:
						indices.append(vertices.size())
						vertices.append(face_positions[corner])
						vertex_normals.append(face_normals[corner])
						vertex_uvs.append(face_uvs[corner])

	file.close()

	if vertices.is_empty():
		return {"error": ERR_INVALID_DATA, "message": "No valid geometry found in OBJ file"}

	vertex_normals = _fill_missing_normals(vertices, indices, vertex_normals)

	var mesh: ArrayMesh = _build_array_mesh(vertices, vertex_normals, vertex_uvs, indices)
	var external := SlabExternalMesh.from_mesh(mesh, path)
	external.name = path.get_file().get_basename()

	return {
		"error": OK,
		"mesh": external,
		"status": "Imported as External mesh (not a Slab solid). OBJ materials are not imported."
	}


static func _obj_index(value: int, count: int) -> int:
	var index: int = value - 1 if value > 0 else count + value
	return index if value != 0 and index >= 0 and index < count else -1


static func _triangulate_obj_face(points: PackedVector3Array) -> PackedInt32Array:
	if points.size() < 3:
		return PackedInt32Array()
	if points.size() == 3:
		return PackedInt32Array([0, 1, 2])
	# Project onto the dominant plane so concave polygons triangulate correctly.
	var normal := Vector3.ZERO
	for i in points.size():
		normal += points[i].cross(points[(i + 1) % points.size()])
	var axis: int = normal.abs().max_axis_index()
	var polygon := PackedVector2Array()
	for point in points:
		match axis:
			0: polygon.append(Vector2(point.y, point.z))
			1: polygon.append(Vector2(point.z, point.x))
			2: polygon.append(Vector2(point.x, point.y))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	# Geometry2D normalizes to CCW. Restore the source polygon orientation.
	if normal[axis] < 0:
		for i in range(0, triangles.size(), 3):
			var swap: int = triangles[i + 1]
			triangles[i + 1] = triangles[i + 2]
			triangles[i + 2] = swap
	return triangles


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
	var ended := false

	while not file.eof_reached():
		var line: String = file.get_line().split("#", true, 1)[0].strip_edges()
		if line.is_empty():
			continue

		var parts: PackedStringArray = line.replace("\t", " ").split(" ", false)
		if parts.is_empty():
			continue

		if parts[0] == "facet" and parts.size() >= 5 and parts[1] == "normal":
			current_normal = Vector3(float(parts[2]), float(parts[3]), float(parts[4])).normalized()
			face_vertices.clear()
		elif parts[0] == "vertex" and parts.size() >= 4:
			face_vertices.append(Vector3(float(parts[1]), float(parts[2]), float(parts[3])))
		elif parts[0] == "endfacet":
			if face_vertices.size() != 3:
				file.close()
				return {"error": ERR_INVALID_DATA, "message": "STL facets must have three vertices"}
			var base: int = vertices.size()
			indices.append_array(PackedInt32Array([base, base + 2, base + 1]))
			for i in range(3):
				vertices.append(face_vertices[i])
				normals.append(current_normal)
			face_vertices.clear()
		elif parts[0] == "endsolid":
			ended = true

	file.close()
	if not ended or not face_vertices.is_empty():
		return {"error": ERR_INVALID_DATA, "message": "Incomplete ASCII STL"}

	if vertices.is_empty():
		return {"error": ERR_INVALID_DATA, "message": "No valid geometry found in STL file"}

	normals = _fill_missing_normals(vertices, indices, normals)
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

	if triangle_count <= 0 or triangle_count > 10000000 or file.get_length() != 84 + triangle_count * 50:
		file.close()
		return {"error": ERR_INVALID_DATA, "message": "Invalid triangle count in STL file: %d" % triangle_count}

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for _i in range(triangle_count):
		var nx: float = file.get_float()
		var ny: float = file.get_float()
		var nz: float = file.get_float()
		var normal := Vector3(nx, ny, nz).normalized()

		var base: int = vertices.size()
		indices.append_array(PackedInt32Array([base, base + 2, base + 1]))
		for _v in range(3):
			var vx: float = file.get_float()
			var vy: float = file.get_float()
			var vz: float = file.get_float()
			vertices.append(Vector3(vx, vy, vz))
			normals.append(normal)

		file.get_16()

	file.close()

	if vertices.is_empty():
		return {"error": ERR_INVALID_DATA, "message": "No valid geometry found in binary STL file"}

	normals = _fill_missing_normals(vertices, indices, normals)
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
		var face_normal: Vector3 = (v2 - v0).cross(v1 - v0)
		normals[i0] += face_normal
		normals[i1] += face_normal
		normals[i2] += face_normal

	for i in range(normals.size()):
		if normals[i].length_squared() > 0.0001:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP

	return normals


static func _fill_missing_normals(vertices: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array) -> PackedVector3Array:
	var computed := PackedVector3Array()
	for i in normals.size():
		if normals[i].is_zero_approx():
			if computed.is_empty():
				computed = _compute_normals(vertices, indices)
			normals[i] = computed[i]
	return normals
