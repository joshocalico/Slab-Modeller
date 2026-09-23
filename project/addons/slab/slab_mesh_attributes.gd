@tool
extends RefCounted

# Canonical import boundary: all channels align to flattened source vertices.
# Deformation geometry belongs to kernel corners; this contains no source mesh.
static func flatten(mesh: Mesh) -> Dictionary:
	if mesh == null: return {"error": "mesh is missing"}
	var result := {"vertices": PackedVector3Array(), "indices": PackedInt32Array(),
		"uvs": PackedVector2Array(), "slots": PackedInt32Array(), "attributes": {}}
	var attrs: Dictionary = result.attributes
	attrs.uv2 = PackedVector2Array()
	attrs.colors = PackedColorArray()
	attrs.normals = PackedVector3Array()
	attrs.tangents = PackedFloat32Array()
	attrs.bones = PackedInt32Array()
	attrs.weights = PackedFloat32Array()
	for key in ["uv2_present", "color_present", "normal_present", "tangent_present", "skin_present"]:
		attrs[key] = PackedByteArray()
	attrs.blend_shapes = []
	var shape_count: int = mesh.get_blend_shape_count() if mesh is ArrayMesh else 0
	var normalized := mesh is ArrayMesh and mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for shape in shape_count:
		attrs.blend_shapes.append({"name": str(mesh.get_blend_shape_name(shape)), "positions": PackedVector3Array(),
			"normals": PackedVector3Array(), "tangents": PackedFloat32Array()})
	var any_uv := false
	var any_skin := false
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return {"error": "only triangle surfaces are supported"}
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			return {"error": "vertex arrays are malformed"}
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var count := vertices.size()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if (indices.size() if not indices.is_empty() else count) % 3 != 0: return {"error": "triangle indices are malformed"}
		for channel in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			if _present(arrays[channel]) and arrays[channel].size() != count: return {"error": "surface attribute length differs from vertex count"}
		if _present(arrays[Mesh.ARRAY_TANGENT]) and arrays[Mesh.ARRAY_TANGENT].size() != count * 4:
			return {"error": "tangent data is malformed"}
		var skin := _present(arrays[Mesh.ARRAY_BONES]) or _present(arrays[Mesh.ARRAY_WEIGHTS])
		var influence_count := 0
		if skin:
			if not _present(arrays[Mesh.ARRAY_BONES]) or not _present(arrays[Mesh.ARRAY_WEIGHTS]) or arrays[Mesh.ARRAY_BONES].size() != arrays[Mesh.ARRAY_WEIGHTS].size() or count == 0:
				return {"error": "bone indices and weights are malformed"}
			influence_count = arrays[Mesh.ARRAY_BONES].size() / count
			if influence_count not in [4, 8] or arrays[Mesh.ARRAY_BONES].size() != count * influence_count:
				return {"error": "skin requires four or eight influences per vertex"}
		any_skin = any_skin or skin
		var shapes: Array = mesh.surface_get_blend_shape_arrays(surface) if mesh is ArrayMesh else []
		if shapes.size() != shape_count: return {"error": "blend shape surface count is inconsistent"}
		for shape in shapes:
			if shape.size() != Mesh.ARRAY_MAX or not shape[Mesh.ARRAY_VERTEX] is PackedVector3Array or shape[Mesh.ARRAY_VERTEX].size() != count:
				return {"error": "blend shape vertex data is malformed"}
			for channel in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT]:
				if _present(shape[channel]) and shape[channel].size() != count * (4 if channel == Mesh.ARRAY_TANGENT else 1):
					return {"error": "blend shape normal or tangent data is malformed"}
		var base: int = result.vertices.size()
		for index in count:
			if not vertices[index].is_finite(): return {"error": "nonfinite vertex"}
			result.vertices.append(vertices[index])
			var has_uv := _present(arrays[Mesh.ARRAY_TEX_UV])
			any_uv = any_uv or has_uv
			var uv: Vector2 = arrays[Mesh.ARRAY_TEX_UV][index] if has_uv else Vector2.ZERO
			var uv2: Vector2 = arrays[Mesh.ARRAY_TEX_UV2][index] if _present(arrays[Mesh.ARRAY_TEX_UV2]) else Vector2.ZERO
			var color: Color = arrays[Mesh.ARRAY_COLOR][index] if _present(arrays[Mesh.ARRAY_COLOR]) else Color.WHITE
			var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][index] if _present(arrays[Mesh.ARRAY_NORMAL]) else Vector3.ZERO
			if not uv.is_finite() or not uv2.is_finite() or not normal.is_finite() or not _finite_color(color): return {"error": "nonfinite surface attribute"}
			result.uvs.append(uv)
			attrs.uv2.append(uv2)
			attrs.colors.append(color)
			attrs.normals.append(normal)
			attrs.uv2_present.append(int(_present(arrays[Mesh.ARRAY_TEX_UV2])))
			attrs.color_present.append(int(_present(arrays[Mesh.ARRAY_COLOR])))
			attrs.normal_present.append(int(_present(arrays[Mesh.ARRAY_NORMAL])))
			attrs.tangent_present.append(int(_present(arrays[Mesh.ARRAY_TANGENT])))
			attrs.skin_present.append(int(skin))
			var tangent := PackedFloat32Array([0, 0, 0, 1])
			if _present(arrays[Mesh.ARRAY_TANGENT]): tangent = arrays[Mesh.ARRAY_TANGENT].slice(index * 4, index * 4 + 4)
			for component in tangent:
				if not is_finite(component): return {"error": "nonfinite tangent"}
			attrs.tangents.append_array(tangent)
			var total := 0.0
			if skin:
				for influence in influence_count:
					var weight: float = arrays[Mesh.ARRAY_WEIGHTS][index * influence_count + influence]
					if not is_finite(weight) or weight < 0 or arrays[Mesh.ARRAY_BONES][index * influence_count + influence] < 0:
						return {"error": "invalid skin influence"}
					total += weight
				if total <= 0: return {"error": "skin vertex has no positive influence"}
			for influence in 8:
				attrs.bones.append(arrays[Mesh.ARRAY_BONES][index * influence_count + influence] if skin and influence < influence_count else 0)
				attrs.weights.append(arrays[Mesh.ARRAY_WEIGHTS][index * influence_count + influence] / total if skin and influence < influence_count else 0.0)
			for shape_index in shape_count:
				var shape: Array = shapes[shape_index]
				var position: Vector3 = shape[Mesh.ARRAY_VERTEX][index]
				var shape_normal: Vector3 = shape[Mesh.ARRAY_NORMAL][index] if _present(shape[Mesh.ARRAY_NORMAL]) else (normal if normalized else Vector3.ZERO)
				if normalized:
					position -= vertices[index]
					shape_normal -= normal
				if not position.is_finite() or not shape_normal.is_finite(): return {"error": "nonfinite blend shape"}
				attrs.blend_shapes[shape_index].positions.append(position)
				attrs.blend_shapes[shape_index].normals.append(shape_normal)
				for component in 4:
					var delta: float = shape[Mesh.ARRAY_TANGENT][index * 4 + component] if _present(shape[Mesh.ARRAY_TANGENT]) else (tangent[component] if normalized else 0.0)
					if normalized: delta -= tangent[component]
					if not is_finite(delta): return {"error": "nonfinite blend tangent"}
					attrs.blend_shapes[shape_index].tangents.append(delta)
		if indices.is_empty():
			for index in count: result.indices.append(base + index)
		else:
			for index in indices:
				if index < 0 or index >= count: return {"error": "triangle indices are malformed"}
				result.indices.append(base + index)
		for triangle in (indices.size() if not indices.is_empty() else count) / 3: result.slots.append(surface)
	if not any_uv: result.uvs = PackedVector2Array()
	if not any_skin:
		attrs.bones = PackedInt32Array()
		attrs.weights = PackedFloat32Array()
	return result

static func envelope(instance: MeshInstance3D) -> Dictionary:
	var names := PackedStringArray()
	var values := PackedFloat32Array()
	if instance.mesh is ArrayMesh:
		for index in instance.mesh.get_blend_shape_count():
			names.append(str(instance.mesh.get_blend_shape_name(index)))
			values.append(instance.get_blend_shape_value(index))
	return {"skin": instance.skin, "skeleton": instance.skeleton, "blend_names": names,
		"blend_values": values, "blend_mode": Mesh.BLEND_SHAPE_MODE_RELATIVE}

static func _present(value: Variant) -> bool:
	return value != null and not value.is_empty()

static func _finite_color(value: Color) -> bool:
	return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
