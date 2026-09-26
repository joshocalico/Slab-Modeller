extends SceneTree

const Actions := preload("res://addons/slab/slab_actions.gd")
const Selection := preload("res://addons/slab/slab_selection.gd")
const History := preload("res://tests/slab_test_undo.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func _solid(parent: Node, label: String) -> Node3D:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.name = label
	parent.add_child(solid)
	solid.owner = parent
	solid.call("make_box", Vector3(2, 2, 2))
	return solid

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material

func _regions(solid: Node3D, left: Color, right: Color) -> bool:
	var bindings: Array = solid.call("get_mesh_materials")
	var mesh: ArrayMesh = solid.call("build_mesh")
	var found_left := false
	var found_right := false
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material: StandardMaterial3D = bindings[surface]
		if material == null: return false
		for i in range(0, indices.size(), 3):
			var center_x := (vertices[indices[i]].x + vertices[indices[i+1]].x + vertices[indices[i+2]].x) / 3.0
			if center_x > 2.0001:
				found_right = true
				if not material.albedo_color.is_equal_approx(right): return false
			else:
				found_left = true
				if not material.albedo_color.is_equal_approx(left): return false
	return found_left and found_right

func _run() -> void:
	var scene := Node3D.new()
	scene.name = "BooleanMaterials"
	root.add_child(scene)
	var host := _solid(scene, "Host")
	var cutter := _solid(scene, "Cutter")
	cutter.position.x = 1
	var red := _material(Color.RED)
	var blue := _material(Color.BLUE)
	host.set("materials", [red])
	cutter.set("materials", [blue])
	var before: PackedByteArray = host.get("data")
	var cutter_before: PackedByteArray = cutter.get("data")
	var selection := Selection.new()
	selection.set_objects([host, cutter])
	var history := History.new()
	var actions := Actions.new(selection, history)
	actions.run("boolean_union")
	check(history.actions.size() == 1, "native Boolean command produces one Undo action")
	check(_regions(host, Color.RED, Color.BLUE), "actual emitted surfaces retain red host and blue cutter")
	var materials: Array = host.get("materials")
	check(materials.has(red) and materials.has(blue), "Boolean keeps original material Resource identities")
	check(cutter.get("data") == cutter_before and cutter.get("materials") == [blue], "Boolean leaves operand geometry and bindings unchanged")
	var after: PackedByteArray = host.get("data")
	history.undo()
	check(host.get("data") == before and host.get("materials") == [red], "Undo restores geometry and material table together")
	history.redo()
	check(host.get("data") == after and host.get("materials") == materials and _regions(host, Color.RED, Color.BLUE), "Redo restores both resource bindings and rendered colours")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "material Boolean scene packs")
	var path := "user://boolean_materials_smoke.tscn"
	check(ResourceSaver.save(packed, path) == OK, "material Boolean scene saves")
	var loaded: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var restored: Node3D = loaded.instantiate()
	root.add_child(restored)
	check(_regions(restored.get_node("Host"), Color.RED, Color.BLUE), "reloaded scene keeps both operand material appearances")
	restored.free()
	DirAccess.remove_absolute(path)
	var before_reject: PackedByteArray = host.get("data")
	check(host.call("boolean_with", cutter, 99) != OK, "invalid Boolean mode refuses")
	check(host.get("data") == before_reject and host.get("materials") == materials, "refused Boolean leaves material table and geometry untouched")
	scene.free()
	_check_fallbacks()
	_check_shared_resource()
	print("BOOLEAN_MATERIALS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check_fallbacks() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var host := _solid(scene, "Host")
	var cutter := _solid(scene, "Cutter")
	cutter.position.x = 1
	host.set("prototype_color", Color.GREEN)
	cutter.set("prototype_color", Color.BLUE)
	# Slot 1 is unresolved on the host. Appending cutter materials must not
	# accidentally bind that existing host geometry to the cutter colour.
	host.call("set_face_material", host.call("get_faces"), 1)
	check(host.call("boolean_with", cutter, 0) == OK, "Boolean supports different prototype fallback colours")
	check(_regions(host, Color.GREEN, Color.BLUE), "out-of-range host fallback stays green while cutter stays blue")
	cutter.set("prototype_color", Color.YELLOW)
	check(_regions(host, Color.GREEN, Color.BLUE), "later operand prototype recolouring leaves Boolean result unchanged")
	scene.free()

func _check_shared_resource() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var host := _solid(scene, "Host")
	var cutter := _solid(scene, "Cutter")
	cutter.position.x = 1
	var shared := _material(Color.PURPLE)
	host.set("materials", [shared])
	cutter.set("materials", [shared])
	check(host.call("boolean_with", cutter, 0) == OK, "Boolean accepts shared material resource")
	check(host.get("materials") == [shared], "shared resources deduplicate without copies")
	scene.free()
