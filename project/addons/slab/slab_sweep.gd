@tool
class_name SlabSweep
extends Node3D

@export var profile := Vector2(1.0, 2.0):
	set(value):
		profile = Vector2(maxf(value.x, 0.05), maxf(value.y, 0.05))
		_rebuild()

@export var prototype_color := Color(0.72, 0.55, 0.38):
	set(value):
		prototype_color = value
		_rebuild()

@export var points: PackedVector3Array = PackedVector3Array():
	set(value):
		points = value
		_rebuild()

var _mesh_instance: MeshInstance3D


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_rebuild()


func _ensure_mesh() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	add_child(_mesh_instance)


func _rebuild() -> void:
	_ensure_mesh()
	if points.size() < 2:
		_mesh_instance.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var frames: Array = _frames()
	for i in range(frames.size() - 1):
		_side_ring(st, frames[i], frames[i + 1])
	_cap(st, frames[0], false)
	_cap(st, frames[frames.size() - 1], true)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = prototype_color
	mat.roughness = 0.7
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)
	_mesh_instance.mesh = mesh


func _frames() -> Array:
	var frames: Array = []
	for i in points.size():
		var tangent := Vector3.FORWARD
		if i + 1 < points.size():
			tangent = points[i + 1] - points[i]
		elif i > 0:
			tangent = points[i] - points[i - 1]
		tangent.y = 0.0
		if tangent.length() < 0.001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var right := tangent.cross(Vector3.UP)
		if right.length() < 0.001:
			right = Vector3.RIGHT
		right = right.normalized()
		frames.append({"origin": points[i], "right": right, "tangent": tangent})
	return frames


func _corner(frame: Dictionary, index: int) -> Vector3:
	var half_w: float = profile.x * 0.5
	var origin: Vector3 = frame.origin
	var right: Vector3 = frame.right
	match index:
		0:
			return origin - right * half_w
		1:
			return origin + right * half_w
		2:
			return origin + right * half_w + Vector3.UP * profile.y
		_:
			return origin - right * half_w + Vector3.UP * profile.y


func _side_ring(st: SurfaceTool, a: Dictionary, b: Dictionary) -> void:
	_quad(st, _corner(a, 0), _corner(b, 0), _corner(b, 1), _corner(a, 1))
	_quad(st, _corner(a, 1), _corner(b, 1), _corner(b, 2), _corner(a, 2))
	_quad(st, _corner(a, 2), _corner(b, 2), _corner(b, 3), _corner(a, 3))
	_quad(st, _corner(a, 3), _corner(b, 3), _corner(b, 0), _corner(a, 0))


func _cap(st: SurfaceTool, frame: Dictionary, at_end: bool) -> void:
	if at_end:
		_quad(st, _corner(frame, 0), _corner(frame, 1), _corner(frame, 2), _corner(frame, 3))
	else:
		_quad(st, _corner(frame, 0), _corner(frame, 3), _corner(frame, 2), _corner(frame, 1))


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
