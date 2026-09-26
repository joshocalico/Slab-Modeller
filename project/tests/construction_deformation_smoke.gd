extends SceneTree

const Construction := preload("res://addons/slab/slab_construction.gd")
const Step := preload("res://addons/slab/slab_construction_step.gd")
const Fixture := preload("res://tests/deformation_fixture.gd")
const Attributes := preload("res://addons/slab/slab_mesh_attributes.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", message)

func _run() -> void:
	var scene := Node3D.new()
	scene.name = "ConstructionDeformation"
	root.add_child(scene)
	var rig := Skeleton3D.new()
	rig.name = "Rig"
	rig.add_bone("Root")
	scene.add_child(rig)
	rig.owner = scene
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.name = "Subject"
	scene.add_child(solid)
	solid.owner = scene
	var flat := Attributes.flatten(Fixture.mesh(false))
	check(solid.call("import_from_mesh", flat.vertices, flat.indices, flat.uvs, flat.slots, flat.attributes).error == OK, "construction source imports full corner attributes")
	var skin := Skin.new()
	skin.add_bind(0, Transform3D.IDENTITY)
	var envelope := {"skin": skin, "skeleton": NodePath("../Rig"), "blend_names": PackedStringArray(["Stretch"]), "blend_values": PackedFloat32Array([0.6]), "blend_mode": Mesh.BLEND_SHAPE_MODE_RELATIVE}
	solid.set("deformation", envelope)
	var engine := Construction.new()
	var undo := UndoRedo.new()
	var recipe := Construction.from_mesh(solid)
	var array := Step.new()
	array.kind = Step.Kind.ARRAY_LINEAR
	array.parameters = {"count": 2, "step": Vector3(3, 0, 0)}
	recipe.steps.append(array)
	var result := engine.apply_candidate(solid, recipe, scene, undo)
	check(result.error == OK, "attributed mesh source supports array history")
	if result.error == OK:
		var child: Node3D = solid.get_child(0)
		check(solid.get("deformation") == envelope, "rebuild preserves primary binding and morph weight")
		check(child.get("deformation").skin == skin and child.get_node_or_null(child.get("deformation").skeleton) == rig, "generated copy retains Skin identity and resolves its rebased skeleton path")
		check(child.call("build_mesh").get_blend_shape_name(0) == &"Stretch", "array output retains named morph geometry")
		undo.undo()
		check(solid.get_child_count() == 0 and solid.get("deformation") == envelope, "array Undo restores binding and removes output")
		undo.redo()
		check(solid.get_child(0) == child and child.get_node_or_null(child.get("deformation").skeleton) == rig, "array Redo restores same bound output")
		var changed: Dictionary = envelope.duplicate()
		changed.blend_values = PackedFloat32Array([0.25])
		solid.set("deformation", changed)
		result = engine.edit_step(solid, array.id, {"count": 3}, scene, undo)
		check(result.error != OK and solid.get("deformation") == changed, "manual deformation changes cannot be overwritten by rebuilding")
		solid.set("deformation", envelope)
		var packed := PackedScene.new()
		check(packed.pack(scene) == OK and ResourceSaver.save(packed, "user://construction_deformation.tscn") == OK, "recipe and deformation scene save")
		var saved: PackedScene = ResourceLoader.load("user://construction_deformation.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		var reopened := saved.instantiate()
		root.add_child(reopened)
		var restored: Node3D = reopened.get_node("Subject")
		result = engine.edit_step(restored, array.id, {"count": 3}, reopened)
		check(result.error == OK and restored.get_child_count() == 2, "saved attributed recipe can rebuild after reopening")
		for output in restored.get_children():
			check(output.get_node_or_null(output.get("deformation").skeleton) == reopened.get_node("Rig"), "reopened generated copy resolves reopened rig")
		reopened.free()
		DirAccess.remove_absolute("user://construction_deformation.tscn")
	undo.clear_history()
	undo.free()
	scene.free()
	print("CONSTRUCTION_DEFORMATION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
