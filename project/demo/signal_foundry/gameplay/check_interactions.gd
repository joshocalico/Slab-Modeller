extends SceneTree

## Headless checks for reusable gameplay scenes. Does not load the authored level.

var fails := 0
var world: Node3D
var player: CharacterBody3D
var exit_completion_events := 0


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, what: String) -> void:
	if ok:
		print("ok ", what)
	else:
		fails += 1
		push_error("FAIL " + what)


func settle(frames: int = 4) -> void:
	for i in frames:
		await physics_frame


func load_scene(path: String) -> PackedScene:
	var packed: PackedScene = load(path)
	expect(packed != null, "%s loads" % path.get_file())
	return packed


func run() -> void:
	world = Node3D.new()
	root.add_child(world)

	var player_scene := load_scene("res://demo/signal_foundry/gameplay/player.tscn")
	var cell_scene := load_scene("res://demo/signal_foundry/gameplay/energy_cell.tscn")
	var checkpoint_scene := load_scene("res://demo/signal_foundry/gameplay/checkpoint_beacon.tscn")
	var exit_scene := load_scene("res://demo/signal_foundry/gameplay/exit_beacon.tscn")
	if player_scene == null or cell_scene == null or checkpoint_scene == null or exit_scene == null:
		quit(1)
		return

	player = player_scene.instantiate()
	world.add_child(player)
	await settle()
	expect(player.energy_cells == 0, "player starts with no energy")
	expect(not player.has_exit_power(3), "three-cell exit starts locked")
	var locked_exit: Area3D = exit_scene.instantiate()
	locked_exit.required_cells = 4
	world.add_child(locked_exit)
	expect(locked_exit.get_node("Label3D").text == "EXIT\n4 CELLS", "exit label reflects configured requirement")
	locked_exit._on_body_entered(player)
	expect(not locked_exit.completed, "exit remains incomplete without enough cells")
	expect(locked_exit.get_node("Label3D").text.contains("4 CELLS REQUIRED"), "locked exit reports its requirement")
	expect(player.get_node("HUD/Margin/Rows/Notice").text.contains("4 MORE CELLS"), "locked exit reports missing cells on HUD")
	var unrelated_body := Node3D.new()
	locked_exit._on_body_entered(unrelated_body)
	locked_exit._on_body_exited(unrelated_body)
	expect(locked_exit.get_node("Label3D").text.contains("4 CELLS REQUIRED"), "unrelated bodies do not change exit state")
	unrelated_body.free()
	expect(not locked_exit.get_node("Label3D").no_depth_test, "exit label respects scene depth")
	locked_exit.queue_free()

	var cell: Area3D = cell_scene.instantiate()
	world.add_child(cell)
	expect(not cell.get_node("Visual/Label3D").no_depth_test, "energy label respects scene depth")
	cell._on_body_entered(player)
	expect(player.energy_cells == 1, "energy cell increments progress")
	expect(cell.collected, "energy cell cannot collect twice")
	cell._on_body_entered(player)
	expect(player.energy_cells == 1, "duplicate overlap does not increment progress")

	player.collect_energy_cell()
	player.collect_energy_cell()
	expect(player.has_exit_power(3), "three cells power the exit")
	expect(player.get_node("HUD/Margin/Rows/Objective").text.contains("3 / 3"), "HUD shows completed energy count")

	var checkpoint: Area3D = checkpoint_scene.instantiate()
	checkpoint.position = Vector3(8, 0, -4)
	checkpoint.rotation.y = PI / 2.0
	checkpoint.checkpoint_title = "Forge Deck"
	world.add_child(checkpoint)
	expect(checkpoint.get_node("Label3D").text == "FORGE DECK", "checkpoint label reflects configured title before activation")
	expect(not checkpoint.get_node("Label3D").no_depth_test, "checkpoint label respects scene depth")
	checkpoint._on_body_entered(player)
	var expected_respawn := Vector3(6.5, 0, -4)
	expect(player.spawn_transform.origin.is_equal_approx(expected_respawn), "checkpoint offsets respawn 1.5 m along local -Z")
	expect(player.spawn_transform.basis.z.is_equal_approx(checkpoint.global_basis.z), "checkpoint preserves beacon facing")
	expect(player.checkpoint_name == "FORGE DECK", "checkpoint updates HUD name")
	player.position = Vector3.ZERO
	player._reset_to_spawn()
	expect(player.global_position.is_equal_approx(expected_respawn), "reset returns beside the active checkpoint")

	var exit_beacon: Area3D = exit_scene.instantiate()
	world.add_child(exit_beacon)
	exit_beacon.exit_completed.connect(func(_body: Node3D) -> void: exit_completion_events += 1)
	exit_beacon._on_body_entered(player)
	expect(exit_beacon.completed, "powered exit latches completion")
	expect(exit_completion_events == 1, "powered exit emits one completion signal")
	expect(exit_beacon.get_node("Visual/Powered").visible, "powered exit shows green field")
	expect(not exit_beacon.get_node("Visual/Locked").visible, "powered exit hides red field")
	exit_beacon._on_body_exited(player)
	expect(exit_beacon.get_node("Visual/Powered").visible, "completed exit stays visibly powered after player leaves")
	player.notice_time = 1.25
	exit_beacon._on_body_entered(player)
	expect(exit_completion_events == 1, "completed exit does not emit again on re-entry")
	expect(is_equal_approx(player.notice_time, 1.25), "completed exit notifies the HUD only once")

	print("interaction checks: %d failure(s)" % fails)
	quit(1 if fails else 0)
