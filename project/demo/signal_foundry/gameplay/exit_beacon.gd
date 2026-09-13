extends Area3D

signal exit_completed(player: Node3D)

@export_range(1, 99, 1) var required_cells := 3
var animation_time := 0.0
var completed := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	$Label3D.text = "EXIT\n%d CELLS" % required_cells


func _process(delta: float) -> void:
	animation_time += delta
	var pulse := 1.0 + sin(animation_time * 3.5) * 0.025
	$Visual/Locked.scale = Vector3(pulse, pulse, 1.0)
	$Visual/Powered.scale = Vector3(pulse, pulse, 1.0)


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("has_exit_power"):
		return
	if completed:
		return
	var powered: bool = body.call("has_exit_power", required_cells)
	$Visual/Powered.visible = powered
	$Visual/Locked.visible = not powered
	$Label3D.text = "EXIT ONLINE" if powered else "EXIT LOCKED\n%d CELLS REQUIRED" % required_cells
	if body.has_method("show_exit_status"):
		body.call("show_exit_status", required_cells)
	if powered:
		completed = true
		exit_completed.emit(body)


func _on_body_exited(body: Node3D) -> void:
	if completed or not body.has_method("has_exit_power"):
		return
	$Visual/Powered.hide()
	$Visual/Locked.show()
	$Label3D.text = "EXIT\n%d CELLS" % required_cells
