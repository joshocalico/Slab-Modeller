extends SceneTree

const Selection = preload("res://addons/slab/slab_selection.gd")
const Actions = preload("res://addons/slab/slab_actions.gd")
const Undo = preload("res://tests/slab_test_undo.gd")
const Bake = preload("res://addons/slab/slab_export_mesh.gd")
const Obj = preload("res://addons/slab/slab_export_obj.gd")
const Import = preload("res://addons/slab/slab_import_mesh.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func snapshot(node: Node3D) -> Dictionary:
	var baked := Bake.new()
	check(baked.bake([node]) == OK, "mesh snapshot bakes")
	var triangles: Dictionary = {}
	for t in baked.triangle_count():
		var corners: Array[String] = []
		for k in 3:
			var index: int = baked.indices[t * 3 + k]
			var p: Vector3 = baked.positions[index]
			var uv: Vector2 = baked.uvs[index]
			corners.append("%.3f,%.3f,%.3f/%.3f,%.3f" % [p.x, p.y, p.z, uv.x, uv.y])
		corners.sort()
		triangles[";".join(corners)] = baked.material_names[baked.material_per_triangle[t]]
	return triangles

func _run() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var source: Node3D = ClassDB.instantiate("SlabSolid")
	parent.add_child(source)
	check(source.call("make_box", Vector3(2, 3, 4)) == 0, "source box builds")
	var copper := StandardMaterial3D.new()
	copper.resource_name = "Copper"
	copper.albedo_color = Color(0.7, 0.3, 0.2, 0.6)
	copper.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var artwork := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	artwork.fill(Color(0.2, 0.4, 0.8, 1.0))
	artwork.set_pixel(1, 0, Color(0.8, 0.1, 0.3, 0.5))
	copper.albedo_texture = ImageTexture.create_from_image(artwork)
	var slate := StandardMaterial3D.new()
	slate.resource_name = "Slate"
	slate.albedo_color = Color(0.1, 0.2, 0.3, 1.0)
	source.set("materials", [copper, slate])
	var faces: PackedInt64Array = source.call("get_faces")
	for i in faces.size():
		check(source.call("set_face_material", PackedInt64Array([faces[i]]), i % 2) == 0, "source face material assigned")
		check(source.call("set_face_uv", PackedInt64Array([faces[i]]), Vector2(0.3 + i * 0.1, 0.7), Vector2(i * 0.11, 0.23), 0.3) == 0, "source UVs assigned")
	var before_obj := snapshot(source)
	var baked := Bake.new()
	baked.bake([source])
	var path := "user://promote_attributes.obj"
	check(Obj.write(path, baked) == OK, "multi-material OBJ writes")
	var dependency_paths: Array[String] = []
	var mtl_text: String = FileAccess.get_file_as_string("user://promote_attributes.mtl")
	for line in mtl_text.split("\n"):
		if line.begins_with("map_Kd "):
			dependency_paths.append("user://" + line.substr(7))
	check(dependency_paths.size() == 1, "owned ImageTexture writes a PNG dependency")
	check(Obj.write(path, baked) == OK and FileAccess.get_file_as_string("user://promote_attributes.mtl") == mtl_text, "repeated export uses deterministic texture names")
	if not dependency_paths.is_empty():
		var dependency: String = dependency_paths[0]
		var original_obj: String = FileAccess.get_file_as_string(path)
		DirAccess.rename_absolute(dependency, dependency + ".saved")
		DirAccess.make_dir_absolute(dependency)
		check(Obj.write(path, baked) != OK, "texture write failure is reported")
		check(FileAccess.get_file_as_string(path) == original_obj, "dependency failure leaves existing OBJ untouched")
		DirAccess.remove_absolute(dependency)
		DirAccess.rename_absolute(dependency + ".saved", dependency)
	var imported := Import.load_from_file(path)
	check(imported.error == OK, "multi-material OBJ imports")
	if not imported.has("mesh"):
		source.free()
		parent.free()
		quit(1)
		return
	var external: MeshInstance3D = imported.mesh
	parent.add_child(external)
	external.owner = parent
	check(external.mesh.get_surface_count() == 2, "OBJ preserves both material groups")
	for material in external.get_materials():
		if material.resource_name == "Copper":
			check(material.albedo_color.is_equal_approx(copper.albedo_color), "OBJ roundtrip preserves diffuse color and opacity")
			check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "OBJ preserves alpha blending")
			check(material.albedo_texture != null and material.albedo_texture.get_image().get_pixel(1, 0).is_equal_approx(artwork.get_pixel(1, 0)), "OBJ roundtrip preserves painted RGBA pixel")
		else:
			check(material.albedo_color.is_equal_approx(slate.albedo_color), "OBJ keeps second material color independent")
	check(snapshot(external) == before_obj, "OBJ roundtrip preserves triangle material names and UVs")
	source.free()
	parent.position = Vector3(-2, 3, 1)
	parent.rotation.y = 0.4
	external.top_level = true
	external.position = Vector3(5, 6, 7)
	external.rotation = Vector3(0.1, 0.2, 0.3)
	external.scale = Vector3(-1, 2, 0.5)
	external.visible = false
	var override_material := StandardMaterial3D.new()
	override_material.resource_name = "Surface_override"
	external.set_surface_override_material(1, override_material)
	var child := Node3D.new()
	child.name = "Socket"
	external.add_child(child)
	child.position = Vector3(0.1, 0.2, 0.3)
	child.owner = parent
	var grandchild := Node3D.new()
	child.add_child(grandchild)
	grandchild.owner = external
	var original_transform := external.transform
	var before_promote := snapshot(external)
	var selection := Selection.new()
	selection.set_objects([external])
	var undo := Undo.new()
	var actions := Actions.new(selection, undo)
	var result: Dictionary = actions._run_promote()
	check(result.status == Actions.PROMOTE_SUCCESS, "attributed external promotes: %s" % result.status)
	var solid: Node3D = selection.solid
	if solid == external:
		parent.free()
		quit(1)
		return
	check(snapshot(solid) == before_promote, "Promote preserves world geometry, arbitrary UVs and active material slots")
	check(solid.top_level and solid.transform.is_equal_approx(original_transform) and not solid.visible, "Promote preserves transform and hidden state")
	check(child.get_parent() == solid and child.position.is_equal_approx(Vector3(0.1, 0.2, 0.3)), "Promote retains child and local transform")
	check(child.owner == parent and grandchild.owner == solid, "Promote remaps subtree owners")
	var prior_data: PackedByteArray = solid.get("data")
	var restored: Node3D = ClassDB.instantiate("SlabSolid")
	parent.add_child(restored)
	restored.set("data", prior_data)
	restored.set("materials", solid.get("materials"))
	restored.top_level = solid.top_level
	restored.transform = solid.transform
	check(snapshot(restored) == before_promote, "serialized solid data preserves imported UV/material attributes")
	restored.free()
	var invalid: Dictionary = solid.call("import_from_mesh", PackedVector3Array([Vector3.ZERO]), PackedInt32Array([0, 0, 0]), PackedVector2Array([Vector2.ZERO]), PackedInt32Array([0]))
	check(invalid.error != 0 and solid.get("data") == prior_data, "malformed import leaves existing solid data unchanged")
	undo.undo()
	check(child.get_parent() == external and child.owner == parent and grandchild.owner == external, "Undo restores subtree and owners")
	check(external.transform.is_equal_approx(original_transform) and not external.visible, "Undo preserves original instance state")
	check(external.get_surface_override_material(1) == override_material, "Undo preserves material override")
	undo.redo()
	check(child.get_parent() == solid and snapshot(solid) == before_promote, "Redo restores children and attributed geometry")
	check(int(solid.call("face_uv", solid.call("get_faces")[0]).get("texture_resolution", -1)) == 0, "imported UV mapping starts with unknown atlas resolution")
	external.free()
	parent.free()
	for dependency in dependency_paths:
		DirAccess.remove_absolute(dependency)
	_check_refusals()
	for extension in ["obj", "mtl"]:
		DirAccess.remove_absolute("user://promote_attributes." + extension)
	print("Promote attribute regressions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _check_refusals() -> void:
	var source: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(source)
	source.call("make_box", Vector3.ONE)
	var prototype := Color(0.2, 0.7, 0.4, 1.0)
	source.set("prototype_color", prototype)
	var prototype_bake := Bake.new()
	prototype_bake.bake([source])
	check(prototype_bake.materials.size() == 1 and prototype_bake.materials[0] != null and prototype_bake.materials[0].albedo_color.is_equal_approx(prototype), "unassigned slot exports visible prototype color")
	check(Obj.write("user://prototype_color.obj", prototype_bake) == OK, "prototype color OBJ exports")
	var prototype_import := Import.load_from_file("user://prototype_color.obj")
	check(prototype_import.error == OK, "prototype color OBJ imports")
	if prototype_import.has("mesh"):
		check(prototype_import.mesh.get_materials()[0].albedo_color.is_equal_approx(prototype), "prototype color survives OBJ roundtrip")
		prototype_import.mesh.free()
	DirAccess.remove_absolute("user://prototype_color.obj")
	DirAccess.remove_absolute("user://prototype_color.mtl")
	var material := ShaderMaterial.new()
	source.set("materials", [material])
	var baked := Bake.new()
	baked.bake([source])
	check(Obj.write("user://unsupported_shader.obj", baked) == ERR_UNAVAILABLE, "OBJ refuses shaders instead of silently replacing them")
	check(not FileAccess.file_exists("user://unsupported_shader.obj"), "unsupported material creates no partial OBJ")
	var external = preload("res://addons/slab/slab_external_mesh.gd").from_mesh(source.call("build_mesh"))
	root.add_child(external)
	var child := Node3D.new()
	child.name = "Mesh"
	external.add_child(child)
	var selection := Selection.new()
	selection.set_objects([external])
	var actions := Actions.new(selection)
	var result: Dictionary = actions._run_promote()
	check(str(result.status).contains("reserved") and child.get_parent() == external and selection.solid == external, "conflicting child names refuse without renaming or removing them")
	external.free()
	source.free()
	var file := FileAccess.open("user://missing_material.obj", FileAccess.WRITE)
	file.store_string("mtllib does_not_exist.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
	file.close()
	var imported := Import.load_from_file("user://missing_material.obj")
	check(imported.error != OK and not imported.has("mesh"), "missing MTL refuses without dropping material data")
	DirAccess.remove_absolute("user://missing_material.obj")
