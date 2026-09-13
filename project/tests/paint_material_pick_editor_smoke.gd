extends "res://tests/panel_editor_smoke.gd"

# Editor undo acceptance for imported paint materials. The lab scene is never saved.
# scripts/godot --editor --path project --script res://tests/paint_material_pick_editor_smoke.gd
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
	var stable_frames := 0
	deadline = Time.get_ticks_msec() + 15000
	while stable_frames < 20:
		await process_frame
		var edited: Node = editor.get_edited_scene_root()
		stable_frames = stable_frames + 1 if edited != null and edited.scene_file_path == "res://demo/modeller_lab.tscn" else 0
		if Time.get_ticks_msec() > deadline:
			_fail("Material fixture did not remain current after session restore")
			return
	var plugin := _plugin(root)
	var selection: RefCounted = plugin.get("_selection")
	var actions: RefCounted = plugin.get("_actions")
	var paint: RefCounted = plugin.get("_paint")
	var solid: Node3D = editor.get_edited_scene_root().get_node("Box2")
	selection.set_objects([solid])
	selection.mode = 3
	var faces: PackedInt64Array = solid.call("get_faces")
	for face in faces:
		solid.call("set_face_material", PackedInt64Array([face]), 0)
	solid.set("materials", [])
	var selected := PackedInt64Array([faces[0]])
	selection.set_ids(selected)
	var before_data: PackedByteArray = solid.get("data")
	var before_mats: Array = (solid.get("materials") as Array).duplicate()
	var before_slot: int = actions.material_slot
	var imported := ResourceLoader.load("res://demo/signal_foundry/materials/brick.tres") as StandardMaterial3D
	paint.pick_material(imported)
	await process_frame
	var after_data: PackedByteArray = solid.get("data")
	var after_mats: Array = solid.get("materials")
	_check(after_data != before_data, "pick_changes_selected_face_data")
	_check(after_mats.size() == 2 and after_mats[0] == null and after_mats[1] == imported,
		"first_pick_reserves_default_slot_and_preserves_resource_identity")
	_check(int(solid.call("face_uv", selected[0]).get("slot", -1)) == 1,
		"selected_face_receives_imported_material")
	for i in range(1, faces.size()):
		_check(int(solid.call("face_uv", faces[i]).get("slot", -1)) == 0,
			"unselected_face_%d_keeps_default_slot" % i)
	_check(actions.material_slot == 1 and paint.material() == imported,
		"paint_binding_tracks_imported_slot")
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(solid))
	_check(history.has_undo(), "pick_is_recorded_in_solid_scene_history")
	history.undo()
	await process_frame
	_check(solid.get("data") == before_data and solid.get("materials") == before_mats,
		"undo_restores_exact_face_data_and_material_array")
	_check(actions.material_slot == before_slot, "undo_restores_active_material_slot")
	history.redo()
	await process_frame
	var redone_mats: Array = solid.get("materials")
	_check(solid.get("data") == after_data and redone_mats.size() == 2 and redone_mats[1] == imported,
		"redo_restores_exact_face_data_and_shared_resource_identity")
	_check(actions.material_slot == 1, "redo_restores_imported_active_slot")

	# Native selection begins on another solid, then an actual 3D paint click
	# must move both selection and Undo ownership to the hit solid.
	var other: Node3D = editor.get_edited_scene_root().get_node("Box")
	var native_selection: Object = editor.get_selection()
	native_selection.clear()
	native_selection.add_node(other)
	editor.edit_node(other)
	await process_frame
	paint.enter()
	actions.material_slot = 1
	var viewport: SubViewport = editor.get_editor_viewport_3d(0)
	var camera: Camera3D = viewport.get_camera_3d()
	var hit_face: int = 0
	var hit_world := Vector3.ZERO
	for candidate in faces:
		var world: Vector3 = solid.to_global(solid.call("face_centroid", candidate))
		var normal: Vector3 = (solid.global_transform.basis.inverse().transposed() * solid.call("face_normal", candidate)).normalized()
		if normal.dot(camera.global_position - world) > 0.1 and not camera.is_position_behind(world):
			hit_face = candidate
			hit_world = world
			break
	_check(hit_face != 0, "cross_solid_fixture_has_a_visible_face")
	solid.call("set_face_material", PackedInt64Array([hit_face]), 0)
	var cross_before_data: PackedByteArray = solid.get("data")
	var cross_before_mats: Array = (solid.get("materials") as Array).duplicate()
	var surface: Control = _surface(viewport.get_parent().get_parent())
	surface.grab_focus()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(hit_world)
	click.global_position = click.position
	plugin.call("_forward_3d_gui_input", camera, click)
	click = click.duplicate()
	click.pressed = false
	plugin.call("_forward_3d_gui_input", camera, click)
	await create_timer(0.3).timeout
	_check(solid.get("data") != cross_before_data, "cross_solid_viewport_paint_changes_the_hit_solid")
	_check(native_selection.get_selected_nodes() == [solid], "cross_solid_paint_focuses_its_native_undo_owner")
	var cross_history := manager.get_history_undo_redo(manager.get_object_history_id(solid))
	cross_history.undo()
	await create_timer(0.5).timeout
	_check(solid.get("data") == cross_before_data and solid.get("materials") == cross_before_mats,
		"cross_solid_paint_is_undoable_in_the_new_native_target_history")
	print("PAINT_MATERIAL_PICK_EDITOR failures=", failures)
	quit(1 if failures else 0)
