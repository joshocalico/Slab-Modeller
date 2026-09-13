extends "res://tests/panel_editor_smoke.gd"

# Rendered topology workflow through real panel clicks. Does not save the scene.
func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("Requires --editor")
		return
	var editor := Engine.get_singleton("EditorInterface")
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		await process_frame
	editor.open_scene_from_path("res://demo/modeller_lab.tscn")
	editor.set_main_screen_editor("3D")
	while editor.get_edited_scene_root() == null or editor.get_edited_scene_root().scene_file_path != "res://demo/modeller_lab.tscn":
		await process_frame
	await create_timer(1.0).timeout
	var plugin := _plugin(root)
	var panel: Control = plugin.get("_panel")
	var selection: RefCounted = plugin.get("_selection")
	await _click(_mode(panel, 0))
	await _click(_button_named(panel.find_child("Commands", true, false), "Box"))
	await _click(panel.find_child("CreateShape", true, false))
	await _confirm_create(editor, Vector3(20, 0, 0))
	var solid: Node3D = editor.get_selection().get_selected_nodes()[0]
	# Separate the fixture from existing lab geometry before visual inspection.
	var viewport: SubViewport = editor.get_editor_viewport_3d(0)
	var surface: Control = _surface(viewport.get_parent().get_parent())
	surface.grab_focus()
	var frame := InputEventKey.new()
	frame.keycode = KEY_F
	frame.physical_keycode = KEY_F
	frame.pressed = true
	surface.get_viewport().push_input(frame)
	await create_timer(0.5).timeout
	await _click(_mode(panel, 3))
	var top := 0
	var side := 0
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9: top = face
		if solid.call("face_normal", face).x > 0.9: side = face
	selection.set_ids(PackedInt64Array([top]))
	var before: PackedByteArray = solid.get("data")
	await _click(_button_named(panel, "Subdivide"))
	var split: PackedByteArray = solid.get("data")
	var split_ids := PackedInt64Array(selection.ids)
	_check(split_ids.size() == 4 and solid.call("face_count") == 9, "subdivide_selects_four_output_faces")
	await _capture(editor, {"capture_prefix": "/tmp/slab-topology-subdivide"}, "after")
	await _capture(editor, {"capture_prefix": "/tmp/slab-topology-face-panel", "capture_rect": panel.get_global_rect()}, "after")
	await _click(_button_named(panel, "Merge"))
	_check(solid.call("face_count") == 6 and selection.ids.size() == 1, "merge_continues_from_subdivide_selection")
	var merged: PackedByteArray = solid.get("data")
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(solid))
	history.undo()
	_check(solid.get("data") == split and selection.ids == split_ids, "merge_undo_restores_region_selection")
	history.redo()
	_check(solid.get("data") == merged and selection.ids.size() == 1, "merge_redo_restores_result_selection")
	selection.set_ids(PackedInt64Array([selection.ids[0], side]))
	await _click(_button_named(panel, "Merge"))
	_check(solid.get("data") == merged and panel.get("_status").text.contains("flat surface"), "folded_merge_refusal_explains_recovery")
	history.undo()
	history.undo()
	_check(solid.get("data") == before, "topology_undo_returns_original_box")
	await _click(_mode(panel, 2))
	var edges: PackedInt64Array = solid.call("face_edges", top)
	selection.set_ids(PackedInt64Array([edges[0], edges[1], edges[2]]))
	_check(_button_named(panel, "Connect").disabled, "three_edges_disable_connect")
	selection.set_ids(PackedInt64Array([edges[0], edges[2]]))
	await _click(_button_named(panel, "Connect"))
	var cut: PackedByteArray = solid.get("data")
	var cut_ids := PackedInt64Array(selection.ids)
	_check(solid.call("face_count") == 7 and cut_ids.size() == 1, "connect_selects_new_cut")
	await _click(_button_named(panel, "Dissolve"))
	_check(solid.call("face_count") == 6 and selection.ids.is_empty(), "dissolve_clears_removed_edge_selection")
	history.undo()
	_check(solid.get("data") == cut and selection.ids == cut_ids, "dissolve_undo_restores_selected_cut")
	await _capture(editor, {"capture_prefix": "/tmp/slab-topology-edge-panel", "capture_rect": panel.get_global_rect()}, "after")
	print("TOPOLOGY_EDITOR_RESULT failures=", failures)
	quit(1 if failures else 0)
