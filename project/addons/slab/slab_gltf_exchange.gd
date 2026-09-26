@tool
extends RefCounted

const External := preload("res://addons/slab/slab_external_mesh.gd")
const Attributes := preload("res://addons/slab/slab_mesh_attributes.gd")
const Ids := preload("res://addons/slab/slab_construction_step.gd")

static func load_scene(path: String) -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	# Runtime registers this converter automatically; editor imports normally keep
	# ImporterMeshInstance3D nodes for the asset pipeline. Our dialog needs editable
	# MeshInstance3D nodes immediately, including skins and visibility settings.
	var converter := GLTFDocumentExtensionConvertImporterMesh.new()
	GLTFDocument.register_gltf_document_extension(converter)
	var error := document.append_from_file(path, state)
	if error != OK:
		GLTFDocument.unregister_gltf_document_extension(converter)
		return {"error": error, "message": "Could not read glTF scene and its dependencies."}
	var scene := document.generate_scene(state)
	GLTFDocument.unregister_gltf_document_extension(converter)
	if scene == null: return {"error": ERR_INVALID_DATA, "message": "glTF scene could not be generated."}
	# Skinned nodes can be replaced during scene generation, leaving the state's
	# original scene-node handle stale. Resolve those nodes by their generated name.
	var records: Array = state.get_json().get("nodes", [])
	var nodes := state.get_nodes()
	var meshes := state.get_meshes()
	var generated_meshes := scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D: generated_meshes.append(scene)
	for index in nodes.size():
		var mesh_index: int = nodes[index].mesh
		if mesh_index < 0: continue
		var generated: Node = state.get_scene_node(index)
		if not is_instance_valid(generated):
			var matches: Array[Node] = []
			for candidate in generated_meshes:
				if candidate.name == nodes[index].resource_name:
					matches.append(candidate)
			if matches.size() == 1:
				generated = matches[0]
			elif not meshes[mesh_index].blend_weights.is_empty():
				scene.free()
				return {"error": ERR_INVALID_DATA, "message": "Could not resolve blend shape weights to a unique imported mesh."}
		if generated is MeshInstance3D:
			var weights := PackedFloat32Array(meshes[mesh_index].blend_weights)
			if index < records.size() and records[index].has("weights"):
				weights = PackedFloat32Array(records[index].weights)
			for shape in mini(generated.mesh.get_blend_shape_count(), weights.size()):
				generated.set_blend_shape_value(shape, weights[shape])
	var count := 0
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh != null:
			node.set_script(External)
			node.set_source_path(path)
			count += 1
	if count == 0:
		scene.free()
		return {"error": ERR_INVALID_DATA, "message": "glTF scene contains no meshes."}
	return {"error": OK, "mesh": scene, "status": "Imported glTF hierarchy with materials, skin bindings and blend shapes. Select a mesh to Promote."}

# Build an export scene from CURRENT generated meshes and only their referenced
# skeletons. No saved pre-Promote mesh is used or kept in the deformation envelope.
static func scene_from_solids(solids: Array) -> Dictionary:
	var scene := Node3D.new()
	scene.name = "SlabExport"
	var skeletons: Dictionary = {}
	var output_count := 0
	for solid in solids:
		if not is_instance_valid(solid) or not solid is Node3D: continue
		var mesh: ArrayMesh = solid.build_mesh() if solid.has_method("build_mesh") else (solid.mesh if solid is MeshInstance3D else null)
		if mesh == null: continue
		var instance := MeshInstance3D.new()
		instance.name = solid.name
		mesh = mesh.duplicate()
		instance.mesh = mesh
		instance.transform = solid.global_transform if solid.is_inside_tree() else solid.transform
		scene.add_child(instance, true)
		instance.owner = scene
		var materials: Array = solid.get_materials() if solid.has_method("get_materials") else []
		if solid.is_class("SlabSolid"): materials = solid.call("get_mesh_materials")
		for surface in mesh.get_surface_count():
			var material: Material = materials[surface] if surface < materials.size() else mesh.surface_get_material(surface)
			if solid is MeshInstance3D: material = solid.get_active_material(surface)
			if material is ShaderMaterial:
				scene.free()
				return {"error": ERR_UNAVAILABLE, "message": "glTF cannot represent a Godot shader material."}
			if material != null: instance.set_surface_override_material(surface, material)
		var deformation: Dictionary = Attributes.envelope(solid) if solid is MeshInstance3D else solid.get("deformation")
		instance.skin = deformation.get("skin")
		var skeleton_path: NodePath = deformation.get("skeleton", NodePath())
		if instance.skin != null and skeleton_path.is_empty():
			scene.free()
			return {"error": ERR_INVALID_DATA, "message": "A skin has no Skeleton3D binding; export would lose deformation."}
		if not skeleton_path.is_empty():
			var skeleton: Node = solid.get_node_or_null(skeleton_path)
			if skeleton is Skeleton3D:
				if not skeletons.has(skeleton):
					var copy: Skeleton3D = skeleton.duplicate(0)
					for child in copy.get_children(): child.free()
					copy.transform = skeleton.global_transform
					scene.add_child(copy, true)
					copy.owner = scene
					skeletons[skeleton] = copy
				instance.skeleton = instance.get_path_to(skeletons[skeleton])
			elif instance.skin != null:
				scene.free()
				return {"error": ERR_INVALID_DATA, "message": "A skin's Skeleton3D is missing; export would lose deformation."}
		var weights: PackedFloat32Array = deformation.get("blend_values", PackedFloat32Array())
		for shape in mini(mesh.get_blend_shape_count(), weights.size()): instance.set_blend_shape_value(shape, weights[shape])
		output_count += 1
	if output_count == 0:
		scene.free()
		return {"error": ERR_INVALID_DATA, "message": "No generated meshes to export."}
	return {"error": OK, "scene": scene}

static func write(path: String, solids: Array) -> Dictionary:
	var built := scene_from_solids(solids)
	if built.error != OK: return built
	var scene: Node3D = built.scene
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null: tree.root.add_child(scene)
	var error := document.append_from_scene(scene, state)
	if error != OK:
		scene.free()
		return {"error": error, "message": "glTF could not encode the generated scene."}
	# Godot exports mesh defaults independently of each instance's current pose.
	# Each export instance owns its mesh, so its current weights are unambiguous.
	var nodes := state.get_nodes()
	var meshes := state.get_meshes()
	for index in nodes.size():
		var node := state.get_scene_node(index)
		var mesh_index: int = nodes[index].mesh
		if node is MeshInstance3D and mesh_index >= 0:
			var values := PackedFloat32Array()
			for shape in node.mesh.get_blend_shape_count():
				values.append(node.get_blend_shape_value(shape))
			meshes[mesh_index].blend_weights = values
	var token := Ids.new_uuid()
	var extension := path.get_extension().to_lower()
	var assets := path.get_basename().get_file() + "_assets_" + token
	var staging := path.get_base_dir().path_join(assets)
	if extension not in ["glb", "gltf"]:
		scene.free()
		return {"error": ERR_INVALID_PARAMETER, "message": "Choose a .glb or .gltf filename."}
	error = DirAccess.make_dir_recursive_absolute(staging)
	if error != OK:
		scene.free()
		return {"error": error, "message": "Could not create export staging directory."}
	var staged := staging.path_join("scene." + extension)
	error = document.write_to_filesystem(state, staged)
	scene.free()
	if error != OK:
		_remove_tree(staging)
		return {"error": error, "message": "Could not write glTF dependencies."}
	if extension == "gltf":
		var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(staged))
		if not json is Dictionary:
			_remove_tree(staging)
			return {"error": ERR_FILE_CORRUPT, "message": "Generated glTF document is invalid."}
		for section in ["buffers", "images"]:
			for dependency in json.get(section, []):
				if dependency.has("uri") and not str(dependency.uri).begins_with("data:"):
					dependency.uri = assets.path_join(str(dependency.uri))
		var file := FileAccess.open(staged, FileAccess.WRITE)
		if file == null:
			_remove_tree(staging)
			return {"error": ERR_CANT_CREATE, "message": "Could not write final glTF manifest."}
		file.store_string(JSON.stringify(json))
		file.close()
	error = DirAccess.rename_absolute(staged, path)
	if error != OK:
		_remove_tree(staging)
		return {"error": error, "message": "Could not publish glTF file; existing export remains unchanged."}
	if extension == "glb": _remove_tree(staging)
	return {"error": OK}

static func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for child in directory.get_directories(): _remove_tree(path.path_join(child))
	for file in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
