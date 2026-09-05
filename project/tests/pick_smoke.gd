extends SceneTree

const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")

var _fails := 0
var _solid: Node3D
var _camera: Camera3D
var _frames := 0


func _initialize() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		push_error("SlabSolid missing")
		quit(1)
		return
	var world := Node3D.new()
	root.add_child(world)
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.look_at_from_position(Vector3(6, 8, 10), Vector3(1, 1.5, 1), Vector3.UP)
	_camera.current = true
	_solid = ClassDB.instantiate("SlabSolid")
	world.add_child(_solid)
	_solid.call("make_box", Vector3(2, 3, 2))


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_run()
	return true


func _run() -> void:
	var top: int = _top_face(_solid)
	_expect(top != 0, "found a top face")
	var screen: Vector2 = _camera.unproject_position(_solid.to_global(_solid.call("face_centroid", top)))
	var picked: int = SlabPick.pick(_solid, SlabSelection.Mode.FACE, _camera, screen)
	_expect(picked == top, "click on the top centroid selects that face, got %d want %d" % [picked, top])

	var verts: PackedInt64Array = _solid.call("get_vertices")
	_expect(verts.size() == 8, "box has 8 vertices")
	var first_vert: int = verts[0]
	var vert_screen: Vector2 = _camera.unproject_position(_solid.to_global(_solid.call("vertex_position", first_vert)))
	var vert_picked: int = SlabPick.pick(_solid, SlabSelection.Mode.VERTEX, _camera, vert_screen)
	_expect(vert_picked == first_vert, "click on a vertex selects it, got %d want %d" % [vert_picked, first_vert])

	var miss: int = SlabPick.pick(_solid, SlabSelection.Mode.FACE, _camera, Vector2(20000, 20000))
	_expect(miss == 0, "a click off the mesh selects nothing")

	var edges: PackedInt64Array = _solid.call("get_edges")
	_expect(edges.size() == 12, "box has 12 edges")
	var first_edge: int = edges[0]
	var ends: PackedVector3Array = _solid.call("edge_endpoints", first_edge)
	var mid: Vector3 = (ends[0] + ends[1]) * 0.5
	var edge_screen: Vector2 = _camera.unproject_position(_solid.to_global(mid))
	var edge_picked: int = SlabPick.pick(_solid, SlabSelection.Mode.EDGE, _camera, edge_screen)
	_expect(edge_picked == first_edge, "click on an edge midpoint selects it, got %d want %d" % [edge_picked, first_edge])

	var selection := SlabSelection.new()
	selection.set_objects([_solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.toggle_id(top, false)
	_expect(selection.ids.size() == 1 and selection.ids[0] == top, "first click replaces the selection")
	var second: int = 0
	for id in PackedInt64Array(_solid.call("get_faces")):
		if id != top:
			second = id
			break
	selection.toggle_id(second, true)
	_expect(selection.ids.size() == 2, "shift adds a second face")
	selection.toggle_id(top, true)
	_expect(selection.ids.size() == 1 and selection.ids[0] == second, "shift on the first face removes it")

	var mesh_child: Node = _solid.get_node_or_null("Mesh")
	_expect(mesh_child != null, "solid owns a Mesh child")
	var from_mesh := SlabSelection.new()
	from_mesh.set_objects([mesh_child])
	_expect(from_mesh.solid == _solid, "picking the Mesh child still selects the solid")

	if _fails != 0:
		push_error(str(_fails) + " failures")
		quit(1)
	else:
		print("pick_smoke ok")
		quit(0)


func _top_face(solid: Node3D) -> int:
	var best: int = 0
	var up := -2.0
	for id in PackedInt64Array(solid.call("get_faces")):
		var n: Vector3 = solid.call("face_normal", id)
		if n.y > up:
			up = n.y
			best = id
	return best


func _expect(ok: bool, what: String) -> void:
	if not ok:
		push_error("FAIL " + what)
		_fails += 1
	else:
		print("ok ", what)
