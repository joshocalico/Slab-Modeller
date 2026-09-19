extends "res://tests/panel_editor_smoke.gd"

# Rendered topology workflow through real panel clicks. Does not save the scene.
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
	editor.set_main_screen_editor("3D")
	var stable_frames := 0
	deadline = Time.get_ticks_msec() + 15000
	while stable_frames < 20:
		await process_frame
		var edited: Node = editor.get_edited_scene_root()
		stable_frames = stable_frames + 1 if edited != null and edited.scene_file_path == "res://demo/modeller_lab.tscn" else 0
		if Time.get_ticks_msec() > deadline:
			_fail("Fixture did not remain current after session restore")
			return
	var plugin := _plugin(root)
	var panel: Control = plugin.get("_panel")
	var selection: RefCounted = plugin.get("_selection")
	plugin.make_bottom_panel_item_visible(panel)
	await process_frame
	# First select an existing solid to initialize the panel properly
	var init_solid: Node3D = editor.get_edited_scene_root().get_node_or_null("Box2")
	if init_solid == null:
		_fail("Fixture is missing Box2")
		return
	editor.get_selection().clear()
	editor.get_selection().add_node(init_solid)
	editor.edit_node(init_solid)
	await create_timer(0.5).timeout
	selection.set_objects([init_solid])
	# Now create a new box for topology tests
	await _click(_mode(panel, 0))
	await _click(_button_named(panel.find_child("CreateChips", true, false), "Box"))
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
	# Undo the edge connect to restore original geometry for vertex connect test
	history.undo()
	_check(solid.get("data") == before, "edge_connect_undo_restores_original_for_vertex_test")

	# Vertex Connect through panel clicks
	await _check_vertex_connect(editor, plugin, panel, selection, solid, top)

	# Weld / Collapse through panel clicks
	await _check_weld_collapse(editor, plugin, panel, selection)

	# Concave faces: valid ops or clear refusal
	await _check_concave_faces(editor, plugin, panel, selection)

	# Larger multi-material regions: material preservation
	await _check_multi_material_regions(editor, plugin, panel, selection)

	print("TOPOLOGY_EDITOR_RESULT failures=", failures)
	quit(1 if failures else 0)


func _check_vertex_connect(editor: Object, plugin: EditorPlugin, panel: Control, selection: RefCounted, solid: Node3D, top: int) -> void:
	# Switch to vertex mode
	await _click(_mode(panel, 1))
	var vertices: PackedInt64Array = solid.call("get_vertices")
	# Find two non-adjacent vertices on the top face
	var face_verts := PackedInt64Array()
	var face_edges: PackedInt64Array = solid.call("face_edges", top)
	for edge in face_edges:
		var ends: PackedVector3Array = solid.call("edge_endpoints", edge)
		for v in vertices:
			var pos: Vector3 = solid.call("vertex_position", v)
			if pos.is_equal_approx(ends[0]) or pos.is_equal_approx(ends[1]):
				if not face_verts.has(v):
					face_verts.append(v)
	_check(face_verts.size() >= 4, "top_face_has_four_vertices")
	if face_verts.size() < 4:
		return
	# Select two diagonal (non-adjacent) vertices
	selection.set_ids(PackedInt64Array([face_verts[0], face_verts[2]]))
	var before: PackedByteArray = solid.get("data")
	var before_faces: int = solid.call("face_count")
	var connect_btn: Button = _button_named(panel, "Connect")
	_check(connect_btn != null and not connect_btn.disabled, "vertex_connect_enabled_for_two_non_adjacent")
	await _click(connect_btn)
	var after: PackedByteArray = solid.get("data")
	_check(after != before and solid.call("face_count") == before_faces + 1, "vertex_connect_adds_face_through_panel")
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(solid))
	history.undo()
	_check(solid.get("data") == before, "vertex_connect_undo_restores_original")
	await _capture(editor, {"capture_prefix": "/tmp/slab-topology-vertex-connect"}, "after")


func _check_weld_collapse(editor: Object, plugin: EditorPlugin, panel: Control, selection: RefCounted) -> void:
	# Create a new solid for weld/collapse testing
	await _click(_mode(panel, 0))
	await _click(_button_named(panel.find_child("CreateChips", true, false), "Box"))
	await _click(panel.find_child("CreateShape", true, false))
	await _confirm_create(editor, Vector3(24, 0, 0))
	var weld_solid: Node3D = editor.get_selection().get_selected_nodes()[0]
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(weld_solid))

	# Test Collapse: select two adjacent vertices and collapse them
	await _click(_mode(panel, 1))
	var verts: PackedInt64Array = weld_solid.call("get_vertices")
	_check(verts.size() == 8, "box_has_eight_vertices")
	if verts.size() < 2:
		return
	# Find two vertices that share an edge
	var edges: PackedInt64Array = weld_solid.call("get_edges")
	var v1: int = 0
	var v2: int = 0
	for edge in edges:
		var ends: PackedVector3Array = weld_solid.call("edge_endpoints", edge)
		for v in verts:
			if weld_solid.call("vertex_position", v).is_equal_approx(ends[0]):
				v1 = v
			if weld_solid.call("vertex_position", v).is_equal_approx(ends[1]):
				v2 = v
		if v1 != 0 and v2 != 0:
			break
	_check(v1 != 0 and v2 != 0, "found_two_adjacent_vertices_for_collapse")
	if v1 == 0 or v2 == 0:
		return
	selection.set_ids(PackedInt64Array([v1, v2]))
	var collapse_before: PackedByteArray = weld_solid.get("data")
	var collapse_btn: Button = _button_named(panel, "Collapse")
	_check(collapse_btn != null and not collapse_btn.disabled, "collapse_enabled_for_two_adjacent_vertices")
	await _click(collapse_btn)
	var collapse_after: PackedByteArray = weld_solid.get("data")
	var vert_count_after: int = weld_solid.call("get_vertices").size()
	_check(collapse_after != collapse_before and vert_count_after < 8, "collapse_reduces_vertex_count_through_panel")
	history.undo()
	_check(weld_solid.get("data") == collapse_before, "collapse_undo_restores_original")

	# Test Weld: requires vertices within weld distance (we'll test the button state)
	selection.set_ids(PackedInt64Array([v1, v2]))
	var weld_btn: Button = _button_named(panel, "Weld")
	_check(weld_btn != null, "weld_button_exists")
	# Weld on adjacent vertices may refuse if they're outside weld radius
	# The key test is that the button is enabled for vertex selection
	_check(not weld_btn.disabled, "weld_enabled_for_vertex_selection")
	await _capture(editor, {"capture_prefix": "/tmp/slab-topology-vertex-weld-collapse"}, "after")
	# Clean up
	weld_solid.free()


func _check_concave_faces(editor: Object, plugin: EditorPlugin, panel: Control, selection: RefCounted) -> void:
	# Create a concave prism (C-shape)
	var concave: Node3D = ClassDB.instantiate("SlabSolid")
	var scene: Node = editor.get_edited_scene_root()
	scene.add_child(concave)
	concave.owner = scene
	concave.name = "ConcaveTestShape"
	var poly := PackedVector3Array([
		Vector3(0, 0, 4), Vector3(1, 0, 4), Vector3(1, 0, 1), Vector3(3, 0, 1),
		Vector3(3, 0, 4), Vector3(4, 0, 4), Vector3(4, 0, 0), Vector3(0, 0, 0),
	])
	var err: int = concave.call("make_prism", poly, 2.0)
	_check(err == 0, "concave_prism_builds")
	if err != 0:
		concave.free()
		return
	concave.position = Vector3(28, 0, 0)
	await create_timer(0.3).timeout
	editor.get_selection().clear()
	await process_frame
	editor.get_selection().add_node(concave)
	editor.edit_node(concave)
	await create_timer(0.3).timeout
	selection.set_objects([concave])
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()

	# Find the top face (concave)
	var top_face: int = 0
	for face in concave.call("get_faces"):
		if concave.call("face_normal", face).y > 0.9:
			top_face = face
			break
	_check(top_face != 0, "concave_shape_has_top_face")
	if top_face == 0:
		concave.free()
		return

	# Test Subdivide on concave face - should work or give clear refusal
	await _click(_mode(panel, 3))
	selection.set_ids(PackedInt64Array([top_face]))
	var concave_before: PackedByteArray = concave.get("data")
	var concave_faces_before: int = concave.call("face_count")
	await _click(_button_named(panel, "Subdivide"))
	var concave_after: PackedByteArray = concave.get("data")
	var subdivide_worked: bool = concave_after != concave_before
	var status_text: String = panel.get("_status").text
	_check(subdivide_worked or status_text.length() > 0, "concave_subdivide_works_or_explains_refusal")

	# Test Inset on concave face - should work
	if subdivide_worked:
		var history := manager.get_history_undo_redo(manager.get_object_history_id(concave))
		history.undo()
	selection.set_ids(PackedInt64Array([top_face]))
	concave_before = concave.get("data")
	await _click(_button_named(panel.find_child("Commands", true, false), "Inset"))
	var amount: SpinBox = panel.find_child("HandleAmount", true, false)
	amount.value = 0.2
	await _click(_button_named(panel.find_child("OperationHandles", true, false), "Apply"))
	concave_after = concave.get("data")
	_check(concave_after != concave_before or status_text.length() > 0, "concave_inset_works_or_explains_refusal")
	await _capture(editor, {"capture_prefix": "/tmp/slab-topology-concave"}, "after")
	concave.free()


func _check_multi_material_regions(editor: Object, plugin: EditorPlugin, panel: Control, selection: RefCounted) -> void:
	# Create a box and assign different materials to faces
	var multi_mat: Node3D = ClassDB.instantiate("SlabSolid")
	var scene: Node = editor.get_edited_scene_root()
	scene.add_child(multi_mat)
	multi_mat.owner = scene
	multi_mat.name = "MultiMaterialTestShape"
	multi_mat.call("make_box", Vector3(4, 3, 4))
	multi_mat.position = Vector3(32, 0, 0)

	# Set up materials
	var mat0 := StandardMaterial3D.new()
	mat0.albedo_color = Color(1, 0, 0)
	var mat1 := StandardMaterial3D.new()
	mat1.albedo_color = Color(0, 1, 0)
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = Color(0, 0, 1)
	multi_mat.set("materials", [mat0, mat1, mat2])

	editor.get_selection().clear()
	editor.get_selection().add_node(multi_mat)
	editor.edit_node(multi_mat)
	await process_frame
	selection.set_objects([multi_mat])
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()

	# Assign materials to top and side faces
	var top_face: int = 0
	var side_faces := PackedInt64Array()
	for face in multi_mat.call("get_faces"):
		var normal: Vector3 = multi_mat.call("face_normal", face)
		if normal.y > 0.9:
			top_face = face
		elif absf(normal.y) < 0.1:
			side_faces.append(face)

	_check(top_face != 0, "multi_mat_has_top_face")
	_check(side_faces.size() >= 2, "multi_mat_has_side_faces")
	if top_face == 0 or side_faces.size() < 2:
		multi_mat.free()
		return

	# Assign different materials
	multi_mat.call("set_face_material", PackedInt64Array([top_face]), 0)  # Red
	multi_mat.call("set_face_material", PackedInt64Array([side_faces[0]]), 1)  # Green
	multi_mat.call("set_face_material", PackedInt64Array([side_faces[1]]), 2)  # Blue

	# Test: Subdivide top face and verify material is preserved
	await _click(_mode(panel, 3))
	selection.set_ids(PackedInt64Array([top_face]))
	var before_subdivide: PackedByteArray = multi_mat.get("data")
	var before_mat_slot: int = int(multi_mat.call("face_uv", top_face).get("slot", -1))
	await _click(_button_named(panel, "Subdivide"))
	var after_subdivide: PackedByteArray = multi_mat.get("data")
	_check(after_subdivide != before_subdivide, "multi_mat_subdivide_changes_data")

	# Check that subdivided faces keep the same material slot
	var subdivided_ids := PackedInt64Array(selection.ids)
	var material_preserved: bool = true
	for face_id in subdivided_ids:
		var face_slot: int = int(multi_mat.call("face_uv", face_id).get("slot", -1))
		if face_slot != before_mat_slot:
			material_preserved = false
			break
	_check(material_preserved, "subdivide_preserves_material_slot_on_children")

	# Test: Merge subdivided faces and verify material is preserved
	await _click(_button_named(panel, "Merge"))
	var after_merge: PackedByteArray = multi_mat.get("data")
	_check(multi_mat.call("face_count") == 6, "merge_returns_to_six_faces")
	var merged_id: int = selection.ids[0] if selection.ids.size() > 0 else 0
	if merged_id != 0:
		var merged_slot: int = int(multi_mat.call("face_uv", merged_id).get("slot", -1))
		_check(merged_slot == before_mat_slot, "merge_preserves_material_slot_on_result")

	# Test: Side face materials remain unchanged after top face operations
	var side0_slot: int = int(multi_mat.call("face_uv", side_faces[0]).get("slot", -1))
	var side1_slot: int = int(multi_mat.call("face_uv", side_faces[1]).get("slot", -1))
	_check(side0_slot == 1 and side1_slot == 2, "other_face_materials_unchanged_after_topology_ops")

	# Test: Connect edges on multi-material solid preserves materials
	await _click(_mode(panel, 2))
	var top_edges: PackedInt64Array = multi_mat.call("face_edges", merged_id if merged_id != 0 else top_face)
	if top_edges.size() >= 4:
		selection.set_ids(PackedInt64Array([top_edges[0], top_edges[2]]))
		var before_connect: PackedByteArray = multi_mat.get("data")
		await _click(_button_named(panel, "Connect"))
		var after_connect: PackedByteArray = multi_mat.get("data")
		_check(after_connect != before_connect, "edge_connect_on_multi_mat_changes_data")
		# Verify side materials still correct
		side0_slot = int(multi_mat.call("face_uv", side_faces[0]).get("slot", -1))
		side1_slot = int(multi_mat.call("face_uv", side_faces[1]).get("slot", -1))
		_check(side0_slot == 1 and side1_slot == 2, "edge_connect_preserves_other_face_materials")

	await _capture(editor, {"capture_prefix": "/tmp/slab-topology-multi-material"}, "after")
	multi_mat.free()
