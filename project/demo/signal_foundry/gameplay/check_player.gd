extends SceneTree

## Headless checks for the Foundry player. Does not load signal_foundry.tscn.

var fails := 0
var player: CharacterBody3D
var world: Node3D


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, what: String) -> void:
	if ok:
		print("ok ", what)
	else:
		fails += 1
		push_error("FAIL " + what)


func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)


func tap_player(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	player._unhandled_input(event)


func add_box(size: Vector3, origin: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.position = origin
	body.add_child(collider)
	world.add_child(body)
	return body


func settle(frames: int = 8) -> void:
	for i in frames:
		await physics_frame


func run() -> void:
	var packed: PackedScene = load("res://demo/signal_foundry/gameplay/player.tscn")
	expect(packed != null, "player.tscn loads")
	if packed == null:
		quit(1)
		return

	world = Node3D.new()
	root.add_child(world)
	add_box(Vector3(4, 1, 4), Vector3(0, -0.5, 0))

	player = packed.instantiate()
	expect(player is CharacterBody3D, "root is CharacterBody3D")
	player.position = Vector3(0, 0, 0)
	world.add_child(player)
	await settle(12)

	var shape_node: CollisionShape3D = player.get_node("CollisionShape3D")
	var capsule: CapsuleShape3D = shape_node.shape
	expect(is_equal_approx(capsule.radius, 0.3), "capsule radius 0.3, got %s" % capsule.radius)
	expect(is_equal_approx(capsule.height, 1.7), "capsule height 1.7, got %s" % capsule.height)
	expect(shape_node.position.is_equal_approx(Vector3(0, 0.85, 0)), "capsule centred at y=0.85")
	var camera: Camera3D = player.get_node("Camera3D")
	expect(camera.position.is_equal_approx(Vector3(0, 1.55, 0)), "eye at y=1.55")
	expect(is_equal_approx(camera.fov, 78.0), "fov 78")
	expect(camera.current, "camera is current")
	expect(is_equal_approx(player.floor_snap_length, 0.35), "floor snap 0.35")
	expect(player.is_on_floor(), "spawn stands on the floor")
	expect(player.spawn_transform.origin.is_equal_approx(Vector3(0, 0, 0)), "spawn is the instance transform")
	var diagnostics: Control = player.get_node("HUD/Diagnostics")
	var diagnostic_text: Label = player.get_node("HUD/Diagnostics/Readout")
	expect(not diagnostics.visible, "F3 diagnostics start hidden")
	tap_player(KEY_F3)
	expect(diagnostics.visible, "F3 shows diagnostics")
	expect(diagnostic_text.text.contains("feet  X"), "diagnostics show global feet coordinates")
	expect(diagnostic_text.text.contains("floor  YES"), "diagnostics show grounded state")
	expect(diagnostic_text.text.contains("StaticBody3D"), "diagnostics identify floor collider, text=%s" % diagnostic_text.text)
	expect(diagnostic_text.text.contains("autorun  OFF"), "diagnostics show autorun state")
	tap_player(KEY_F3)
	expect(not diagnostics.visible, "second F3 hides diagnostics")

	player.position = Vector3(1.5, 2.0, -1.0)
	player.rotation.y = 0.4
	player.pitch = 0.5
	camera.rotation.x = 0.5
	player.velocity = Vector3(2, -1, 3)
	Input.action_press("foundry_reset")
	await settle(2)
	Input.action_release("foundry_reset")
	expect(player.global_position.is_equal_approx(Vector3(0, 0, 0)), "R restores instance origin, at=%s" % player.global_position)
	expect(is_equal_approx(player.rotation.y, 0.0), "R restores instance yaw")
	expect(is_equal_approx(player.pitch, 0.0), "R restores pitch")
	expect(player.velocity.is_equal_approx(Vector3.ZERO), "R clears velocity")

	var yaw_before: float = player.rotation.y
	var pitch_before: float = player.pitch
	Input.action_press("foundry_look_right")
	Input.action_press("foundry_look_down")
	await settle(10)
	Input.action_release("foundry_look_right")
	Input.action_release("foundry_look_down")
	expect(player.rotation.y < yaw_before - 0.05, "keyboard look right yaws, %s -> %s" % [yaw_before, player.rotation.y])
	expect(player.pitch < pitch_before - 0.05, "keyboard look down pitches, %s -> %s" % [pitch_before, player.pitch])
	expect(is_equal_approx(camera.rotation.x, player.pitch), "camera pitch follows keyboard look")

	Input.action_press("foundry_reset")
	await settle(2)
	Input.action_release("foundry_reset")

	add_box(Vector3(3, 1, 3), Vector3(12, -0.5, 0))
	player.global_position = Vector3(12, 0, 0)
	player.rotation.y = -PI / 2.0
	player.velocity = Vector3.ZERO
	await settle(8)
	expect(player.is_on_floor(), "coyote start is on the ledge")
	Input.action_press("foundry_forward")
	var frames := 0
	while frames < 180 and player.is_on_floor():
		await physics_frame
		frames += 1
	Input.action_release("foundry_forward")
	expect(not player.is_on_floor(), "walked off the ledge after %d frames" % frames)
	Input.action_press("foundry_jump")
	await physics_frame
	Input.action_release("foundry_jump")
	await physics_frame
	expect(player.velocity.y > 4.0, "coyote jump after leaving the floor, vy=%s" % player.velocity.y)

	player.global_transform = player.spawn_transform
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0, 1.1, 0)
	await physics_frame
	expect(not player.is_on_floor(), "buffer start is in the air")
	frames = 0
	while frames < 90 and player.global_position.y > 0.22 and not player.is_on_floor():
		await physics_frame
		frames += 1
	Input.action_press("foundry_jump")
	await physics_frame
	Input.action_release("foundry_jump")
	var bounced := false
	for i in 20:
		await physics_frame
		if player.velocity.y > 4.0:
			bounced = true
			break
	expect(bounced, "jump buffer fires on landing, y=%s vy=%s" % [player.global_position.y, player.velocity.y])

	add_box(Vector3(2, 1, 2), Vector3(19.2, -0.5, 0))
	var stair: Node3D = ClassDB.instantiate("SlabSolid")
	world.add_child(stair)
	expect(int(stair.call("make_stair", Vector3(3, 1.0, 2), 4)) == 0, "0.25 m riser Slab stair builds")
	stair.position = Vector3(20, 0, -1)
	await settle(8)
	player.global_position = Vector3(19.2, 0, 0)
	player.rotation.y = -PI / 2.0
	player.velocity = Vector3.ZERO
	await settle(6)
	Input.action_press("foundry_forward")
	frames = 0
	while frames < 400 and player.global_position.y < 0.85:
		await physics_frame
		frames += 1
	Input.action_release("foundry_forward")
	await settle(8)
	expect(player.global_position.y > 0.7, "walks a 4×0.25 m Slab stair, y=%s frames=%d" % [player.global_position.y, frames])

	player.global_transform = player.spawn_transform
	player.velocity = Vector3.ZERO
	player.auto_run = false
	player.pitch = player.spawn_pitch
	await settle(8)
	expect(player.is_on_floor(), "autorun start is on the pad")
	expect(not player.auto_run, "autorun starts off")
	tap_player(KEY_T)
	expect(player.auto_run, "T tap starts autorun")
	await settle(20)
	expect(player.global_position.z < -0.8, "autorun walks forward without holding W, z=%s" % player.global_position.z)
	expect(absf(player.velocity.z + 5.0) < 0.05, "autorun is walk speed, vz=%s" % player.velocity.z)
	Input.action_press("foundry_jump")
	await physics_frame
	Input.action_release("foundry_jump")
	await physics_frame
	expect(player.velocity.y > 4.0, "Space still jumps during autorun, vy=%s" % player.velocity.y)
	expect(player.velocity.z < -4.0, "autorun keeps forward speed in the air, vz=%s" % player.velocity.z)

	player.global_transform = player.spawn_transform
	player.velocity = Vector3.ZERO
	await settle(8)
	expect(player.is_on_floor(), "back on the pad before toggling autorun off")
	expect(player.auto_run, "autorun stays on across a scripted teleport")
	tap_player(KEY_T)
	expect(not player.auto_run, "second T tap stops autorun")
	await settle(8)
	var z_stopped: float = player.global_position.z
	await settle(12)
	expect(absf(player.global_position.z - z_stopped) < 0.2, "after T-off the player is not still running, z=%s" % player.global_position.z)

	player.global_transform = player.spawn_transform
	player.velocity = Vector3.ZERO
	player.auto_run = false
	await settle(6)
	tap_player(KEY_T)
	await settle(10)
	expect(player.auto_run, "autorun is on before S")
	tap_player(KEY_S)
	expect(not player.auto_run, "S tap cancels autorun")
	Input.action_press("foundry_back")
	await physics_frame
	Input.action_release("foundry_back")
	var z_after_s: float = player.global_position.z
	await settle(12)
	expect(absf(player.global_position.z - z_after_s) < 0.25, "S does not leave autorun running, z=%s" % player.global_position.z)

	player.auto_run = true
	player.velocity = Vector3(0, 0, -5)
	player.global_position = Vector3(0.4, 0, 0.4)
	Input.action_press("foundry_reset")
	await settle(2)
	Input.action_release("foundry_reset")
	expect(not player.auto_run, "R clears autorun")
	expect(player.global_position.is_equal_approx(Vector3(0, 0, 0)), "R still restores origin after autorun")

	player.auto_run = true
	tap_player(KEY_ESCAPE)
	expect(not player.auto_run, "Esc stops autorun")
	expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Esc still releases the mouse")

	player.global_transform = player.spawn_transform
	player.velocity = Vector3.ZERO
	player.auto_run = false
	await settle(4)
	Input.action_press("foundry_forward")
	await settle(12)
	Input.action_release("foundry_forward")
	expect(player.global_position.z < -0.4, "held W still walks without autorun, z=%s" % player.global_position.z)

	player.global_transform = player.spawn_transform
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	tap_player(KEY_Q)
	await settle(20)
	expect(is_equal_approx(player.rotation.y, deg_to_rad(15.0)),
		"one Q tap is a 15° left step even if held-time passes, yaw=%s" % player.rotation.y)
	tap_player(KEY_E)
	expect(is_equal_approx(player.rotation.y, 0.0), "E yaws 15° right, yaw=%s" % player.rotation.y)

	expect(FileAccess.file_exists("res://demo/signal_foundry/signal_foundry.tscn"), "authored foundry scene is untouched on disk")

	if fails != 0:
		push_error("%d failures" % fails)
		quit(1)
	else:
		print("check_player ok")
		quit(0)
