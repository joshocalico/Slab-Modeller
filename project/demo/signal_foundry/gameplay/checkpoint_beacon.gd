extends Area3D

@export var checkpoint_title := "CHECKPOINT"
var activated := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if activated or not body.has_method("activate_checkpoint"):
		return
	activated = true
	var respawn := global_transform
	respawn.origin = global_position
	body.call("activate_checkpoint", respawn, checkpoint_title)
	$Visual/Ring.hide()
	$Visual/RingOnline.show()
	$Visual/OmniLight3D.light_color = Color(0.1, 1.0, 0.72)
	$Label3D.text = "%s\nONLINE" % checkpoint_title.to_upper()
