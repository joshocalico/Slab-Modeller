extends Area3D

@export var pulse_speed := 3.0
@export_range(0.0, 1.0, 0.01) var pulse_amount := 0.12
var base_scale := Vector3.ONE
var time := 0.0
var triggered := false


func _ready() -> void:
	base_scale = $Visual.scale
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	time += delta
	var pulse := 1.0 + sin(time * pulse_speed) * pulse_amount
	$Visual.scale = base_scale * pulse
	$Visual.rotate_y(delta * 0.7)


func _on_body_entered(body: Node3D) -> void:
	if triggered or not body.has_method("respawn_from_hazard"):
		return
	triggered = true
	body.call("respawn_from_hazard")
	var tween := create_tween()
	tween.tween_property($Visual, "scale", base_scale * 1.5, 0.08)
	tween.tween_property($Visual, "scale", base_scale, 0.12)
	await get_tree().create_timer(0.35).timeout
	triggered = false
