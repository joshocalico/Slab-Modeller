extends SceneTree
const Fixture := preload("res://tests/deformation_fixture.gd")
const Attributes := preload("res://addons/slab/slab_mesh_attributes.gd")
const External := preload("res://addons/slab/slab_external_mesh.gd")
const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const TestUndo := preload("res://tests/slab_test_undo.gd")
const Exchange := preload("res://addons/slab/slab_gltf_exchange.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", message)


func verify_mesh(mesh: ArrayMesh, label: String) -> void:
	check(mesh.get_blend_shape_count() == 1 and mesh.get_blend_shape_name(0) == &"Stretch", label + " retains named blend shape")
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var count: int = arrays[Mesh.ARRAY_VERTEX].size()
		check(arrays[Mesh.ARRAY_TEX_UV2] != null and arrays[Mesh.ARRAY_TEX_UV2].size() == count, label + " emits UV2 per vertex")
		check(arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR][0].is_equal_approx(Color(0.2, 0.4, 0.6, 0.8)), label + " retains vertex color")
		check(arrays[Mesh.ARRAY_WEIGHTS] != null and is_equal_approx(arrays[Mesh.ARRAY_WEIGHTS][0], 1.0), label + " retains skin weights")
		var shapes: Array = mesh.surface_get_blend_shape_arrays(surface)
		if not shapes.is_empty(): check(shapes[0][Mesh.ARRAY_VERTEX][0].is_equal_approx(Vector3(0.25, 0, 0)), label + " emits relative morph deltas")

func _run() -> void:
	for normalized in [false, true]:
		var input := Fixture.mesh(normalized)
		var flat := Attributes.flatten(input)
		check(not flat.has("error"), "attribute adapter accepts valid deformation")
		check(flat.attributes.blend_shapes[0].positions[0].is_equal_approx(Vector3(0.25, 0, 0)), "both blend modes canonicalize to relative deltas")
	var scene := Node3D.new()
	scene.name = "DeformationFixture"
	root.add_child(scene)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Rig"
	skeleton.add_bone("Root")
	scene.add_child(skeleton)
	skeleton.owner = scene
	var external := External.from_mesh(Fixture.mesh(true))
	external.name = "Subject"
	scene.add_child(external)
	external.owner = scene
	external.skeleton = NodePath("../Rig")
	var skin := Skin.new()
	skin.add_bind(0, Transform3D.IDENTITY)
	external.skin = skin
	external.set_blend_shape_value(0, 0.6)
	var selection := Selection.new()
	selection.set_objects([external])
	var undo := TestUndo.new()
	var actions := Actions.new(selection, undo)
	var result: Dictionary = actions._run_promote()
	var solid: Node3D = selection.solid
	check(solid != external and solid.is_class("SlabSolid"), "Promote converts skinned morph mesh: " + str(result))
	if solid == external:
		scene.free()
		quit(1)
		return
	verify_mesh(solid.call("build_mesh"), "Promote")
	var envelope: Dictionary = solid.get("deformation")
	check(envelope.skin == skin and envelope.skeleton == NodePath("../Rig") and is_equal_approx(envelope.blend_values[0], 0.6), "Promote retains usable binding envelope and current morph weight")
	var mesh_node: MeshInstance3D = solid.get_node("Mesh")
	check(mesh_node.skin == skin and mesh_node.get_node_or_null(mesh_node.skeleton) == skeleton, "internal generated mesh resolves original skeleton")
	undo.undo()
	check(selection.solid == external and external.skin == skin, "Promote Undo restores original usable binding")
	undo.redo()
	check(selection.solid == solid, "Promote Redo restores attributed solid")
	check(solid.call("move_vertices", solid.call("get_vertices"), Vector3(0, 1, 0)) == OK, "attributed solid remains editable")
	verify_mesh(solid.call("build_mesh"), "Edit")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "deformed solid scene packs")
	var path: String = "user://deformation_scene.tscn"
	check(ResourceSaver.save(packed, path) == OK, "deformed solid scene saves")
	var reopened: Node3D = (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(reopened)
	var restored: Node3D = reopened.get_node("Subject")
	verify_mesh(restored.call("build_mesh"), "Reload")
	var restored_mesh: MeshInstance3D = restored.get_node("Mesh")
	check(restored_mesh.get_node_or_null(restored_mesh.skeleton) == reopened.get_node("Rig"), "reloaded internal mesh resolves saved skeleton")
	for extension in ["glb", "gltf"]:
		var export_path: String = "user://deformation_roundtrip." + extension
		var exported := Exchange.write(export_path, [restored])
		check(exported.error == OK, extension + " exports current generated attributes: " + str(exported))
		if exported.error == OK:
			var imported := Exchange.load_scene(export_path)
			check(imported.error == OK, extension + " reimports hierarchy")
			if imported.error == OK:
				var meshes: Array[Node] = imported.mesh.find_children("*", "MeshInstance3D", true, false)
				check(not meshes.is_empty() and meshes[0].mesh.get_blend_shape_count() == 1 and meshes[0].skin != null, extension + " preserves skin and morph in actual exchange")
				check(not meshes.is_empty() and is_equal_approx(meshes[0].get_blend_shape_value(0), .6), extension + " preserves current morph weight")
				imported.mesh.free()
		DirAccess.remove_absolute(export_path)
	reopened.free()
	scene.free()
	external.free()
	DirAccess.remove_absolute(path)
	print("PROMOTE_DEFORMATION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
