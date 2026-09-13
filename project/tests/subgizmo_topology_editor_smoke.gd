extends "res://tests/native_gizmo_editor_smoke.gd"

# Headless editor integration for topology-driven native subgizmo frames.
# scripts/godot --editor --headless --path project --script res://tests/subgizmo_topology_editor_smoke.gd

func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("Requires --editor")
		return
	var editor := Engine.get_singleton("EditorInterface")
	var deadline := Time.get_ticks_msec() + 30000
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		if Time.get_ticks_msec() > deadline:
			_fail("Editor initialization timed out")
			return
		await process_frame
	await create_timer(1.5).timeout
	editor.open_scene_from_path("res://demo/modeller_lab.tscn")
	var stable := 0
	while stable < 20:
		await process_frame
		var scene: Node = editor.get_edited_scene_root()
		stable = stable + 1 if scene != null and scene.scene_file_path == "res://demo/modeller_lab.tscn" else 0
		if Time.get_ticks_msec() > deadline:
			_fail("Fixture did not remain current")
			return
	var plugin := _plugin(root)
	var solid: Node3D = editor.get_edited_scene_root().get_node("Box2")
	var selection: RefCounted = plugin.get("_selection")
	editor.get_selection().clear()
	editor.get_selection().add_node(solid)
	selection.mode = 3
	var face := _top_face(solid)
	selection.set_ids(PackedInt64Array([face]))
	await process_frame
	var gizmo := _slab_gizmo(plugin, solid)
	if gizmo == null:
		_fail("Selected Slab gizmo was not available")
		return
	var before: PackedByteArray = solid.get("data")
	var before_origin: Vector3 = plugin.get("_solid_gizmo")._get_subgizmo_transform(gizmo, 2147483646).origin
	_check(solid.call("extrude_faces", PackedInt64Array([face]), 0.5) == OK, "extrude_commits")
	_check(String(plugin.get("_subgizmo_token")).is_empty(), "topology change invalidates the cached native frame synchronously")
	await process_frame
	await process_frame
	var moved_origin: Vector3 = plugin.get("_solid_gizmo")._get_subgizmo_transform(gizmo, 2147483646).origin
	_check(not moved_origin.is_equal_approx(before_origin), "topology_change_moves_selected_face_frame")
	solid.set("data", before)
	_check(String(plugin.get("_subgizmo_token")).is_empty(), "undo data restore invalidates the extruded frame synchronously")
	await process_frame
	await process_frame
	var restored_origin: Vector3 = plugin.get("_solid_gizmo")._get_subgizmo_transform(gizmo, 2147483646).origin
	_check(restored_origin.is_equal_approx(before_origin), "undo_data_restore_refreshes_selected_face_frame")
	_check(plugin.get("_topology_solid") == solid and not String(plugin.get("_subgizmo_token")).is_empty(),
		"selected solid remains bound and native frame is resynchronized")
	var session: RefCounted = plugin.get("_session")
	session.set("_pending_native_press", true)
	solid.set("data", before)
	await process_frame
	_check(String(plugin.get("_subgizmo_token")).is_empty(), "topology refresh does not replace a pending native drag frame")
	session.set("_pending_native_press", false)
	plugin._refresh_gizmos()
	_check(not String(plugin.get("_subgizmo_token")).is_empty(), "native release refreshes the invalidated frame")
	var other: Node3D = editor.get_edited_scene_root().get_node("Box")
	selection.set_objects([other])
	plugin._subgizmo_token = "other-frame"
	solid.set("data", before)
	_check(plugin.get("_subgizmo_token") == "other-frame", "selection change disconnects the previous solid topology")
	print("SUBGIZMO_TOPOLOGY_EDITOR_RESULT failures=", failures)
	quit(1 if failures else 0)


func _top_face(solid: Node3D) -> int:
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9:
			return face
	return 0


func _slab_gizmo(plugin: EditorPlugin, solid: Node3D) -> EditorNode3DGizmo:
	for gizmo in solid.get_gizmos():
		if gizmo.get_plugin() == plugin.get("_solid_gizmo"):
			return gizmo
	return null
