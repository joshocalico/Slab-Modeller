extends Area3D

@export var spin_speed := 1.8
var collected := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	$Visual.rotate_y(spin_speed * delta)
	$Visual.position.y = 0.72 + sin(Time.get_ticks_msec() * 0.004) * 0.08


func _on_body_entered(body: Node3D) -> void:
	if collected or not body.has_method("collect_energy_cell"):
		return
	collected = true
	body.call("collect_energy_cell")
	monitoring = false
	$CollisionShape3D.set_deferred("disabled", true)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property($Visual, "scale", Vector3.ONE * 0.02, 0.22)
	tween.tween_property($Visual, "rotation:y", $Visual.rotation.y + TAU, 0.22)
	await tween.finished
	queue_free()
