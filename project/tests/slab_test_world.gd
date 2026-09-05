extends RefCounted

const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")

const EYE := Vector3(6, 8, 10)
const LOOK_AT := Vector3(1, 1.5, 1)
const VIEW := Vector2i(1280, 720)

var _stage: Node3D
var _view: SubViewport
var _camera: Camera3D
var _metrics: RefCounted
var _box: Node3D
var _other: Node3D
var _far: Node3D
var _pristine: Dictionary = {}
var _rest: Dictionary = {}


static func staged(tree: SceneTree, scale := 1.0):
	var world := new()
	world._stage = Node3D.new()
	tree.root.add_child(world._stage)
	world._view = SubViewport.new()
	world._view.size = VIEW
	world._view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world._stage.add_child(world._view)
	world._camera = Camera3D.new()
	world._view.add_child(world._camera)
	world._camera.look_at_from_position(EYE, LOOK_AT, Vector3.UP)
	world._camera.current = true
	world._metrics = SlabMetrics.at_scale(scale)
	world._box = world.add_solid("Box", Vector3(2, 3, 2), Vector3.ZERO)
	world._other = world.add_solid("Other", Vector3(2, 3, 2), Vector3(-6, 0, 0))
	world._far = world.add_solid("Far", Vector3(2, 2, 2), Vector3(0, 0, -6))
	world._remember(world._box)
	world._remember(world._other)
	world._remember(world._far)
	return world


func box() -> Node3D:
	return _box


func other() -> Node3D:
	return _other


func far() -> Node3D:
	return _far


func camera() -> Camera3D:
	return _camera


func stage() -> Node3D:
	return _stage


func metrics() -> RefCounted:
	return _metrics


func add_solid(node_name: String, size: Vector3, at: Vector3) -> Node3D:
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	solid.name = node_name
	_stage.add_child(solid)
	solid.position = at
	solid.call("make_box", size)
	return solid


func clear_solids() -> void:
	for child in _stage.get_children():
		if child == _view:
			continue
		child.free()


func tear_down() -> void:
	if is_instance_valid(_stage):
		_stage.free()
	_stage = null
	_view = null
	_camera = null


func top_face(solid: Node3D) -> int:
	var best: int = 0
	var up := -2.0
	for id in PackedInt64Array(solid.call("get_faces")):
		var n: Vector3 = solid.call("face_normal", id)
		if n.y > up:
			up = n.y
			best = id
	return best


func at_face(solid: Node3D, id: int) -> Vector2:
	return _camera.unproject_position(solid.to_global(solid.call("face_centroid", id)))


func at_vertex(solid: Node3D, id: int) -> Vector2:
	return _camera.unproject_position(solid.to_global(solid.call("vertex_position", id)))


func along_edge(solid: Node3D, id: int, t: float) -> Vector2:
	var ends: PackedVector3Array = solid.call("edge_endpoints", id)
	var point: Vector3 = ends[0].lerp(ends[1], t)
	return _camera.unproject_position(solid.to_global(point))


func along_edge_on_face(solid: Node3D, edge: int, t: float, face: int) -> Vector2:
	return along_edge(solid, edge, t).lerp(at_face(solid, face), 0.2)


func at_origin(solid: Node3D) -> Vector2:
	return _camera.unproject_position(solid.global_position)


func past_pick_radius(solid: Node3D) -> Vector2:
	var right := -INF
	var y := 0.0
	for id in PackedInt64Array(solid.call("get_vertices")):
		var p: Vector2 = _camera.unproject_position(vertex_world(solid, id))
		if p.x > right:
			right = p.x
			y = p.y
	return Vector2(right + _metrics.pick_radius() * 4.0, y)


func click(screen: Vector2, shift := false, meta := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.shift_pressed = shift
	event.meta_pressed = meta
	return event


func motion(screen: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = screen
	event.global_position = screen
	return event


func key(keycode: int, ctrl := false, alt := false, meta := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.echo = false
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.meta_pressed = meta
	return event


func release(screen: Vector2, shift := false, meta := false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.shift_pressed = shift
	event.meta_pressed = meta
	return event


func drag_to(screen: Vector2, shift := false) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = screen
	event.global_position = screen
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.shift_pressed = shift
	return event


func double_click(screen: Vector2, shift := false) -> InputEventMouseButton:
	var event := click(screen, shift)
	event.double_click = true
	return event


func forward() -> Vector3:
	return -_camera.global_transform.basis.z


func toward(anchor: Vector3, dir: Vector3, px: float) -> Vector2:
	var a: Vector2 = _camera.unproject_position(anchor)
	var b: Vector2 = _camera.unproject_position(anchor + dir.normalized())
	var along: Vector2 = b - a
	if along.length_squared() < 0.0001:
		return a + Vector2(px, 0.0)
	return a + along.normalized() * px


func vertex_world(solid: Node3D, id: int) -> Vector3:
	var local: Vector3 = solid.call("vertex_position", id)
	if solid.is_inside_tree():
		return solid.to_global(local)
	return solid.transform * local


func positions(solid: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for id in PackedInt64Array(solid.call("get_vertices")):
		out[id] = vertex_world(solid, id)
	return out


func moved_vertices(solid: Node3D) -> PackedInt64Array:
	var rest: Dictionary = _rest.get(solid, {})
	var out := PackedInt64Array()
	for id in PackedInt64Array(solid.call("get_vertices")):
		if not rest.has(id):
			continue
		if not vertex_world(solid, id).is_equal_approx(rest[id]):
			out.append(id)
	return out


func unchanged(solid: Node3D, ids: PackedInt64Array) -> bool:
	var moved: PackedInt64Array = moved_vertices(solid)
	for id in ids:
		if moved.has(id):
			return false
	return true


func top_vertex(solid: Node3D) -> int:
	var verts: PackedInt64Array = solid.call("face_vertices", top_face(solid))
	return verts[0]


func ringed_box() -> Dictionary:
	var solid: Node3D = add_solid("Ringed", Vector3(2, 3, 2), Vector3(8, 0, 0))
	var vertical: int = 0
	for edge in PackedInt64Array(solid.call("get_edges")):
		var ends: PackedVector3Array = solid.call("edge_endpoints", edge)
		if absf(ends[0].x - ends[1].x) < 0.01 and absf(ends[0].z - ends[1].z) < 0.01:
			vertical = edge
			break
	solid.call("insert_loop", vertical, 0.5)
	var ring: int = 0
	var mid_y: float = 1.5
	for edge in PackedInt64Array(solid.call("get_edges")):
		var ends: PackedVector3Array = solid.call("edge_endpoints", edge)
		if absf(ends[0].y - mid_y) < 0.05 and absf(ends[1].y - mid_y) < 0.05:
			ring = edge
			break
	return { "solid": solid, "ring_edge": ring }


func _remember(solid: Node3D) -> void:
	_pristine[solid] = solid.get("data")
	_rest[solid] = positions(solid)


func reset() -> void:
	for child in _stage.get_children():
		if child == _view:
			continue
		if child == _box or child == _other or child == _far:
			continue
		child.free()
	_box.set("data", _pristine[_box])
	_other.set("data", _pristine[_other])
	_far.set("data", _pristine[_far])
	_rest[_box] = positions(_box)
	_rest[_other] = positions(_other)
	_rest[_far] = positions(_far)
