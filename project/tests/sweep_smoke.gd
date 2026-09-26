extends SceneTree

var _fails := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sweep_script: Script = load("res://addons/slab/slab_sweep.gd")
	_expect(sweep_script != null, "sweep script loads")
	if sweep_script == null:
		_finish()
		return
	var sweep: Node3D = sweep_script.new()
	root.add_child(sweep)
	sweep.set("profile", Vector2(0.5, 1.0))
	var path := PackedVector3Array([Vector3.ZERO, Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4)])
	sweep.set("points", path)
	_expect(sweep.get("last_error") == 0, "open sweep validates through native kernel")
	var mesh_i: MeshInstance3D = sweep.get_node_or_null("Mesh")
	_expect(mesh_i != null and mesh_i.mesh != null, "open sweep generates visible mesh")
	sweep.set("closed", true)
	_expect(sweep.get("last_error") == 0, "closed toggle generates valid solid")
	var closed_mesh: ArrayMesh = mesh_i.mesh
	_expect(_triangle_count(closed_mesh) == 32, "closed mesh has cyclic sides without caps")
	var shape: CollisionShape3D = sweep.get_node_or_null("__body/Shape")
	_expect(shape != null and shape.shape is ConcavePolygonShape3D, "closed node has matching collision")
	if shape and shape.shape is ConcavePolygonShape3D:
		_expect(shape.shape.get_faces().size() == 96, "collision has all32 closed side triangles")
	var packed := PackedScene.new()
	_expect(packed.pack(sweep) == OK, "sweep packs in memory")
	var reloaded: Node3D = packed.instantiate()
	root.add_child(reloaded)
	_expect(reloaded.get("closed") == true and reloaded.get("points") == path, "reload preserves closed setting and points")
	_expect(reloaded.get("last_error") == 0, "reload rebuilds valid closed geometry")
	reloaded.free()
	var invalid := PackedVector3Array([Vector3.ZERO, Vector3.ONE])
	sweep.set("points", invalid)
	_expect(sweep.get("last_error") != 0, "two-point closed path is refused")
	_expect(mesh_i.mesh == closed_mesh, "invalid edit retains last valid mesh")
	_expect(not sweep.call("_get_configuration_warnings").is_empty(), "invalid path explains how to recover")
	sweep.set("points", path)
	_expect(sweep.get("last_error") == 0, "valid path recovers after invalid edit")
	sweep.set("closed", false)
	_expect(_triangle_count(mesh_i.mesh) == 28, "opening loop removes final sides and restores caps")
	var vertical := PackedVector3Array([Vector3.ZERO, Vector3(0, 4, 0), Vector3(3, 6, 1)])
	sweep.set("points", vertical)
	_expect(sweep.get("last_error") == 0, "vertical path transports frame without flattening Y")
	_expect(mesh_i.mesh.get_aabb().end.y > 6, "vertical sweep retains height changes")
	sweep.free()

	var shapes: RefCounted = load("res://addons/slab/slab_shapes.gd").new()
	shapes.call("set_value", &"sweep_closed", 1.0)
	var plan: Dictionary = shapes.call("plan", &"make_sweep")
	_expect(plan.args[2] == true, "Create plan forwards closed flag")
	var solid: Node = ClassDB.instantiate("SlabSolid")
	_expect(solid.callv(plan.method, plan.args) == 0, "closed Create defaults form valid solid")
	_expect(solid.call("vertex_count") - solid.call("edge_count") + solid.call("face_count") == 0, "Create result has torus topology")
	var bytes: PackedByteArray = solid.get("data")
	var too_short := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])
	_expect(solid.call("make_sweep", too_short, Vector2.ONE, true) != 0, "binding refuses invalid closed path")
	_expect(solid.get("data") == bytes, "binding rejection preserves editable bytes")
	solid.free()
	_finish()


func _triangle_count(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var count := 0
	for surface in mesh.get_surface_count():
		var indices := mesh.surface_get_array_index_len(surface)
		count += int((indices if indices > 0 else mesh.surface_get_array_len(surface)) / 3)
	return count


func _expect(ok: bool, what: String) -> void:
	if not ok:
		push_error("FAIL " + what)
		_fails += 1
	else:
		print("ok ", what)


func _finish() -> void:
	if _fails != 0:
		push_error(str(_fails) + " failures")
		quit(1)
	else:
		print("sweep_smoke ok")
		quit(0)
