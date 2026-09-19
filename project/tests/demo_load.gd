extends SceneTree

var _fails := 0
var _frames := 0
var _demo: Node


func _initialize() -> void:
	var packed: PackedScene = load("res://demo/demo.tscn")
	if packed == null:
		push_error("demo.tscn missing")
		quit(1)
		return
	_demo = packed.instantiate()
	root.add_child(_demo)


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var box: Node = _demo.get_node_or_null("SlabModule/Box")
	var solid: Node = _demo.get_node_or_null("SlabModule/Solid")
	var hall: Node = _demo.get_node_or_null("SlabModule/Hall")
	if box == null or not box.is_class("SlabSolid"):
		push_error("demo Box is not a SlabSolid")
		quit(1)
		return true
	if solid == null or not solid.is_class("SlabSolid"):
		push_error("demo Solid is not a SlabSolid")
		quit(1)
		return true
	var box_blob: PackedByteArray = box.get("data")
	var solid_blob: PackedByteArray = solid.get("data")
	_expect(box_blob.size() >= 800, "demo Box stores topology in data, bytes=%s" % box_blob.size())
	_expect(solid_blob.size() >= 800, "demo Solid stores topology in data, bytes=%s" % solid_blob.size())
	_expect(int(box.call("face_count")) == 6, "demo Box reloads 6 faces from data")
	_expect(int(solid.call("face_count")) == 6, "demo Solid reloads 6 faces from data")
	_expect(absf(float(box.call("volume")) - 8.0) < 0.01, "demo Box volume is the saved 2x2x2")
	_expect(box.get("collision_enabled") == true, "demo Box has collision_enabled")
	var box_collider: CollisionShape3D = box.get_node_or_null("__body/__shape")
	_expect(box_collider != null and box_collider.shape is ConcavePolygonShape3D,
		"demo Box has runtime collision shape")
	_expect(solid.get("collision_enabled") == true, "demo Solid has collision_enabled")
	var solid_collider: CollisionShape3D = solid.get_node_or_null("__body/__shape")
	_expect(solid_collider != null and solid_collider.shape is ConcavePolygonShape3D,
		"demo Solid has runtime collision shape")
	print("box=", box, " faces=", box.call("face_count"), " volume=", box.call("volume"))
	print("solid=", solid, " faces=", solid.call("face_count"))
	print("hall=", hall, " points=", hall.get("points") if hall else null)
	if hall:
		var mesh_i: Node = hall.get_node_or_null("Mesh")
		if mesh_i == null:
			mesh_i = hall.get_node_or_null("__mesh")
		print("hall_mesh=", mesh_i, " mesh=", mesh_i.mesh if mesh_i else null)
		if mesh_i and mesh_i.mesh:
			print("hall_verts=", mesh_i.mesh.surface_get_array_len(0))
	if _fails != 0:
		push_error(str(_fails) + " failures")
		quit(1)
	else:
		print("demo_load ok")
		quit(0)
	return true


func _expect(ok: bool, what: String) -> void:
	if not ok:
		push_error("FAIL " + what)
		_fails += 1
	else:
		print("ok ", what)
