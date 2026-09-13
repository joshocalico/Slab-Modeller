extends SceneTree

# Save in the editor first, then run:
# scripts/godot --headless --path project --script res://tests/editor_scene_snapshot.gd -- res://demo/modeller_lab.tscn [Box2]
# Inspects a detached scene. No scripts receive tree/ready callbacks and no files are saved.
# Vertex IDs are strings so JSON readers retain all 64 bits.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1 or args.size() > 2:
		_fail("Usage: -- scene_path [node_path_relative_to_scene_root]")
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		_fail("Cannot load PackedScene: " + args[0])
		return
	var scene := packed.instantiate()
	var target := scene.get_node_or_null(NodePath(args[1])) if args.size() == 2 else scene
	if target == null:
		scene.free()
		_fail("No node at: " + args[1])
		return
	var solids: Array[Dictionary] = []
	_collect(target, scene, solids)
	solids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.path < b.path)
	if solids.is_empty():
		scene.free()
		_fail("No SlabSolid nodes in requested subtree")
		return
	print(JSON.stringify({"scene": args[0], "solids": solids}, "", true, true))
	scene.free()
	quit()


func _collect(node: Node, scene: Node, solids: Array[Dictionary]) -> void:
	if node.is_class("SlabSolid"):
		var solid := node as Node3D
		var world := _world_transform(solid)
		var ids: PackedInt64Array = solid.call("get_vertices")
		ids.sort()
		var vertices: Array[Dictionary] = []
		for id in ids:
			var local: Vector3 = solid.call("vertex_position", id)
			vertices.append({"id": str(id), "local": _vector(local), "world": _vector(world * local)})
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(solid.get("data"))
		solids.append({
			"path": str(scene.get_path_to(solid)),
			"local_transform": _transform(solid.transform),
			"global_transform": _transform(world),
			"data_sha256": digest.finish().hex_encode(),
			"vertices": vertices,
			"face_count": (solid.call("get_faces") as PackedInt64Array).size(),
			"edge_count": (solid.call("get_edges") as PackedInt64Array).size(),
		})
	for child in node.get_children():
		_collect(child, scene, solids)


func _world_transform(node: Node3D) -> Transform3D:
	# Node3D.global_transform requires a live tree. Compose the saved transforms
	# instead so inspection cannot run scene gameplay or editor tool callbacks.
	if node.top_level or not node.get_parent() is Node3D:
		return node.transform
	return _world_transform(node.get_parent() as Node3D) * node.transform


func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _transform(value: Transform3D) -> Dictionary:
	return {"origin": _vector(value.origin), "basis_columns": [
		_vector(value.basis.x), _vector(value.basis.y), _vector(value.basis.z)]}


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
