extends Area3D

@export var pulse_speed := 3.0
@export_range(0.0, 1.0, 0.01) var pulse_amount := 0.12
var base_mesh_scale := Vector3.ONE
var base_light_energy := 0.0
var time := 0.0
var triggered := false


func _ready() -> void:
	base_mesh_scale = $Visual/Mesh.scale
	base_light_energy = $Visual/OmniLight3D.light_energy
	body_entered.connect(_on_body_entered)


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
