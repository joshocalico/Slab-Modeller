extends SceneTree

var player: CharacterBody3D
var yard: Node3D
var failed := false

func _initialize() -> void:
	call_deferred("run")

func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func walk(target: Vector3, label: String) -> void:
	var frames := 0
	Input.action_press("yard_forward")
	while frames < 900:
		var delta := target - player.global_position
		delta.y = 0
		if delta.length() < 0.3:
			break
		player.rotation.y = atan2(-delta.x, -delta.z)
		await physics_frame
		frames += 1
	Input.action_release("yard_forward")
	for i in range(3):
		await physics_frame
	var good := frames < 900 and absf(player.position.y - target.y) < 0.65
	failed = failed or not good
	print("ROUTE %s %s at=%s frames=%d" % [label, "PASS" if good else "FAIL", player.position, frames])

func interact() -> void:
	await process_frame
	key(KEY_E, true)
	await process_frame
	key(KEY_E, false)

func run() -> void:
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	yard = load("res://demo/relay_yard/relay_yard.tscn").instantiate()
	root.add_child(yard)
	player = yard.get_node("Player")
	for i in range(5):
		await physics_frame
	await walk(Vector3(10,0,20), "around machinery")
	await walk(Vector3(10,0,11.5), "approach workshop")
	await walk(Vector3(5.5,0,11.5), "door approach")
	await walk(Vector3(5.5,0.35,8), "door threshold")
	await walk(Vector3(7,0.35,6), "workshop cell")
	await interact()
	await walk(Vector3(5.5,0.35,8), "leave workshop")
	await walk(Vector3(5.5,0,11.5), "exit threshold")
	await walk(Vector3(11.5,0,9), "stair approach")
	await walk(Vector3(12,0,5.5), "stair foot")
	await walk(Vector3(24,3.2,5.5), "stair ascent")
	await walk(Vector3(28,3.2,7), "gallery cell")
	await interact()
	await walk(Vector3(27.5,3.2,12), "walkway entrance")
	await walk(Vector3(27.5,3.2,20), "lookout walkway")
	await walk(Vector3(26,3.2,21), "lookout cell")
	await interact()
	await walk(Vector3(27.5,3.2,20), "return to walkway")
	await walk(Vector3(27.5,3.2,12), "return walkway")
	await walk(Vector3(28,3.2,7), "return gallery")
	await walk(Vector3(24,3.2,5.5), "top stair")
	await walk(Vector3(12,0,5.5), "stair descent")
	await walk(Vector3(11.5,0,9), "return courtyard")
	await walk(Vector3(16,0,10), "central route")
	await walk(Vector3(16,0,23), "exit gate")
	await interact()
	for i in range(90):
		await physics_frame
	await walk(Vector3(16,0,27), "gate traversal")
	var won: bool = yard.title.text == "YARD RESTORED"
	print("ROUTE collected=%d expected=3 won=%s failed=%s" % [yard.collected, won, failed])
	quit(1 if failed or yard.collected != 3 or not won else 0)
