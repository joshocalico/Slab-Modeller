extends SceneTree
const Fixture := preload("res://tests/deformation_fixture.gd")
const Attributes := preload("res://addons/slab/slab_mesh_attributes.gd")
const Exchange := preload("res://addons/slab/slab_gltf_exchange.gd")
const Import := preload("res://addons/slab/slab_import_mesh.gd")
const External := preload("res://addons/slab/slab_external_mesh.gd")
var failures := 0
var checks := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", message)
func _run() -> void:
	_check_plain_solid_exchange()
	_check_native_refusals()
	for normalized in [false, true]:
		var mesh := Fixture.mesh(normalized)
		var flat := Attributes.flatten(mesh)
		check(not flat.has("error"), "valid attributed mesh flattens")
		if flat.has("error"): continue
		check(flat.attributes.blend_shapes[0].positions[0].is_equal_approx(Vector3(0.25, 0, 0)), "blend mode converts to relative deltas")
		check(flat.attributes.bones.size() == flat.vertices.size() * 8 and is_equal_approx(flat.attributes.weights[0], 1), "skin has eight normalized influence slots")
		check(flat.attributes.uv2[0].is_equal_approx(Vector2(0.25, 0.75)) and flat.attributes.colors[0].is_equal_approx(Color(0.2, 0.4, 0.6, 0.8)), "UV2 and colors survive canonical boundary")
	var scene := Node3D.new()
	root.add_child(scene)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Rig"
	skeleton.add_bone("Root")
	scene.add_child(skeleton)
	var external := External.from_mesh(Fixture.mesh(true))
	external.name = "Subject"
	scene.add_child(external)
	external.skeleton = NodePath("../Rig")
	var skin := Skin.new()
	skin.add_bind(0, Transform3D.IDENTITY)
	external.skin = skin
	external.set_blend_shape_value(0, 0.6)
	external.skeleton = NodePath()
	var unbound := Exchange.scene_from_solids([external])
	check(unbound.error != OK, "skin without skeleton binding refuses instead of dropping deformation")
	if unbound.error == OK: unbound.scene.free()
	external.skeleton = NodePath("../Rig")
	for extension in ["glb", "gltf"]:
		var folder: String = "user://attribute_exchange_" + extension
		DirAccess.make_dir_recursive_absolute(folder)
		var path: String = folder.path_join("subject." + extension)
		var exported := Exchange.write(path, [external])
		check(exported.error == OK, extension + " exports current attributed mesh: " + str(exported))
		if exported.error == OK:
			var imported := Import.load_from_file(path)
			check(imported.error == OK, extension + " loads generated file: " + str(imported.get("message", "")))
			if imported.error == OK:
				var meshes: Array[Node] = imported.mesh.find_children("*", "MeshInstance3D", true, false)
				check(not meshes.is_empty(), extension + " has imported mesh")
				if not meshes.is_empty():
					var mesh: MeshInstance3D = meshes[0]
					check(mesh.skin != null and mesh.get_node_or_null(mesh.skeleton) is Skeleton3D, extension + " skin resolves imported skeleton")
					check(mesh.mesh.get_blend_shape_count() == 1 and is_equal_approx(mesh.get_blend_shape_value(0), 0.6), extension + " keeps morph and active weight")
					var arrays: Array = mesh.mesh.surface_get_arrays(0)
					check(arrays[Mesh.ARRAY_TEX_UV2] != null and arrays[Mesh.ARRAY_COLOR] != null, extension + " retains UV2 and color channels")
				_check_import_history(imported.mesh, extension)
		Exchange._remove_tree(folder)
	scene.free()
	print("MESH_ATTRIBUTES_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check_native_refusals() -> void:
	var flat := Attributes.flatten(Fixture.mesh(false))
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.make_box(Vector3(3, 3, 3))
	var before: PackedByteArray = solid.data
	var bad: Dictionary = flat.attributes.duplicate(true)
	bad.uv2[0] = Vector2(NAN, 0)
	var result: Dictionary = solid.import_from_mesh(flat.vertices, flat.indices, flat.uvs, flat.slots, bad)
	check(result.error != OK and solid.data == before, "non-finite imported channel refuses atomically")
	bad = flat.attributes.duplicate(true)
	bad.skin_present[flat.indices[0] if not flat.indices.is_empty() else 0] = 0
	result = solid.import_from_mesh(flat.vertices, flat.indices, flat.uvs, flat.slots, bad)
	check(result.error != OK and solid.data == before, "mixed skin presence within a triangle refuses atomically")
	solid.free()

func _check_import_history(imported: Node3D, extension: String) -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var history := UndoRedo.new()
	history.create_action("Import Mesh")
	history.add_do_method(scene.add_child.bind(imported))
	history.add_do_method(Import.set_scene_owner.bind(imported, scene))
	history.add_undo_method(scene.remove_child.bind(imported))
	history.commit_action()
	check(imported.owner == scene, extension + " imported hierarchy belongs to edited scene")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, extension + " imported hierarchy packs")
	var reopened := packed.instantiate()
	var meshes := reopened.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty(), extension + " imported child meshes survive scene save")
	if not meshes.is_empty():
		check(meshes[0].skin != null and meshes[0].get_node_or_null(meshes[0].skeleton) is Skeleton3D, extension + " saved hierarchy keeps skin binding")
	reopened.free()
	history.undo()
	check(imported.get_parent() == null and scene.get_child_count() == 0, extension + " Undo removes entire import")
	history.redo()
	check(imported.get_parent() == scene and imported.owner == scene, extension + " Redo restores import and ownership")
	history.clear_history()
	scene.free()

# Also run this suite with --editor: Godot's editor generates importer-only mesh
# nodes unless the runtime converter is registered for the dialog import.
func _check_plain_solid_exchange() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.name = "Solid"
	root.add_child(solid)
	solid.make_box(Vector3(2, 2, 2))
	solid.position = Vector3(-5, 0, 0)
	var before: PackedByteArray = solid.data
	for extension in ["glb", "gltf"]:
		var folder: String = "user://plain_solid_exchange_" + extension
		DirAccess.make_dir_recursive_absolute(folder)
		var path: String = folder.path_join("solid." + extension)
		var exported := Exchange.write(path, [solid])
		check(exported.error == OK, extension + " exports plain SlabSolid")
		if exported.error == OK:
			var imported := Import.load_from_file(path)
			check(imported.error == OK, extension + " imports plain SlabSolid in editor or runtime: " + str(imported.get("message", "")))
			if imported.error == OK:
				var meshes: Array[Node] = imported.mesh.find_children("*", "MeshInstance3D", true, false)
				check(meshes.size() == 1 and meshes[0].get_script() == External, extension + " produces selectable External mesh")
				if meshes.size() == 1:
					check(meshes[0].position.is_equal_approx(solid.position) and meshes[0].visible, extension + " keeps plain solid transform and visibility")
				imported.mesh.free()
		Exchange._remove_tree(folder)
	check(solid.data == before, "plain solid export is non-destructive")
	solid.free()
