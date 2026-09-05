extends RefCounted

const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")

const EYE := Vector3(6, 8, 10)
const LOOK_AT := Vector3(1, 1.5, 1)

var _stage: Node3D
var _camera: Camera3D
var _metrics: RefCounted
var _box: Node3D
var _other: Node3D
var _far: Node3D


static func staged(tree: SceneTree, scale := 1.0):
	var world := new()
	world._stage = Node3D.new()
	tree.root.add_child(world._stage)
	world._camera = Camera3D.new()
	world._stage.add_child(world._camera)
	world._camera.look_at_from_position(EYE, LOOK_AT, Vector3.UP)
	world._camera.current = true
	world._metrics = SlabMetrics.at_scale(scale)
	world._box = world.add_solid("Box", Vector3(2, 3, 2), Vector3.ZERO)
	world._other = world.add_solid("Other", Vector3(2, 3, 2), Vector3(-6, 0, 0))
	world._far = world.add_solid("Far", Vector3(2, 2, 2), Vector3(0, 0, -6))
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
		if child == _camera:
			continue
		child.free()


func tear_down() -> void:
	if is_instance_valid(_stage):
		_stage.free()
	_stage = null
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
