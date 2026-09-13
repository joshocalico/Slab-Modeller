extends Area3D

@export var checkpoint_title := "CHECKPOINT"
@export var local_respawn_offset := Vector3(0, 0, -1.5)
var activated := false
var animation_time := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	$Label3D.text = checkpoint_title.to_upper()


func _process(delta: float) -> void:
	animation_time += delta
	$Visual/Ring.rotate_y(delta * (2.2 if activated else 0.7))
	$Visual/RingOnline.rotate_y(delta * 2.2)
	if activated:
		var pulse := 1.0 + sin(animation_time * 4.0) * 0.08
		$Visual/RingOnline.scale = Vector3.ONE * pulse


func _on_body_entered(body: Node3D) -> void:
	if activated or not body.has_method("activate_checkpoint"):
		return
	activated = true
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var facing := Basis.looking_at(forward.normalized(), Vector3.UP)
	var respawn := Transform3D(facing, global_position + facing * local_respawn_offset)
	body.call("activate_checkpoint", respawn, checkpoint_title)
	$Visual/Ring.hide()
	$Visual/RingOnline.show()
	$Visual/OmniLight3D.light_color = Color(0.1, 1.0, 0.72)
	$Label3D.text = "%s\nONLINE" % checkpoint_title.to_upper()
