extends Node3D

## Attach to a Node3D parent of editor-authored machinery.

@export_enum("X", "Y", "Z") var rotation_axis := 1
@export var degrees_per_second := 45.0
@export var running := true


func _physics_process(delta: float) -> void:
	if not running or is_zero_approx(degrees_per_second):
		return
	var axis := Vector3.RIGHT
	if rotation_axis == 1:
		axis = Vector3.UP
	elif rotation_axis == 2:
		axis = Vector3.BACK
	rotate_object_local(axis, deg_to_rad(degrees_per_second) * delta)
