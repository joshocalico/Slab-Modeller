@tool
extends Area3D

@export var pulse_speed := 3.0
@export_range(0.0, 1.0, 0.01) var pulse_amount := 0.12
@export var footprint_size := Vector2(2.0, 2.0):
	set(value):
		footprint_size = Vector2(maxf(0.05, value.x), maxf(0.05, value.y))
		if is_node_ready():
			_sync_footprint()
var base_mesh_scale := Vector3.ONE
var base_light_energy := 0.0
var time := 0.0
var triggered := false


func _ready() -> void:
	_sync_footprint()
	base_mesh_scale = $Visual/Mesh.scale
	base_light_energy = $Visual/OmniLight3D.light_energy
	if Engine.is_editor_hint():
		set_process(false)
		return
	body_entered.connect(_on_body_entered)


func _sync_footprint() -> void:
	if not has_node("CollisionShape3D") or not has_node("Visual/Mesh"):
		return
	var shape := $CollisionShape3D.shape as BoxShape3D
	var mesh := $Visual/Mesh.mesh as BoxMesh
	if shape != null:
		shape.size = Vector3(footprint_size.x, shape.size.y, footprint_size.y)
	if mesh != null:
		mesh.size = Vector3(footprint_size.x, mesh.size.y, footprint_size.y)


func _process(delta: float) -> void:
	time += delta
	var pulse := 1.0 + sin(time * pulse_speed) * pulse_amount
	$Visual/Mesh.scale = Vector3(base_mesh_scale.x, base_mesh_scale.y * pulse, base_mesh_scale.z)


func _on_body_entered(body: Node3D) -> void:
	if triggered or not body.has_method("respawn_from_hazard"):
		return
	triggered = true
	body.call("respawn_from_hazard")
	var tween := create_tween()
	tween.tween_property($Visual/OmniLight3D, "light_energy", base_light_energy * 2.5, 0.08)
	tween.tween_property($Visual/OmniLight3D, "light_energy", base_light_energy, 0.12)
	await get_tree().create_timer(0.35).timeout
	triggered = false
