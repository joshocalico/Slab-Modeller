extends SceneTree

const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")

var _fails := 0
var _solid: Node3D
var _other: Node3D
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
	_other = ClassDB.instantiate("SlabSolid")
	world.add_child(_other)
	_other.position = Vector3(-6, 0, 0)
	_other.call("make_box", Vector3(2, 3, 2))


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
	var vertex_xray := SlabPick.candidates(_solid, SlabSelection.Mode.VERTEX, _camera, vert_screen, 24.0, false)
	var visible_vertices := SlabPick.candidates(_solid, SlabSelection.Mode.VERTEX, _camera, vert_screen, 24.0, true)
	_expect(not visible_vertices.is_empty() and vert_picked == int(visible_vertices[0]["id"]), "legacy vertex pick chooses the first visible candidate")
	_expect(_candidate_has(vertex_xray, first_vert), "X-ray vertex candidates retain the occluded requested corner")
	_expect(_same_ids(vertex_xray, SlabPick.candidates(_solid, SlabSelection.Mode.VERTEX, _camera, vert_screen, 24.0, false)),
		"overlapping vertex order is deterministic")

	var miss: int = SlabPick.pick(_solid, SlabSelection.Mode.FACE, _camera, Vector2(20000, 20000))
	_expect(miss == 0, "a click off the mesh selects nothing")

	var edges: PackedInt64Array = _solid.call("get_edges")
	_expect(edges.size() == 12, "box has 12 edges")
	var first_edge: int = edges[0]
	var ends: PackedVector3Array = _solid.call("edge_endpoints", first_edge)
	var mid: Vector3 = (ends[0] + ends[1]) * 0.5
	var edge_screen: Vector2 = _camera.unproject_position(_solid.to_global(mid))
	var edge_picked: int = SlabPick.pick(_solid, SlabSelection.Mode.EDGE, _camera, edge_screen)
	var edge_xray := SlabPick.candidates(_solid, SlabSelection.Mode.EDGE, _camera, edge_screen, 24.0, false)
	var visible_edges := SlabPick.candidates(_solid, SlabSelection.Mode.EDGE, _camera, edge_screen, 24.0, true)
	_expect(not visible_edges.is_empty() and edge_picked == int(visible_edges[0]["id"]), "legacy edge pick chooses the first visible candidate")
	_expect(_candidate_has(edge_xray, first_edge), "X-ray edge candidates retain the occluded requested edge")

	var along: Vector3 = ends[0].lerp(ends[1], 0.3)
	var along_screen: Vector2 = _camera.unproject_position(_solid.to_global(along))
	var along_picked: int = SlabPick.pick(_solid, SlabSelection.Mode.EDGE, _camera, along_screen)
	_expect(along_picked != 0, "generous tolerance picks along an edge, not only at its midpoint")

	var perspective_a := _camera.to_global(Vector3(-1.0, 0.0, -2.0))
	var perspective_b := _camera.to_global(Vector3(2.0, 0.0, -10.0))
	var perspective_t := 0.35
	var projected_screen := _camera.unproject_position(perspective_a).lerp(
		_camera.unproject_position(perspective_b), perspective_t)
	var projected_world := SlabPick.projected_edge_world(_camera, perspective_a, perspective_b, perspective_t)
	var linear_world := perspective_a.lerp(perspective_b, perspective_t)
	_expect(_camera.unproject_position(projected_world).distance_to(projected_screen) < 0.001,
		"perspective edge point lies on the cursor ray used for visibility")
	_expect(_camera.unproject_position(linear_world).distance_to(projected_screen) > 1.0,
		"perspective fixture distinguishes projected interpolation from world-linear interpolation")
	var crossing := SlabPick.clip_edge_to_camera(_camera,
		_camera.to_global(Vector3(-1.0, 0.0, 1.0)), perspective_b)
	_expect(crossing.size() == 2 and not _camera.is_position_behind(crossing[0])
		and not _camera.is_position_behind(crossing[1]),
		"an edge crossing the camera plane is clipped before perspective interpolation")
	var crossing_world := SlabPick.projected_edge_world(_camera, crossing[0], crossing[1], 0.5)
	_expect(crossing_world.is_finite() and _camera.unproject_position(crossing_world).is_finite(),
		"a clipped perspective edge produces finite visibility coordinates")
	var ortho := Camera3D.new()
	_solid.get_parent().add_child(ortho)
	ortho.projection = Camera3D.PROJECTION_ORTHOGONAL
	ortho.global_transform = _camera.global_transform
	_expect(SlabPick.projected_edge_world(ortho, perspective_a, perspective_b, perspective_t).is_equal_approx(linear_world),
		"orthographic edge interpolation remains world-linear")
	ortho.free()

	var other_top: int = _top_face(_other)
	var other_screen: Vector2 = _camera.unproject_position(_other.to_global(_other.call("face_centroid", other_top)))
	var picked_other: Node3D = SlabPick.pick_solid(_solid.get_parent(), _camera, other_screen)
	_expect(picked_other == _other, "viewport pick hits a solid that was never selected")
	_other.visible = false
	_expect(SlabPick.pick_solid(_solid.get_parent(), _camera, other_screen) != _other
		and not SlabPick.all_solids(_solid.get_parent()).has(_other),
		"a hidden solid is absent from viewport picking and occlusion")
	_other.visible = true
	var hidden_parent := Node3D.new()
	_solid.get_parent().add_child(hidden_parent)
	var hidden_child: Node3D = ClassDB.instantiate("SlabSolid")
	hidden_parent.add_child(hidden_child)
	hidden_child.position = Vector3(-10, 0, 0)
	hidden_parent.visible = false
	_expect(not SlabPick.all_solids(_solid.get_parent()).has(hidden_child),
		"a solid beneath a hidden ancestor is absent from viewport picking")
	hidden_parent.free()
	var origin_screen: Vector2 = _camera.unproject_position(_solid.to_global(_solid.call("face_centroid", top)))
	var picked_origin: Node3D = SlabPick.pick_solid(_solid.get_parent(), _camera, origin_screen)
	_expect(picked_origin == _solid, "viewport pick hits the nearer box without a hierarchy selection")
	_expect(SlabPick.pick_solid(_solid.get_parent(), _camera, Vector2(20000, 20000)) == null, "a click off every solid picks none")

	var depth_camera := Camera3D.new()
	_solid.get_parent().add_child(depth_camera)
	depth_camera.look_at_from_position(Vector3(12, 0, 10), Vector3(12, 0, 0), Vector3.UP)
	var front: Node3D = ClassDB.instantiate("SlabSolid")
	var rear: Node3D = ClassDB.instantiate("SlabSolid")
	_solid.get_parent().add_child(front)
	_solid.get_parent().add_child(rear)
	front.position = Vector3(12, 0, 2)
	rear.position = Vector3(12, 0, -2)
	front.call("make_box", Vector3(2, 2, 2))
	rear.call("make_box", Vector3(2, 2, 2))
	var depth_screen := depth_camera.unproject_position(Vector3(12, 0, 2))
	var visible_faces := SlabPick.scene_candidates(_solid.get_parent(), SlabSelection.Mode.FACE, depth_camera, depth_screen, 24.0, true)
	var xray_faces := SlabPick.scene_candidates(_solid.get_parent(), SlabSelection.Mode.FACE, depth_camera, depth_screen, 24.0, false)
	_expect(not visible_faces.is_empty() and visible_faces[0]["solid"] == front, "visible-only scene candidates stop at the front surface")
	_expect(_candidate_has_solid(xray_faces, rear), "X-ray scene candidates include a solid behind the front surface")
	_expect(_same_scene_candidates(xray_faces, SlabPick.scene_candidates(_solid.get_parent(), SlabSelection.Mode.FACE, depth_camera, depth_screen, 24.0, false)),
		"cross-solid overlap order is deterministic")
	front.free()
	rear.free()
	depth_camera.free()

	var selection := SlabSelection.new()
	selection.set_objects([_solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.toggle_id(top, false)
	_expect(selection.ids.size() == 1 and selection.ids[0] == top, "first click replaces the selection")
	selection.set_hover(_solid, top)
	_expect(selection.hover_solid == _solid and selection.hover_id == top, "hover tracks the preselected face")
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

	var hover_sel := SlabSelection.new()
	hover_sel.set_objects([_solid])
	hover_sel.mode = SlabSelection.Mode.FACE
	hover_sel.set_hover(_solid, top)
	hover_sel.mode = SlabSelection.Mode.EDGE
	_expect(hover_sel.hover_id == 0, "changing mode clears hover")

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


func _candidate_has(items: Array[Dictionary], wanted: int) -> bool:
	for item in items:
		if int(item.get("id", 0)) == wanted:
			return true
	return false


func _candidate_has_solid(items: Array[Dictionary], wanted: Node3D) -> bool:
	for item in items:
		if item.get("solid") == wanted:
			return true
	return false


func _same_ids(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].get("id") != b[i].get("id"):
			return false
	return true


func _same_scene_candidates(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if not _same_ids(a, b):
		return false
	for i in a.size():
		if a[i].get("solid") != b[i].get("solid"):
			return false
	return true


func _expect(ok: bool, what: String) -> void:
	if not ok:
		push_error("FAIL " + what)
		_fails += 1
	else:
		print("ok ", what)
