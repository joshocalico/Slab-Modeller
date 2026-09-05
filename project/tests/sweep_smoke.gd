extends SceneTree

var _fails := 0

func _init() -> void:
	var sweep_script: Script = load("res://addons/slab/slab_sweep.gd")
	_expect(sweep_script != null, "slab_sweep.gd loads")
	if sweep_script == null:
		_finish()
		return
	var sweep: Node3D = sweep_script.new()
	root.add_child(sweep)
	var pts := PackedVector3Array([Vector3.ZERO, Vector3(4, 0, 0), Vector3(4, 0, 3)])
	sweep.set("profile", Vector2(1.0, 2.0))
	sweep.set("points", pts)
	var mesh_i: MeshInstance3D = sweep.get_node_or_null("Mesh")
	if mesh_i == null:
		mesh_i = sweep.get_node_or_null("__mesh")
	_expect(mesh_i != null, "sweep owns __mesh")
	var mesh: ArrayMesh = mesh_i.mesh if mesh_i else null
	_expect(mesh != null, "two-plus points build a mesh")
	if mesh != null:
		_expect(mesh.get_surface_count() == 1, "one surface")
		_expect(mesh.surface_get_array_len(0) >= 24, "caps and sides have verts")
	print("sweep_smoke verts=", mesh.surface_get_array_len(0) if mesh else -1)
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
		print("sweep_smoke ok")
		quit(0)
