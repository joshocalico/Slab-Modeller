extends SceneTree
var DEST: String
var scene_path := "res://demo/signal_relay_annex/signal_relay_annex.tscn"
var image_paths: Dictionary = {}
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		if args[index] == "--output" and index + 1 < args.size():
			DEST = args[index + 1]
			index += 2
		elif args[index] == "--scene" and index + 1 < args.size():
			scene_path = args[index + 1]
			index += 2
		else:
			push_error("Expected --output ABSOLUTE_DIRECTORY [--scene res://scene.tscn]")
			quit(2)
			return
	if not DEST.is_absolute_path():
		push_error("--output must be an absolute directory outside the project")
		quit(2)
		return
	call_deferred("_run")
func xyz(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
func xy(v: Vector2) -> Array:
	return [v.x, v.y]
func texture_info(texture: Texture2D) -> Dictionary:
	if texture == null: return {}
	var key: int = texture.get_instance_id()
	if image_paths.has(key): return image_paths[key]
	var im: Image = texture.get_image()
	if im == null: return {"missing": true, "resource": texture.resource_path}
	if im.is_compressed() and im.decompress() != OK: return {"unsupported_compression": true}
	var path := DEST.path_join("image_%d.png" % image_paths.size())
	var info := {"resource": texture.resource_path, "path": path, "width": im.get_width(), "height": im.get_height(), "save_error": im.save_png(path)}
	image_paths[key] = info
	return info
func mat_info(mat: Material) -> Dictionary:
	if not mat is StandardMaterial3D: return {"unsupported": mat.get_class() if mat else "null"}
	return {"resource": mat.resource_path, "albedo_color": mat.albedo_color.to_html(), "albedo": texture_info(mat.albedo_texture), "uv_scale": xyz(mat.uv1_scale), "uv_offset": xyz(mat.uv1_offset), "triplanar": mat.uv1_triplanar, "repeat": mat.texture_repeat, "emission_enabled": mat.emission_enabled, "emission_operator": mat.emission_operator, "emission_energy": mat.emission_energy_multiplier, "emission_color": mat.emission.to_html(), "emission": texture_info(mat.emission_texture)}
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DEST)
	var scene: Node3D = load(scene_path).instantiate()
	root.add_child(scene)
	await process_frame
	var report := {"scene_sha256": FileAccess.get_sha256(scene_path), "solids": [], "editor_metadata": [], "limitations": ["Pixel analysis uses generated mesh UVs; triplanar/shader materials are reported unsupported.", "Kernel validity is checked by deserializing editable bytes, whose native path invokes kernel validate.", "Collision presence does not establish player climbability; geometry checks are separate."]}
	var all_nodes: Array = [scene]
	all_nodes.append_array(scene.find_children("*", "", true, false))
	for node in all_nodes:
		if node.has_meta("_edit_lock_") or node.has_meta("_edit_group_"):
			report.editor_metadata.append({"path": str(scene.get_path_to(node)), "lock": node.get_meta("_edit_lock_", false), "group": node.get_meta("_edit_group_", false)})
		if not node.is_class("SlabSolid"): continue
		var box: AABB = node.global_transform * node.get_local_aabb()
		var data: PackedByteArray = node.get_data()
		var clone: Node = ClassDB.instantiate("SlabSolid")
		clone.set_data(data)
		var item := {"name": str(node.name), "position": xyz(node.position), "rotation": xyz(node.rotation_degrees), "scale": xyz(node.scale), "bounds_min": xyz(box.position), "bounds_max": xyz(box.end), "bytes": data.size(), "kernel_deserialize_valid": clone.face_count() > 0 and clone.get_data() == data, "faces": [], "surfaces": [], "collision_enabled": node.collision_enabled, "collision_shapes": [], "volume": node.volume(), "visible": node.is_visible_in_tree(), "editor_lock": node.get_meta("_edit_lock_", false), "editor_group": node.get_meta("_edit_group_", false)}
		clone.free()
		for face in node.get_faces():
			var attr: Dictionary = node.face_uv(face)
			var corners: Array = []
			for corner in node.face_corners(face): corners.append(xyz(corner))
			item.faces.append({"id": face, "slot": attr.slot, "material_resource": node.materials[attr.slot].resource_path if attr.slot < node.materials.size() and node.materials[attr.slot] else "prototype fallback", "unwrapped": attr.unwrapped, "texture_resolution": attr.get("texture_resolution", 0), "local_corners": corners, "world_center": xyz(node.global_transform * node.face_centroid(face)), "world_normal": xyz((node.global_transform.basis.inverse().transposed() * node.face_normal(face)).normalized())})
		var mesh_node: MeshInstance3D = node.get_node_or_null("Mesh")
		var mesh: ArrayMesh = node.build_mesh()
		var materials: Array = node.get_mesh_materials()
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var points: Array = []
			var texcoords: Array = []
			for v in vertices: points.append(xyz(node.global_transform * v))
			for u in uv: texcoords.append(xy(u))
			var mat: Material = mesh_node.get_active_material(surface) if mesh_node else materials[surface]
			item.surfaces.append({"surface": surface, "material_slot": node.materials.find(mat), "material": mat_info(mat), "vertices": points, "uv": texcoords, "indices": Array(indices)})
		for child in node.find_children("*", "CollisionShape3D", true, false):
			var shape: Shape3D = child.shape
			item.collision_shapes.append({"disabled": child.disabled, "shape": shape.get_class() if shape else "null", "triangles": shape.get_faces().size() / 3 if shape is ConcavePolygonShape3D else 0, "body": child.get_parent().get_class(), "layer": child.get_parent().collision_layer if child.get_parent() is CollisionObject3D else 0})
		report.solids.append(item)
	var file := FileAccess.open(DEST.path_join("scene.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ANNEX_ACCEPTANCE_DUMP ", report.solids.size(), " solids -> ", DEST)
	scene.free()
	quit()
