extends "res://tests/panel_editor_smoke.gd"

# Runs only in the disposable project created by scripts/slab-install-verify.
# Exercises first-use workflow: create box → room tutorial (inset/extrude) → save → reopen.
func _run() -> void:
	if not Engine.is_editor_hint() or ProjectSettings.get_setting("application/config/name") != "Slab install acceptance":
		_fail("Requires the disposable installation project")
		return
	var editor := Engine.get_singleton("EditorInterface")
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		await process_frame
	editor.open_scene_from_path("res://main.tscn")
	editor.set_main_screen_editor("3D")
	while editor.get_edited_scene_root() == null or editor.get_edited_scene_root().scene_file_path != "res://main.tscn":
		await process_frame
	await create_timer(0.5).timeout
	var scene: Node = editor.get_edited_scene_root()
	var panel: Control = _plugin(root).get("_panel")
	var selection: RefCounted = _plugin(root).get("_selection")
	if "reopen" in OS.get_cmdline_user_args():
		await _reopen_room_tutorial(editor, scene, panel, selection)
	else:
		await _create_room_tutorial(editor, scene, panel, selection)
	await _capture(editor, {"capture_prefix": OS.get_environment("SLAB_INSTALL_CAPTURE")}, "after")
	print("INSTALL_EDITOR_RESULT failures=", failures)
	quit(1 if failures else 0)


func _create_room_tutorial(editor: Object, scene: Node, panel: Control, selection: RefCounted) -> void:
	_check(scene.get_child_count() == 0, "fresh_project_starts_without_demo_dependencies")
	await _click(_mode(panel, 0))
	await _click(_button_named(panel.find_child("CreateChips", true, false), "Box"))
	for entry in [["size_x", 4.0], ["size_y", 3.0], ["size_z", 4.0]]:
		var spin: SpinBox = panel.find_child(entry[0], true, false).find_children("*", "SpinBox", true, false)[0]
		spin.value = entry[1]
		spin.get_line_edit().release_focus()
	await process_frame
	var create_btn: Button = panel.find_child("CreateShape", true, false)
	await _click(create_btn)
	await _confirm_create(editor, Vector3.ZERO)
	var native_selection: Object = editor.get_selection()
	var selected: Array[Node] = native_selection.get_selected_nodes()
	for i in 30:
		if not selected.is_empty() and scene.get_child_count() > 0:
			break
		await process_frame
		selected = native_selection.get_selected_nodes()
	_check(scene.get_child_count() == 1 and scene.get_child(0).is_class("SlabSolid"), "create_works_in_clean_project")
	if scene.get_child_count() == 0:
		_fail("No solid created; cannot proceed with room tutorial")
		_check(editor.save_scene() == OK, "authored_scene_saves")
		return
	var room: Node3D = scene.get_child(0)
	room.name = "Room"
	_check(room.call("get_local_aabb").size.is_equal_approx(Vector3(4, 3, 4)), "tutorial_creates_4_by_3_by_4_box")
	await _click(_mode(panel, 3))
	var top: int = 0
	for id in room.call("get_faces"):
		if room.call("face_normal", id).y > 0.9:
			top = int(id)
	selection.set_ids(PackedInt64Array([top]))
	await create_timer(0.2).timeout
	var preview: Control = panel.find_child("OperationHandles", true, false)
	var amount: SpinBox = panel.find_child("HandleAmount", true, false)
	await _click(_button_named(panel.find_child("Commands", true, false), "Inset"))
	amount.value = 0.45
	await _click(_button_named(preview, "Apply"))
	var inset_data: PackedByteArray = room.get("data")
	_check(selection.ids.size() == 1, "inset_keeps_inner_cap_selected")
	await _click(_button_named(panel.find_child("Commands", true, false), "Extrude"))
	amount.value = -2.4
	await _click(_button_named(preview, "Apply"))
	_check(room.get("data") != inset_data, "extrude_commits_room")
	_check(room.call("face_count") == 14, "room_has_14_faces_after_inset_extrude")
	var floor_face: int = int(selection.ids[0]) if selection.ids.size() > 0 else 0
	if floor_face != 0:
		var floor_y: float = room.call("face_centroid", floor_face).y
		_check(absf(floor_y - 0.6) < 0.01, "room_floor_at_0_6_metres")
	var bodies := room.find_children("*", "CollisionShape3D", true, false)
	_check(not bodies.is_empty() and bodies[0].shape is ConcavePolygonShape3D, "room_has_runtime_collision_before_save")
	if not bodies.is_empty() and bodies[0].shape is ConcavePolygonShape3D:
		var tri_count: int = bodies[0].shape.get_faces().size() / 3
		_check(tri_count >= 24, "room_collision_has_expected_triangles")
	_check(editor.save_scene() == OK, "authored_scene_saves")


func _reopen_room_tutorial(editor: Object, scene: Node, panel: Control, selection: RefCounted) -> void:
	var solid := scene.get_node_or_null("Room")
	_check(solid != null and solid.is_class("SlabSolid"), "saved_room_reopens_with_addon_only")
	if solid == null:
		return
	_check(solid.call("face_count") == 14, "reopened_room_has_14_faces")
	var bounds: AABB = solid.call("get_local_aabb")
	_check(bounds.size.x > 3.9 and bounds.size.x < 4.1, "reopened_room_width_approx_4")
	_check(bounds.size.y > 2.9 and bounds.size.y < 3.1, "reopened_room_height_approx_3")
	_check(bounds.size.z > 3.9 and bounds.size.z < 4.1, "reopened_room_depth_approx_4")
	var floor_face: int = 0
	for id in solid.call("get_faces"):
		var centroid: Vector3 = solid.call("face_centroid", id)
		if centroid.y > 0.5 and centroid.y < 0.7:
			floor_face = int(id)
			break
	_check(floor_face != 0, "reopened_room_has_floor_face_near_0_6m")
	var bodies := solid.find_children("*", "CollisionShape3D", true, false)
	_check(not bodies.is_empty() and bodies[0].shape is ConcavePolygonShape3D, "reopened_room_has_runtime_collision")
	if not bodies.is_empty() and bodies[0].shape is ConcavePolygonShape3D:
		var tri_count: int = bodies[0].shape.get_faces().size() / 3
		_check(tri_count >= 24, "reopened_collision_has_expected_triangles")
	editor.get_selection().clear()
	editor.get_selection().add_node(solid)
	editor.edit_node(solid)
	await create_timer(0.3).timeout
	await _click(_mode(panel, 3))
	selection.set_objects([solid])
	if floor_face != 0:
		selection.set_ids(PackedInt64Array([floor_face]))
	await create_timer(0.2).timeout
	_check(_button_named(panel.find_child("Commands", true, false), "Inset") != null, "reopened_room_is_editable_in_panel")
	_check(_button_named(panel.find_child("Commands", true, false), "Extrude") != null, "reopened_room_has_extrude_command")
