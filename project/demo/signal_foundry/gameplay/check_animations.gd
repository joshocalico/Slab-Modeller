extends SceneTree

## Headless checks for reusable animation helpers. Does not load the authored level.

var fails := 0


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, what: String) -> void:
	if ok:
		print("ok ", what)
	else:
		fails += 1
		push_error("FAIL " + what)


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var rotator := Node3D.new()
	rotator.set_script(load("res://demo/signal_foundry/gameplay/rotating_machinery.gd"))
	rotator.rotation_axis = 1
	rotator.degrees_per_second = 90.0
	world.add_child(rotator)
	rotator._physics_process(1.0)
	expect(is_equal_approx(rotator.rotation.y, PI / 2.0), "rotator turns 90 degrees around selected Y axis")

	var platform_scene: PackedScene = load("res://demo/signal_foundry/gameplay/moving_platform.tscn")
	expect(platform_scene != null, "moving platform scene loads")
	var platform: AnimatableBody3D = platform_scene.instantiate()
	platform.local_travel = Vector3(0, 0, 4)
	platform.travel_duration = 2.0
	platform.endpoint_pause = 0.0
	var slab: Node3D = ClassDB.instantiate("SlabSolid")
	expect(int(slab.call("make_box", Vector3(2, 0.3, 2))) == 0, "test Slab platform builds")
	platform.get_node("PlaceSlabChildrenHere").add_child(slab)
	world.add_child(platform)
	await process_frame
	platform.set_physics_process(false)
	platform.elapsed = 0.0
	platform.direction = 1.0
	platform.transform = platform.start_transform
	await physics_frame
	expect(platform.adopted_shapes == 1, "carrier adopts the hand-authored Slab collision")
	expect(platform.get_node_or_null("CarrierShape0") is CollisionShape3D, "carrier owns a physics shape")
	var source_shape: CollisionShape3D = slab.get_node("__body/__shape")
	expect(source_shape.disabled, "duplicate static Slab collider is disabled")
	platform._physics_process(1.0)
	await physics_frame
	expect(is_equal_approx(platform.position.z, 2.0), "shuttle reaches midpoint after half its duration, z=%s" % platform.position.z)
	platform._physics_process(1.0)
	await physics_frame
	expect(is_equal_approx(platform.position.z, 4.0), "shuttle reaches configured local endpoint, z=%s" % platform.position.z)
	platform._physics_process(1.0)
	await physics_frame
	expect(is_equal_approx(platform.position.z, 2.0), "shuttle reverses toward its start, z=%s" % platform.position.z)

	var hazard_scene: PackedScene = load("res://demo/signal_foundry/gameplay/hazard_reset.tscn")
	expect(hazard_scene != null, "hazard reset scene loads")
	var player_scene: PackedScene = load("res://demo/signal_foundry/gameplay/player.tscn")
	var player: CharacterBody3D = player_scene.instantiate()
	world.add_child(player)
	player.activate_checkpoint(Transform3D(Basis.IDENTITY, Vector3(7, 0, 2)), "Safety")
	player.position = Vector3(-3, 2, -3)
	var hazard: Area3D = hazard_scene.instantiate()
	world.add_child(hazard)
	hazard._on_body_entered(player)
	expect(player.global_position.is_equal_approx(Vector3(7, 0, 2)), "hazard returns player to active checkpoint")
	expect(hazard.triggered, "hazard debounce activates")

	print("animation checks: %d failure(s)" % fails)
	quit(1 if fails else 0)
