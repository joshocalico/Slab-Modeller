extends SceneTree

const Construction := preload("res://addons/slab/slab_construction.gd")
const Step := preload("res://addons/slab/slab_construction_step.gd")

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", message)

func _solid(parent: Node, label: String, size: Vector3 = Vector3(4, 4, 4)) -> Node3D:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.name = label
	parent.add_child(solid)
	solid.owner = parent
	solid.call("make_box", size)
	return solid

func _step(kind: int, parameters: Dictionary) -> Resource:
	var step := Step.new()
	step.kind = kind
	step.parameters = parameters
	return step

func _run() -> void:
	var scene := Node3D.new()
	scene.name = "ConstructionFixture"
	root.add_child(scene)
	var target := _solid(scene, "Target")
	var cutter := _solid(scene, "Cutter", Vector3(2, 2, 2))
	cutter.position = Vector3(1.5, 0, 0)
	var target_material := StandardMaterial3D.new()
	var cutter_material := StandardMaterial3D.new()
	target_material.albedo_color = Color.RED
	cutter_material.albedo_color = Color.BLUE
	target.set("materials", [target_material])
	cutter.set("materials", [cutter_material])
	var engine := Construction.new()
	var undo := UndoRedo.new()
	var recipe = Construction.from_primitive(target, &"make_box", [Vector3(4, 4, 4)])
	var source_id: String = recipe.steps[0].id
	var bevel := _step(Step.Kind.BEVEL, {"amount": 0.1, "segments": 1})
	recipe.steps.append(bevel)
	var cut := _step(Step.Kind.BOOLEAN, {"mode": 1})
	cut.operand_uuid = Construction.ensure_uuid(cutter)
	recipe.steps.append(cut)
	var original: PackedByteArray = target.get("data")
	var result := engine.apply_candidate(target, recipe, scene, undo)
	check(result.error == OK, "primitive → bevel → live Boolean operand builds: " + str(result.get("message", "")))
	if result.error != OK:
		undo.clear_history()
		undo.free()
		scene.free()
		quit(1)
		return
	check(target.get("data") != original and target.call("face_count") > 6, "construction produces actual edited topology")
	check(target.get("materials").has(cutter_material), "Boolean construction retains operand material identity")
	var built: PackedByteArray = target.get("data")
	var version := undo.get_version()
	result = engine.edit_step(target, source_id, {"args": [Vector3(5, 4, 4)]}, scene, undo)
	check(result.error == OK and target.get("data") != built, "primitive parameters replay downstream operations")
	check(undo.get_version() == version + 1, "one parameter edit creates one Undo action")
	var resized: PackedByteArray = target.get("data")
	undo.undo()
	check(target.get("data") == built and target.get_meta(Construction.RECIPE_META).steps[0].parameters.args[0] == Vector3(4, 4, 4), "Undo restores recipe and exact mesh together")
	undo.redo()
	check(target.get("data") == resized, "Redo restores accepted rebuilt mesh")
	var good_recipe: Resource = target.get_meta(Construction.RECIPE_META)
	version = undo.get_version()
	var invalid_bevel = good_recipe.copy_recipe()
	invalid_bevel.steps[1].selection_binding = Step.SelectionBinding.ALL_EDGES
	result = engine.apply_candidate(target, invalid_bevel, scene, undo)
	check(result.error != OK and target.get("data") == resized and target.get_meta(Construction.RECIPE_META) == good_recipe and undo.get_version() == version,
		"failed kernel rebuild preserves last good mesh, recipe, materials and Undo")
	result = engine.set_step_enabled(target, cut.id, false, scene, undo)
	check(result.error == OK and target.get("data") != resized, "bypassing Boolean rebuilds its actual input")
	undo.undo()
	check(target.get("data") == resized, "bypass Undo restores exact Boolean result")
	result = engine.reorder_step(target, source_id, 1, scene, undo)
	check(result.error != OK and target.get("data") == resized, "source cannot reorder behind a modifier")

	# A dependency cycle must be caught before either node is published.
	var cutter_recipe = Construction.from_primitive(cutter, &"make_box", [Vector3(2, 2, 2)])
	var cycle := _step(Step.Kind.BOOLEAN, {"mode": 0})
	cycle.operand_uuid = str(target.get_meta(Construction.UUID_META))
	cutter_recipe.steps.append(cycle)
	var cutter_before: PackedByteArray = cutter.get("data")
	result = engine.apply_candidate(cutter, cutter_recipe, scene, undo)
	check(result.error != OK and result.message.contains("cycle") and cutter.get("data") == cutter_before,
		"operand cycle is refused without changing either solid")
	var missing = good_recipe.copy_recipe()
	missing.steps[2].operand_uuid = Step.new_uuid()
	result = engine.apply_candidate(target, missing, scene, undo)
	check(result.error != OK and target.get("data") == resized, "missing operand preserves cached result")

	# Manual UV edits are retained until the caller explicitly records a barrier.
	var faces: PackedInt64Array = target.call("get_faces")
	target.call("set_face_uv", PackedInt64Array([faces[0]]), Vector2(2, 3), Vector2(0.25, 0.5), 0.0)
	var manual: PackedByteArray = target.get("data")
	result = engine.edit_step(target, bevel.id, {"amount": 0.15}, scene, undo)
	check(result.error != OK and result.message.contains("checkpoint") and target.get("data") == manual,
		"manual UV data cannot be silently overwritten by parameter changes")
	result = engine.apply_candidate(target, Construction.checkpoint(target), scene, undo)
	check(result.error == OK and target.get("data") == manual, "explicit checkpoint records manual UV data without altering it")
	result = engine.edit_step(target, source_id, {"args": [Vector3(6, 4, 4)]}, scene, undo)
	check(result.error != OK and result.message.contains("rebasing") and target.get("data") == manual,
		"changing upstream geometry refuses an unrebased manual checkpoint")

	_check_boundaries(scene, engine, undo)
	_check_picked_edges(scene, engine, undo)
	_check_array_and_reload(scene, engine, undo)
	undo.clear_history()
	undo.free()
	scene.free()
	print("CONSTRUCTION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check_boundaries(scene: Node3D, engine: RefCounted, undo: UndoRedo) -> void:
	var solid := _solid(scene, "Fallback")
	var cutter := _solid(scene, "FallbackCutter", Vector3(2, 2, 2))
	cutter.position.x = 1.5
	solid.set("prototype_color", Color.RED)
	cutter.set("prototype_color", Color.BLUE)
	var recipe = Construction.from_primitive(solid, &"make_box", [Vector3(4, 4, 4)])
	var cut := _step(Step.Kind.BOOLEAN, {"mode": 1})
	cut.operand_uuid = Construction.ensure_uuid(cutter)
	recipe.steps.append(cut)
	var result: Dictionary = engine.apply_candidate(solid, recipe, scene, undo)
	check(result.error == OK and solid.get("materials").size() == 2
		and solid.get("materials")[0].albedo_color == Color.RED
		and solid.get("materials")[1].albedo_color == Color.BLUE,
		"Boolean retains both source and cutter prototype material fallbacks")
	var before: PackedByteArray = solid.get("data")
	var malformed = solid.get_meta(Construction.RECIPE_META).copy_recipe()
	malformed.steps[0].parameters.args = [Vector3(INF, 1, 1)]
	result = engine.apply_candidate(solid, malformed, scene, undo)
	check(result.error != OK and solid.get("data") == before, "nonfinite source parameters refuse before kernel evaluation")
	var duplicate := _solid(scene, "DuplicateIdentity")
	duplicate.set_meta(Construction.UUID_META, cut.operand_uuid)
	result = engine.apply_candidate(solid, recipe, scene, undo)
	check(result.error != OK and result.message.contains("Duplicate"), "duplicate operand identity cannot bind arbitrarily")
	duplicate.free()


func _check_picked_edges(scene: Node3D, engine: RefCounted, undo: UndoRedo) -> void:
	var solid := _solid(scene, "Picked")
	var recipe = Construction.from_primitive(solid, &"make_box", [Vector3(4, 4, 4)])
	var bevel := _step(Step.Kind.BEVEL, {"amount": 0.1, "segments": 1})
	bevel.selection_binding = Step.SelectionBinding.PINNED_EDGES
	bevel.picked_edges = PackedInt64Array([solid.call("get_edges")[0]])
	bevel.input_fingerprint = Step.fingerprint(solid.get("data"))
	recipe.steps.append(bevel)
	var result: Dictionary = engine.apply_candidate(solid, recipe, scene, undo)
	check(result.error == OK, "picked-edge recipe replays against its original input")
	var before: PackedByteArray = solid.get("data")
	result = engine.edit_step(solid, recipe.steps[0].id, {"args": [Vector3(5, 4, 4)]}, scene, undo)
	check(result.error != OK and result.message.contains("rebinding") and solid.get("data") == before,
		"picked IDs cannot silently retarget after upstream regeneration")

func _check_array_and_reload(scene: Node3D, engine: RefCounted, undo: UndoRedo) -> void:
	var solid := _solid(scene, "Array")
	var recipe = Construction.from_primitive(solid, &"make_box", [Vector3(2, 2, 2)])
	var array := _step(Step.Kind.ARRAY_LINEAR, {"count": 3, "step": Vector3(3, 0, 0)})
	recipe.steps.append(array)
	var result: Dictionary = engine.apply_candidate(solid, recipe, scene, undo)
	check(result.error == OK and solid.get_child_count() == 2, "array produces separate editable solid outputs, not flattened copies")
	var first: Node3D = solid.get_child(0)
	var first_id := str(first.get_meta(Construction.OUTPUT_META))
	check(first.position == Vector3(3, 0, 0), "array spacing is in recipe-local coordinates")
	result = engine.edit_step(solid, array.id, {"count": 4}, scene, undo)
	check(result.error == OK and solid.get_child_count() == 3 and solid.get_child(0) == first,
		"array parameter edits preserve existing generated node identity")
	undo.undo()
	check(solid.get_child_count() == 2 and solid.get_child(0) == first, "array count Undo restores outputs and identity")
	undo.redo()
	check(solid.get_child_count() == 3 and solid.get_child(0).get_meta(Construction.OUTPUT_META) == first_id,
		"array count Redo retains stable output identifiers")
	var reordered = solid.get_meta(Construction.RECIPE_META).copy_recipe()
	var bevel := _step(Step.Kind.BEVEL, {"amount": 0.1, "segments": 1})
	reordered.steps.append(bevel)
	result = engine.apply_candidate(solid, reordered, scene, undo)
	check(result.error == OK and first.call("face_count") > 6, "modifiers after Array evaluate each generated solid")
	result = engine.reorder_step(solid, bevel.id, 1, scene, undo)
	check(result.error == OK and solid.get_meta(Construction.RECIPE_META).steps[1].id == bevel.id,
		"valid modifier reorder retains parameters and generated objects")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "construction scene packs with recipe resources")
	var path := "user://construction_smoke.tscn"
	check(ResourceSaver.save(packed, path) == OK, "construction recipe saves")
	var saved: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var reopened := saved.instantiate()
	root.add_child(reopened)
	var restored: Node3D = reopened.get_node("Array")
	var persisted = restored.get_meta(Construction.RECIPE_META)
	check(persisted.steps.size() == 3 and persisted.steps[1].id == bevel.id
		and restored.get("data") == solid.get("data") and restored.get_child_count() == 3,
		"reopen preserves editable recipe, last-good mesh and generated outputs")
	result = engine.edit_step(restored, array.id, {"count": 2}, reopened)
	check(result.error == OK and restored.get_child_count() == 1 and restored.get_child(0).get_meta(Construction.OUTPUT_META) == first_id,
		"saved array parameters remain editable after reopen")
	restored.get_child(0).position += Vector3.UP
	var before: PackedByteArray = restored.get("data")
	result = engine.edit_step(restored, array.id, {"count": 3}, reopened)
	check(result.error != OK and result.message.contains("edited") and restored.get("data") == before,
		"manual generated-object edits are not overwritten by a rebuild")
	reopened.free()
	DirAccess.remove_absolute(path)
