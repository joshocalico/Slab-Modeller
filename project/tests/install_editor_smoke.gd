extends "res://tests/panel_editor_smoke.gd"

# Runs only in the disposable project created by scripts/slab-install-verify.
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
	if "reopen" in OS.get_cmdline_user_args():
		var solid := scene.get_node_or_null("Box")
		_check(solid != null and solid.is_class("SlabSolid"), "saved_solid_reopens_with_addon_only")
		if solid != null:
			_check(solid.call("face_count") == 6 and solid.call("get_local_aabb").size.is_equal_approx(Vector3(6, 1, 6)), "saved_dimensions_and_topology_survive")
			var bodies := solid.find_children("*", "CollisionShape3D", true, false)
			_check(not bodies.is_empty() and bodies[0].shape is ConcavePolygonShape3D, "reopened_solid_has_runtime_collision")
			editor.get_selection().clear()
			editor.get_selection().add_node(solid)
			editor.edit_node(solid)
			await create_timer(0.3).timeout
			await _click(_mode(panel, 3))
			_check(_button_named(panel, "Inset") != null, "reopened_solid_is_editable_in_panel")
	else:
		_check(scene.get_child_count() == 0, "fresh_project_starts_without_demo_dependencies")
		await _click(_mode(panel, 0))
		await _click(_button_named(panel.find_child("Commands", true, false), "Box"))
		for entry in [["size_x", 6.0], ["size_y", 1.0], ["size_z", 6.0]]:
			var spin: SpinBox = panel.find_child(entry[0], true, false).find_children("*", "SpinBox", true, false)[0]
			spin.value = entry[1]
		await process_frame
		await _click(panel.find_child("CreateShape", true, false))
		await _confirm_create(editor, Vector3.ZERO)
		_check(scene.get_child_count() == 1 and scene.get_child(0).is_class("SlabSolid"), "create_works_in_clean_project")
		_check(editor.save_scene() == OK, "authored_scene_saves")
	await _capture(editor, {"capture_prefix": OS.get_environment("SLAB_INSTALL_CAPTURE")}, "after")
	print("INSTALL_EDITOR_RESULT failures=", failures)
	quit(1 if failures else 0)
