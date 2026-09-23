extends RefCounted

static func mesh(normalized: bool) -> ArrayMesh:
	var source: Node3D = ClassDB.instantiate("SlabSolid")
	source.call("make_box", Vector3(2, 2, 2))
	var base: ArrayMesh = source.call("build_mesh")
	var mesh := ArrayMesh.new()
	mesh.add_blend_shape("Stretch")
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED if normalized else Mesh.BLEND_SHAPE_MODE_RELATIVE
	for surface in base.get_surface_count():
		var arrays: Array = base.surface_get_arrays(surface).duplicate(true)
		var count: int = arrays[Mesh.ARRAY_VERTEX].size()
		var uv2 := PackedVector2Array()
		var colors := PackedColorArray()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		var shape: Array = []
		shape.resize(Mesh.ARRAY_MAX)
		var positions := PackedVector3Array()
		var normals := PackedVector3Array()
		var tangents := PackedFloat32Array()
		for vertex in count:
			uv2.append(Vector2(0.25, 0.75))
			colors.append(Color(0.2, 0.4, 0.6, 0.8))
			bones.append_array(PackedInt32Array([0, 0, 0, 0]))
			weights.append_array(PackedFloat32Array([1, 0, 0, 0]))
			positions.append(Vector3(0.25, 0, 0) + (arrays[Mesh.ARRAY_VERTEX][vertex] if normalized else Vector3.ZERO))
			normals.append(arrays[Mesh.ARRAY_NORMAL][vertex] if normalized else Vector3.ZERO)
			if arrays[Mesh.ARRAY_TANGENT] != null:
				for component in 4: tangents.append(arrays[Mesh.ARRAY_TANGENT][vertex * 4 + component] if normalized else 0.0)
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		shape[Mesh.ARRAY_VERTEX] = positions
		shape[Mesh.ARRAY_NORMAL] = normals
		if not tangents.is_empty(): shape[Mesh.ARRAY_TANGENT] = tangents
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shape])
	source.free()
	return mesh

