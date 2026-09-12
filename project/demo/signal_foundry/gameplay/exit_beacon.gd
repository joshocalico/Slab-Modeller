extends Area3D

@export_range(1, 99, 1) var required_cells := 3


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("has_exit_power"):
		return
	var powered: bool = body.call("has_exit_power", required_cells)
	$Visual/Powered.visible = powered
	$Visual/Locked.visible = not powered
	$Label3D.text = "EXIT ONLINE" if powered else "EXIT LOCKED\n%d CELLS REQUIRED" % required_cells
	if body.has_method("show_exit_status"):
		body.call("show_exit_status", required_cells)


func _on_body_exited(_body: Node3D) -> void:
	$Visual/Powered.hide()
	$Visual/Locked.show()
	$Label3D.text = "EXIT\n%d CELLS" % required_cells
