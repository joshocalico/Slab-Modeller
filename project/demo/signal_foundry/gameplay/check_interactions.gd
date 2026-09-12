extends SceneTree

## Headless checks for reusable gameplay scenes. Does not load the authored level.

var fails := 0
var world: Node3D
var player: CharacterBody3D


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

	var cell: Area3D = cell_scene.instantiate()
	world.add_child(cell)
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
	checkpoint.checkpoint_title = "Forge Deck"
	world.add_child(checkpoint)
	checkpoint._on_body_entered(player)
	expect(player.spawn_transform.origin.is_equal_approx(Vector3(8, 0, -4)), "checkpoint updates respawn position")
	expect(player.checkpoint_name == "FORGE DECK", "checkpoint updates HUD name")
	player.position = Vector3.ZERO
	player._reset_to_spawn()
	expect(player.global_position.is_equal_approx(Vector3(8, 0, -4)), "reset returns to active checkpoint")

	var exit_beacon: Area3D = exit_scene.instantiate()
	world.add_child(exit_beacon)
	exit_beacon._on_body_entered(player)
	expect(exit_beacon.get_node("Visual/Powered").visible, "powered exit shows green field")
	expect(not exit_beacon.get_node("Visual/Locked").visible, "powered exit hides red field")

	print("interaction checks: %d failure(s)" % fails)
	quit(1 if fails else 0)
