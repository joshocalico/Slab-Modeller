extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	var top: int = 0
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9:
			top = face
	check(solid.call("inset_faces", PackedInt64Array([top]), 0.45) == OK, "room inset is valid")
	var caps: PackedInt64Array = solid.call("get_last_edited_faces")
	var wall := StandardMaterial3D.new()
	var floor_material := StandardMaterial3D.new()
	solid.set("materials", [wall, floor_material])
	solid.call("set_face_material", caps, 1)
	var original: PackedByteArray = solid.get("data")
	var committed: ArrayMesh = solid.call("build_mesh")
	var display: MeshInstance3D = solid.get_node("Mesh")
	var collider: CollisionShape3D = solid.get_node("__body/__shape")
	var collision := collider.shape
	var overrides: Array[Material] = []
	for i in committed.get_surface_count():
		overrides.append(display.get_surface_override_material(i))
	var stored_before := stored_properties(solid)
	var scratch: Node3D = ClassDB.instantiate("SlabSolid")
	scratch.set("data", original)
	check(scratch.call("extrude_faces", caps, -2.4) == OK, "room cavity preview is valid")
	check(solid.call("set_display_preview", scratch.get("data")), "validated cavity is displayed")
	check(display.mesh != committed, "display uses the proposed result")
	check(solid.call("build_mesh") == committed, "mesh export retains the exact committed resource")
	check(solid.get("data") == original and stored_properties(solid) == stored_before,
		"packing the scene during preview preserves committed properties and excludes preview children")
	check(collider.shape == collision and not collider.disabled, "preview preserves the collision resource and enabled state")
	check(solid.get("materials") == [wall, floor_material], "preview preserves material resources")
	solid.call("clear_display_preview")
	check(display.mesh == committed, "cancel restores the exact committed display resource")
	for i in overrides.size():
		check(display.get_surface_override_material(i) == overrides[i], "cancel restores material slot %d" % i)
	check(not solid.call("set_display_preview", PackedByteArray([1, 2, 3])), "corrupt preview bytes are rejected")
	check(display.mesh == committed and solid.get("data") == original, "rejected preview preserves committed geometry")
	solid.set("collision_enabled", false)
	var disabled_mesh: ArrayMesh = solid.call("build_mesh")
	var disabled_shape := collider.shape
	check(solid.call("set_display_preview", scratch.get("data")), "preview works with collision disabled")
	check(collider.disabled and collider.shape == disabled_shape, "preview preserves disabled collision and its existing shape")
	solid.call("clear_display_preview")
	check(display.mesh == disabled_mesh and collider.disabled, "cancel preserves disabled collision")
	scratch.free()
	solid.free()
	print("display_preview_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func stored_properties(solid: Node) -> Dictionary:
	var packed := PackedScene.new()
	check(packed.pack(solid) == OK, "scene packs during display preview")
	var state := packed.get_state()
	check(state.get_node_count() == 1, "generated display children are not serialized")
	var properties := {}
	for i in state.get_node_property_count(0):
		properties[state.get_node_property_name(0, i)] = state.get_node_property_value(0, i)
	return properties


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("ok " if ok else "FAIL ", message)
