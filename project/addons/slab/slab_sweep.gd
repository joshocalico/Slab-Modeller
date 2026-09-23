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

## Join the final path point to the first, without end caps.
@export var closed := false:
	set(value):
		closed = value
		_rebuild()

## Path points describe the centre line at the profile's base height.
@export var points: PackedVector3Array = PackedVector3Array():
	set(value):
		points = value
		_rebuild()

var last_error := 0
var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_rebuild()


func _ensure_mesh() -> void:
	if _mesh_instance and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	add_child(_mesh_instance)
	var body := StaticBody3D.new()
	body.name = "__body"
	add_child(body)
	_collision = CollisionShape3D.new()
	_collision.name = "Shape"
	body.add_child(_collision)


func _get_configuration_warnings() -> PackedStringArray:
	if points.size() < (3 if closed else 2):
		return PackedStringArray(["A closed sweep needs at least three distinct points; an open sweep needs two."])
	if last_error != 0:
		return PackedStringArray(["The path/profile cannot form a valid closed solid. Remove duplicate points, reversals or intersections, or reduce the profile. The last valid mesh is retained."])
	return PackedStringArray()


func _rebuild() -> void:
	_ensure_mesh()
	# Use the same validated kernel as editable solid creation. The temporary
	# node is never added to the scene and its mesh resource outlives it.
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	var path := PackedVector3Array()
	for point in points:
		path.append(point + Vector3.UP * profile.y * 0.5)
	last_error = solid.call("make_sweep", path, profile, closed)
	if last_error == 0:
		var mesh: ArrayMesh = solid.call("build_mesh")
		var mat := StandardMaterial3D.new()
		mat.albedo_color = prototype_color
		mat.roughness = 0.7
		mesh.surface_set_material(0, mat)
		_mesh_instance.mesh = mesh
		_collision.shape = mesh.create_trimesh_shape()
	solid.free()
	if is_inside_tree():
		update_configuration_warnings()
		update_gizmos()
