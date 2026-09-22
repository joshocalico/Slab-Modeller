extends SceneTree

## Comprehensive reopen test for all demo scenes.
## Verifies SlabSolid topology reloads from data, runtime collision exists,
## and no GDScript errors on reopen.
## scripts/godot --headless --path project --script res://tests/reopen_smoke.gd

var _fails := 0
var _scenes_tested := 0


func _initialize() -> void:
	call_deferred("run")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		push_error("FAIL " + what)
		_fails += 1
	else:
		print("ok ", what)


func _check_solid(solid: Node, name: String) -> void:
	if solid == null:
		push_error("FAIL %s is null" % name)
		_fails += 1
		return
	if not solid.is_class("SlabSolid"):
		push_error("FAIL %s is not a SlabSolid" % name)
		_fails += 1
		return
	var data: PackedByteArray = solid.get("data")
	_expect(data.size() >= 100, "%s stores topology in data, bytes=%d" % [name, data.size()])
	var face_count: int = int(solid.call("face_count"))
	_expect(face_count >= 1, "%s reloads at least 1 face from data, got %d" % [name, face_count])
	var collider: CollisionShape3D = solid.get_node_or_null("__body/__shape")
	_expect(collider != null, "%s has collision body" % name)
	if collider != null:
		var collision_enabled: bool = solid.get("collision_enabled")
		if collision_enabled:
			_expect(collider.shape is ConcavePolygonShape3D, "%s has ConcavePolygonShape3D collision" % name)
			if collider.shape is ConcavePolygonShape3D:
				_expect(collider.shape.get_faces().size() >= 3, "%s collision has triangles" % name)
		else:
			_expect(collider.disabled or collider.shape == null, "%s disabled collision is inactive" % name)


func _test_scene(path: String) -> void:
	print("\n=== Testing %s ===" % path)
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("FAIL %s missing" % path)
		_fails += 1
		return
	var scene: Node = packed.instantiate()
	if scene == null:
		push_error("FAIL %s cannot instantiate" % path)
		_fails += 1
		return
	root.add_child(scene)
	for i in 3:
		await process_frame
	var solids: Array[Node] = scene.find_children("*", "SlabSolid", true, false)
	print("Found %d SlabSolid(s) in %s" % [solids.size(), path])
	_expect(solids.size() >= 1, "%s has at least one SlabSolid" % path.get_file())
	for solid in solids:
		_check_solid(solid, "%s/%s" % [path.get_file(), solid.name])
	scene.queue_free()
	_scenes_tested += 1


func run() -> void:
	var scenes := [
		"res://demo/demo.tscn",
		"res://demo/modeller_lab.tscn",
		"res://demo/relay_yard/relay_yard.tscn",
		"res://demo/signal_foundry/signal_foundry.tscn",
	]
	for scene_path in scenes:
		if FileAccess.file_exists(scene_path):
			await _test_scene(scene_path)
		else:
			print("SKIP %s (not found)" % scene_path)
	print("\n=== Summary ===")
	print("Scenes tested: %d" % _scenes_tested)
	if _fails != 0:
		push_error("reopen_smoke FAIL: %d failure(s)" % _fails)
		quit(1)
	else:
		print("reopen_smoke ok")
		quit(0)
