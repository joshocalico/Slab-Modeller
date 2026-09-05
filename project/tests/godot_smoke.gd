extends SceneTree

var _fails := 0

func _init() -> void:
	_expect(ClassDB.class_exists("SlabSolid"), "SlabSolid registered")
	_expect(ClassDB.class_exists("SlabSocket"), "SlabSocket registered")
	_expect(ClassDB.class_exists("SlabModule"), "SlabModule registered")
	_expect(not ClassDB.class_exists("SlabBlock"), "SlabBlock is gone")

	if not ClassDB.class_exists("SlabSolid"):
		_finish()
		return

	var module: Node3D = ClassDB.instantiate("SlabModule")
	root.add_child(module)
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	module.add_child(solid)
	_expect(solid.call("make_box", Vector3(2, 3, 2)) == 0, "make_box succeeds")
	_expect(solid.call("face_count") == 6, "box has 6 faces")
	_expect(absf(float(solid.call("volume")) - 12.0) < 0.01, "box volume is 12")
	var aabb: AABB = solid.call("get_local_aabb")
	_expect(aabb.size.is_equal_approx(Vector3(2, 3, 2)), "aabb matches box size")
	var mesh: ArrayMesh = solid.call("build_mesh")
	_expect(mesh != null, "build_mesh returns ArrayMesh")
	if mesh != null:
		_expect(mesh.get_surface_count() == 1, "one surface")
		_expect(mesh.surface_get_array_len(0) == 24, "six quads emit 24 verts")
	var baked: ArrayMesh = module.call("bake_mesh")
	_expect(baked != null and baked.get_surface_count() == 1, "module bake includes the solid")
	print("godot_smoke faces=", solid.call("face_count"), " volume=", solid.call("volume"))
	_finish()


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
		print("godot_smoke ok")
		quit(0)
