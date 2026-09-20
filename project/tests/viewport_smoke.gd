extends SceneTree

const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabTopology := preload("res://addons/slab/slab_topology.gd")
const SlabTestHost := preload("res://tests/slab_test_host.gd")
const SlabTestWorld := preload("res://tests/slab_test_world.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")
const SlabXform := preload("res://addons/slab/slab_element_xform.gd")

const VOID := Vector2(20000.0, 20000.0)
const FAR := 40.0
const NUDGE := 1.0

var _world: SlabTestWorld
var _host: SlabTestHost
var _session: SlabViewport
var _fails := 0
var _ran := 0
var _frames := 0


func case_scaled_sloped_face_anchor_stays_on_its_surface() -> void:
	var box: Node3D = _world.box()
	var original_transform := box.transform
	var face: int = _world.top_face(box)
	var ring: PackedInt64Array = box.face_vertices(face)
	var raised := PackedInt64Array()
	for vertex in ring:
		if box.vertex_position(vertex).x > 1.0:
			raised.append(vertex)
	expect(box.move_vertices(raised, Vector3.UP) == OK, "sloped test face commits")
	box.rotation = Vector3(0.3, 0.4, 0.2)
	box.scale = Vector3(2.0, 0.5, 1.5)
	var a: Vector3 = box.to_global(box.vertex_position(ring[0]))
	var b: Vector3 = box.to_global(box.vertex_position(ring[1]))
	var c: Vector3 = box.to_global(box.vertex_position(ring[2]))
	var normal: Vector3 = SlabViewport._world_normal(box, face)
	expect(absf(normal.dot((b - a).normalized())) < 0.00001
		and absf(normal.dot((c - a).normalized())) < 0.00001,
		"face interaction normal stays perpendicular under nonuniform scale")
	var point := a * 0.7 + b * 0.2 + c * 0.1
	var camera := _world.camera()
	var anchor: Vector3 = SlabViewport._face_anchor(camera, camera.unproject_position(point), box, face, normal)
	expect(anchor.distance_to(point) < 0.0001,
		"off-centre face press anchors on the rendered surface under nonuniform scale")
	box.transform = original_transform


func case_native_escape_preserves_selection_and_passes_to_godot() -> void:
	var box: Node3D = _world.box()
	_select(box, SlabSelection.Mode.FACE)
	var ids := PackedInt64Array([_world.top_face(box)])
	_session.state().set_ids(ids)
	_session.handle(_world.camera(), _world.click(VOID))
	var verdict: int = _session.handle(_world.camera(), _world.key(KEY_ESCAPE))
	expect(verdict == SlabViewport.Verdict.PASS, "native Escape reaches Godot")
	expect(_session.state().mode == SlabSelection.Mode.FACE, "native Escape preserves element mode")
	_session.handle(_world.camera(), _world.release(VOID))
	expect(_session.state().ids == ids, "cancelled native release preserves selection")


func case_xray_cycle_hover_matches_click() -> void:
	var box: Node3D = _world.box()
	_select(box, SlabSelection.Mode.FACE)
	var screen: Vector2 = _world.at_face(box, _world.top_face(box))
	_session.state().set_xray(true)
	_session.handle(_world.camera(), _world.motion(screen))
	var first: int = _session.state().hover_id
	var verdict: int = _session.handle(_world.camera(), _world.key(KEY_TAB))
	var second: int = _session.state().hover_id
	expect(verdict == SlabViewport.Verdict.STOP and first != 0 and second != first,
		"Tab cycles the hovered face to an occluded candidate in X-ray")
	_session.handle(_world.camera(), _world.click(screen))
	expect(_session.state().ids == PackedInt64Array([second]), "click selects exactly the cycled hover candidate")
	_session.state().set_xray(false)
	_session.handle(_world.camera(), _world.motion(screen))
	expect(_session.state().hover_id == first, "visible-only resets the cycle to the visible face")


func case_operation_handle_exact_apply_and_cancel() -> void:
	var box: Node3D = _world.box()
	_select(box, SlabSelection.Mode.FACE)
	_session.state().set_ids(PackedInt64Array([_world.top_face(box)]))
	var actions := preload("res://addons/slab/slab_actions.gd").new(_session.state())
	_session.bind_actions(actions)
	var before: PackedByteArray = box.get("data")
	var committed_mesh := box.call("build_mesh") as ArrayMesh
	var committed_bounds: AABB = committed_mesh.get_aabb()
	var shape_before: Shape3D = box.get_node("__body/__shape").shape
	actions.operation_requested.emit(0)
	actions.operation_amount_changed.emit(0.375)
	expect(actions.operation_active and box.get("data") == before, "handle exact amount previews without mutating the solid")
	expect(bool(box.call("has_display_preview")), "a valid operation displays its rendered result")
	expect(not (box.get_node("Mesh").mesh as ArrayMesh).get_aabb().is_equal_approx(committed_bounds),
		"rendered operation result differs from the opaque committed solid")
	expect((box.call("build_mesh") as ArrayMesh).get_aabb().is_equal_approx(committed_bounds),
		"public mesh export remains committed geometry during a display preview")
	expect(box.call("build_mesh") == committed_mesh, "display preview preserves the cached committed mesh identity")
	expect(box.get_node("__body/__shape").shape == shape_before,
		"display preview leaves collision identity unchanged")
	expect(_session.state().operation_preview.get("label", "").contains("0.375"), "handle label shows the exact amount")
	actions.operation_cancel_requested.emit()
	expect(not actions.operation_active and box.get("data") == before and not bool(box.call("has_display_preview")),
		"handle cancel restores the committed display and preserves original data")
	expect((box.get_node("Mesh").mesh as ArrayMesh).get_aabb().is_equal_approx(committed_bounds),
		"cancel restores the committed rendered solid")
	expect(box.get_node("Mesh").mesh == committed_mesh and box.call("build_mesh") == committed_mesh,
		"cancel restores the original committed mesh resource")
	actions.operation_requested.emit(0)
	actions.operation_amount_changed.emit(-100.0)
	expect(not bool(box.call("has_display_preview"))
		and (box.get_node("Mesh").mesh as ArrayMesh).get_aabb().is_equal_approx(committed_bounds),
		"an invalid result restores the committed rendered solid")
	actions.operation_amount_changed.emit(0.375)
	expect(bool(box.call("has_display_preview")), "a valid result redisplays after invalidation")
	actions.operation_apply_requested.emit()
	expect(not actions.operation_active and box.get("data") != before, "handle Apply commits preview and exits modal state")
	expect(not _session.state().ids.is_empty(), "handle Apply retains cap selection")


func case_operation_distances_are_remembered_per_tool() -> void:
	var box: Node3D = _world.box()
	var undo := SlabTestUndo.new()
	_host.stub_undo(undo)
	_select(box, SlabSelection.Mode.FACE)
	_session.state().set_ids(PackedInt64Array([_world.top_face(box)]))
	var actions := preload("res://addons/slab/slab_actions.gd").new(_session.state())
	_session.bind_actions(actions)
	var before: PackedByteArray = box.get("data")

	actions.operation_requested.emit(0)
	actions.operation_amount_changed.emit(-0.4)
	actions.operation_cancel_requested.emit()
	expect(box.get("data") == before and is_equal_approx(actions.extrude_amount, -0.4),
		"cancel preserves geometry while remembering Extrude distance")
	actions.operation_requested.emit(1)
	expect(is_equal_approx(actions.operation_amount, 0.5), "Inset opens at its independent default")
	actions.operation_amount_changed.emit(0.2)
	actions.operation_cancel_requested.emit()
	actions.operation_requested.emit(0)
	expect(is_equal_approx(actions.operation_amount, -0.4), "Extrude reopens at its own last distance")
	actions.operation_cancel_requested.emit()
	actions.operation_requested.emit(1)
	expect(is_equal_approx(actions.operation_amount, 0.2), "Inset reopens at its own last distance")
	actions.operation_apply_requested.emit()
	expect(box.get("data") != before, "remembered Inset distance applies normally")
	undo.undo()
	expect(box.get("data") == before and is_equal_approx(actions.inset_amount, 0.2),
		"undo restores geometry without rewinding session distance")

	_select(box, SlabSelection.Mode.EDGE)
	_session.state().set_ids(PackedInt64Array([box.call("get_edges")[0]]))
	actions.operation_requested.emit(2)
	expect(is_equal_approx(actions.operation_amount, 0.5), "Bevel keeps an independent default width")
	actions.operation_amount_changed.emit(0.1)
	actions.operation_cancel_requested.emit()
	expect(is_equal_approx(actions.bevel_amount, 0.1) and is_equal_approx(actions.amount, 0.5),
		"Bevel remembers its width without changing Weld distance")


func case_boolean_swap_updates_order_in_slab_and_host_selection() -> void:
	var target: Node3D = _world.box()
	var cutter: Node3D = _world.other()
	_host.stub_host_selection([target, cutter])
	_session.adopt_host_selection()
	var actions := preload("res://addons/slab/slab_actions.gd").new(_session.state())
	_session.bind_actions(actions)
	actions.swap_boolean_operands()
	expect(_session.state().objects == [cutter, target], "Swap makes the second selected solid the Boolean target")
	expect(_host.selected_nodes() == [cutter, target], "Swap keeps native host selection in the same operand order")


func case_empty_selection_first_click_selects_the_solid() -> void:
	var box: Node3D = _world.box()
	expect(_host.selected_nodes().is_empty(), "the editor selection starts empty")

	var verdict: int = _session.handle(_world.camera(), _world.click(_world.at_face(box, _world.top_face(box))))

	expect(verdict == SlabViewport.Verdict.CUSTOM, "the very first click is claimed by Slab")
	expect(_host.focused() == box, "the first click focuses the solid, got %s" % _host.focused())


func case_empty_space_click_keeps_slab_authority() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.FACE
	_session.state().set_ids(PackedInt64Array([_world.top_face(box)]))

	var verdict: int = _session.handle(_world.camera(), _world.click(VOID))
	var release: int = _session.handle(_world.camera(), _world.release(VOID))

	expect(verdict == SlabViewport.Verdict.CUSTOM, "a miss with a solid selected stays inside Slab")
	expect(release == SlabViewport.Verdict.CUSTOM, "a plain miss clears when the click completes")
	expect(_session.state().ids.is_empty(), "the miss clears the element selection")
	expect(_host.commands().is_empty(), "a miss never touches the editor selection")


func case_native_gizmo_drag_preserves_element_selection() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.FACE
	var face: int = _world.top_face(box)
	_session.state().set_ids(PackedInt64Array([face]))
	var press := _world.at_face(box, face)
	var verdict := _session.handle(_world.camera(), _world.click(press))
	var motion := _world.motion(press + Vector2(24, 0))
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	var drag_verdict := _session.handle(_world.camera(), motion)
	var release := _session.handle(_world.camera(), _world.release(press + Vector2(24, 0)))
	expect(verdict == SlabViewport.Verdict.PASS and drag_verdict == SlabViewport.Verdict.PASS and release == SlabViewport.Verdict.PASS,
		"a miss that becomes a drag is delegated to Godot's native gizmo")
	expect(_session.state().ids == PackedInt64Array([face]), "native gizmo drag preserves the selected elements")


func case_native_gizmo_drag_preserves_selection_over_pickable_geometry() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.FACE
	var selected: int = _world.top_face(box)
	_session.state().set_ids(PackedInt64Array([selected]))
	var press := _world.at_face(box, selected)
	_session.handle(_world.camera(), _world.motion(press))
	expect(_session.state().hover_id != 0, "test finds pickable geometry beneath the native pivot handle")
	var verdict := _session.handle(_world.camera(), _world.click(press))
	var motion := _world.motion(press + Vector2(24, 0))
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	var drag_verdict := _session.handle(_world.camera(), motion)
	var release := _session.handle(_world.camera(), _world.release(press + Vector2(24, 0)))
	expect(verdict == SlabViewport.Verdict.PASS and drag_verdict == SlabViewport.Verdict.PASS and release == SlabViewport.Verdict.PASS,
		"a drag over pickable geometry remains available to the native gizmo")
	expect(_session.state().ids == PackedInt64Array([selected]), "geometry beneath a native handle does not replace the transformed selection")


func case_empty_space_click_with_nothing_selected_passes() -> void:
	_session.state().mode = SlabSelection.Mode.FACE

	var verdict: int = _session.handle(_world.camera(), _world.click(VOID))

	expect(verdict == SlabViewport.Verdict.PASS, "with nothing selected a miss leaves the viewport alone")


func case_object_mode_selects_the_solid_not_its_mesh_child() -> void:
	var box: Node3D = _world.box()
	_session.state().mode = SlabSelection.Mode.OBJECT

	var verdict: int = _session.handle(_world.camera(), _world.click(_world.at_face(box, _world.top_face(box))))

	expect(verdict == SlabViewport.Verdict.CUSTOM, "an object-mode hit is claimed by Slab")
	expect(_host.focused() == box, "the editor is handed the SlabSolid, got %s" % _host.focused())
	expect(_host.focused() != box.get_node_or_null("Mesh"), "the Mesh child never reaches the editor")


func case_host_selection_of_a_mesh_child_syncs_to_its_solid() -> void:
	var box: Node3D = _world.box()
	var mesh: Node = box.get_node_or_null("Mesh")
	expect(mesh != null, "the solid still owns a Mesh child")

	_host.stub_host_selection([mesh])
	_session.adopt_host_selection()

	expect(_session.state().solid == box, "a Mesh child in the editor selection resolves to its solid")
	expect(_session.state().objects.size() == 1, "the solid is not counted twice")


func case_edge_click_along_the_segment_not_only_the_midpoint() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var edges: PackedInt64Array = box.call("face_edges", face)
	var edge: int = edges[0]
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.EDGE

	for t in [0.3, 0.5]:
		_session.state().clear_ids()
		var verdict: int = _session.handle(_world.camera(), _world.click(_world.along_edge_on_face(box, edge, t, face)))
		expect(verdict == SlabViewport.Verdict.CUSTOM, "a click %d%% along an edge is claimed" % int(t * 100.0))
		expect(_session.state().ids == PackedInt64Array([edge]),
			"a click %d%% along the edge selects it, got %s" % [int(t * 100.0), _session.state().ids])


func case_edge_click_past_the_radius_selects_nothing() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.EDGE

	_session.handle(_world.camera(), _world.click(_world.past_pick_radius(box)))

	expect(_session.state().ids.is_empty(), "a click well outside the radius picks no edge")


func case_e_with_a_face_selected_stops() -> void:
	var box: Node3D = _world.box()
	_select(box, SlabSelection.Mode.FACE)
	var face: int = _world.top_face(box)
	_session.state().set_ids(PackedInt64Array([face]))
	var actions := preload("res://addons/slab/slab_actions.gd").new(_session.state())
	_session.bind_actions(actions)
	var before: int = box.call("face_count")

	var verdict: int = _session.handle(_world.camera(), _world.key(KEY_E))

	expect(verdict == SlabViewport.Verdict.STOP, "E is claimed so Godot Rotate does not run")
	expect(actions.operation_active and box.call("face_count") == before, "E starts a non-destructive preview")
	_session.handle(_world.camera(), _world.key(KEY_ENTER))
	expect(box.call("face_count") == before + 4, "Enter commits the extrusion")


func case_mode_key_claims_the_press_so_godot_never_sees_it() -> void:
	expect(_host.selected_nodes().is_empty(), "mode keys must stop even with nothing selected")
	for mode in SlabSelection.MODE_LABELS:
		var keycode: int = SlabModeStrip.keycode_for(mode)
		expect(keycode != 0, "mode %s declares a keycode" % mode)

		var verdict: int = _session.handle(_world.camera(), _world.key(keycode))

		expect(verdict == SlabViewport.Verdict.STOP,
			"%s's key is claimed, so numpad emulation never runs" % SlabSelection.MODE_LABELS[mode])
		expect(_session.state().mode == mode, "%s's key switches mode" % SlabSelection.MODE_LABELS[mode])


func case_command_modified_digit_passes_through_to_godot() -> void:
	for keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
		expect(_session.handle(_world.camera(), _world.key(keycode, true, false, false)) == SlabViewport.Verdict.PASS,
			"ctrl and a digit still belongs to Godot")
		expect(_session.handle(_world.camera(), _world.key(keycode, false, false, true)) == SlabViewport.Verdict.PASS,
			"cmd and a digit still belongs to Godot")
	expect(_session.state().mode == SlabSelection.Mode.OBJECT, "a modified digit did not change mode")


func case_element_click_at_the_solid_origin_still_selects() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.FACE

	var verdict: int = _session.handle(_world.camera(), _world.click(_world.at_origin(box)))

	expect(verdict == SlabViewport.Verdict.CUSTOM, "a click over the gizmo origin is claimed by Slab")
	expect(_session.state().ids.size() == 1, "a face resolves under the gizmo origin, got %s" % _session.state().ids)


func case_nearer_solid_wins_when_two_overlap_on_screen() -> void:
	var near: Node3D = _world.box()
	var far: Node3D = _world.far()
	_session.state().mode = SlabSelection.Mode.OBJECT

	_session.handle(_world.camera(), _world.click(_world.at_face(near, _world.top_face(near))))

	expect(_host.focused() == near, "the nearer solid wins, got %s" % _host.focused())
	expect(_host.focused() != far, "the far solid is not focused through the near one")


func case_shift_click_toggles_a_second_face() -> void:
	var box: Node3D = _world.box()
	var faces: PackedInt64Array = box.call("get_faces")
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.FACE

	_session.handle(_world.camera(), _world.click(_world.at_face(box, faces[0])))
	_session.handle(_world.camera(), _world.click(_world.at_face(box, faces[1]), true))

	expect(_session.state().ids.size() == 2, "shift adds a second face, got %s" % _session.state().ids)

	_session.handle(_world.camera(), _world.click(_world.at_face(box, faces[1]), true))
	expect(_session.state().ids == PackedInt64Array([faces[0]]), "shift on a selected face removes it")


func case_escape_returns_to_object_mode_and_stops() -> void:
	_session.state().mode = SlabSelection.Mode.FACE

	var verdict: int = _session.handle(_world.camera(), _world.key(KEY_ESCAPE))

	expect(verdict == SlabViewport.Verdict.STOP, "escape is claimed while Slab holds the viewport")
	expect(_session.state().mode == SlabSelection.Mode.OBJECT, "escape returns to object mode")


func case_escape_exits_face_isolation_without_clearing_soft_select() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	var selection: SlabSelection = _session.state()
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([_world.top_face(box)]))
	selection.set_soft_select(true)
	selection.enter_face_isolation()
	expect(selection.face_isolated, "entered face isolation before Escape")
	var verdict: int = _session.handle(_world.camera(), _world.key(KEY_ESCAPE))
	expect(verdict == SlabViewport.Verdict.STOP, "Escape exits Face isolation")
	expect(not selection.face_isolated, "Escape restores face visibility")
	expect(selection.soft_select, "Escape does not clear Soft Select")
	expect(selection.mode == SlabSelection.Mode.FACE, "Escape keeps Face mode")
	expect(not selection.ids.is_empty(), "Escape keeps the face selection")


func case_escape_exits_faces_without_toggling_solid_isolate() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	var selection: SlabSelection = _session.state()
	selection.enter_isolation(_world.stage())
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([_world.top_face(box)]))
	selection.set_soft_select(true)
	selection.enter_face_isolation()
	expect(selection.isolated and selection.face_isolated, "both isolate modes are on")
	var verdict: int = _session.handle(_world.camera(), _world.key(KEY_ESCAPE))
	expect(verdict == SlabViewport.Verdict.STOP, "Escape claims Face isolation first")
	expect(not selection.face_isolated, "Escape exits Faces only")
	expect(selection.isolated, "Escape does not toggle solid Isolate")
	expect(selection.soft_select, "Soft Select stays on")
	expect(selection.mode == SlabSelection.Mode.FACE, "Face mode stays after leaving Faces")
	verdict = _session.handle(_world.camera(), _world.key(KEY_ESCAPE))
	expect(verdict == SlabViewport.Verdict.STOP, "second Escape exits solid Isolate")
	expect(not selection.isolated, "solid Isolate exits on the next Escape")
	expect(selection.mode == SlabSelection.Mode.FACE, "second Escape does not drop to Object while leaving solid Isolate")


func case_changing_mode_clears_ids_and_hover() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.FACE
	_session.handle(_world.camera(), _world.motion(_world.at_face(box, _world.top_face(box))))
	expect(_session.state().hover_id != 0, "hover found a face before the mode change")

	_session.handle(_world.camera(), _world.key(SlabModeStrip.keycode_for(SlabSelection.Mode.EDGE)))

	expect(_session.state().ids.is_empty(), "the mode change cleared the face ids")
	expect(_session.state().hover_id == 0, "the mode change cleared the stale hover id")


func case_object_mode_hover_reports_the_solid_with_a_zero_id() -> void:
	var box: Node3D = _world.box()
	_session.state().mode = SlabSelection.Mode.OBJECT

	var verdict: int = _session.handle(_world.camera(), _world.motion(_world.at_face(box, _world.top_face(box))))

	expect(verdict == SlabViewport.Verdict.PASS, "hover never claims the event, orbit must survive")
	expect(_session.state().hover_solid == box, "object-mode hover names the solid")
	expect(_session.state().hover_id == 0, "object-mode hover carries no element id")


func case_gizmo_targets_include_the_node_that_stopped_being_hovered() -> void:
	var box: Node3D = _world.box()
	_session.state().mode = SlabSelection.Mode.OBJECT
	_session.handle(_world.camera(), _world.motion(_world.at_face(box, _world.top_face(box))))
	expect(_session.gizmo_targets().has(box), "the hovered solid is a redraw target")

	_session.handle(_world.camera(), _world.motion(VOID))

	expect(_session.gizmo_targets().has(box),
		"the solid that stopped being hovered is redrawn once more, or its outline sticks")
	_session.handle(_world.camera(), _world.motion(VOID))
	expect(not _session.gizmo_targets().has(box), "and then it drops out of the redraw set")


func case_gizmo_targets_tolerate_a_freed_selected_solid() -> void:
	var hub: Node3D = _world.add_solid("Hub", Vector3(2, 2, 2), Vector3(8, 0, 0))
	var box: Node3D = _world.box()
	_host.stub_host_selection([box, hub])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.OBJECT
	_session.state().set_hover(hub, 0)
	var mat := StandardMaterial3D.new()
	box.set("materials", [mat])
	hub.set("materials", [mat])
	expect(_session.gizmo_targets().has(hub), "the hovered extra solid is a redraw target")
	hub.free()
	var first: Array = _session.gizmo_targets()
	var live_names := PackedStringArray()
	for node in first:
		live_names.append(node.name)
	expect(not live_names.has("Hub"), "a freed solid is dropped from redraw targets, got %s" % live_names)
	expect(live_names.has("Box"), "the remaining selected solid still redraws")
	var second: Array = _session.gizmo_targets()
	expect(second.has(box), "a second pass after a free still redraws the live solid")
	expect(_session.state().describe() == "Box selected.",
		"describe does not read a freed node, got %s" % _session.state().describe())


func case_every_verdict_maps_to_an_editor_constant() -> void:
	expect(int(SlabViewport.Verdict.PASS) == 0, "PASS is 0, matching AFTER_GUI_INPUT_PASS")
	expect(int(SlabViewport.Verdict.STOP) == 1, "STOP is 1, matching AFTER_GUI_INPUT_STOP")
	expect(int(SlabViewport.Verdict.CUSTOM) == 2, "CUSTOM is 2, matching AFTER_GUI_INPUT_CUSTOM")
	if not ClassDB.class_exists("EditorPlugin"):
		return
	expect(SlabViewport.after_gui_input(SlabViewport.Verdict.PASS) == EditorPlugin.AFTER_GUI_INPUT_PASS,
		"PASS means pass")
	expect(SlabViewport.after_gui_input(SlabViewport.Verdict.STOP) == EditorPlugin.AFTER_GUI_INPUT_STOP,
		"STOP means stop")
	expect(SlabViewport.after_gui_input(SlabViewport.Verdict.CUSTOM) == EditorPlugin.AFTER_GUI_INPUT_CUSTOM,
		"CUSTOM skips node selection so the editor gizmo can keep the click")


func case_click_without_drag_still_selects_and_never_mutates() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	_select(box, SlabSelection.Mode.FACE)
	var pristine: PackedByteArray = box.get("data")
	var at: Vector2 = _world.at_face(box, face)

	var verdict: int = _session.handle(_world.camera(), _world.click(at))
	var release: int = _session.handle(_world.camera(), _world.release(at))

	expect(verdict == SlabViewport.Verdict.CUSTOM, "the press selects without eating the editor gizmo")
	expect(release == SlabViewport.Verdict.PASS, "a click with no grab leaves release to the editor")
	expect(_session.state().ids == PackedInt64Array([face]), "the press selected the face, got %s" % _session.state().ids)
	expect(box.get("data") == pristine, "a click never reaches move_vertices or extrude_faces")


func case_a_one_pixel_drag_stays_below_the_threshold() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	_select(box, SlabSelection.Mode.FACE)
	var pristine: PackedByteArray = box.get("data")
	var at: Vector2 = _world.at_face(box, face)

	_session.handle(_world.camera(), _world.click(at))
	var verdict: int = _session.handle(_world.camera(), _world.drag_to(at + Vector2(NUDGE, 0.0)))
	_session.handle(_world.camera(), _world.release(at + Vector2(NUDGE, 0.0)))

	expect(verdict == SlabViewport.Verdict.PASS, "without a grab, motion stays with the editor gizmo")
	expect(box.get("data") == pristine, "one pixel is a click, not a drag")
	expect(_session.state().ids == PackedInt64Array([face]), "the selection from the press survives")


func case_a_plain_element_drag_does_not_move_geometry() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	_select(box, SlabSelection.Mode.FACE)
	var pristine: PackedByteArray = box.get("data")
	var at: Vector2 = _world.at_face(box, face)
	var target: Vector2 = at + Vector2(FAR, 0.0)

	_session.handle(_world.camera(), _world.click(at))
	var verdict: int = _session.handle(_world.camera(), _world.drag_to(target))
	_session.handle(_world.camera(), _world.release(target))

	expect(verdict == SlabViewport.Verdict.PASS, "a plain drag is left for the editor gizmo")
	expect(box.get("data") == pristine, "plain drag never calls move_vertices")
	expect(_world.moved_vertices(box).is_empty(), "geometry stays put")


func case_the_move_gizmo_translates_the_selected_vertices() -> void:
	var box: Node3D = _world.box()
	var vertex: int = _world.top_vertex(box)
	var before: Vector3 = box.call("vertex_position", vertex)
	var err: int = SlabXform.translate(box, SlabSelection.Mode.VERTEX, PackedInt64Array([vertex]), Vector3(0.5, 0.0, 0.0))
	expect(err == OK, "translate reports ok")
	expect(box.call("vertex_position", vertex).is_equal_approx(before + Vector3(0.5, 0.0, 0.0)),
		"the move gizmo applies one delta to the selected vertex")
	expect(_world.moved_vertices(box) == PackedInt64Array([vertex]), "only the selected vertex moved, got %s" % _world.moved_vertices(box))


func case_the_move_gizmo_translates_an_edge_by_one_delta() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var edge: int = box.call("face_edges", face)[0]
	var ends: PackedInt64Array = box.call("edge_vertices", edge)
	var before: Dictionary = _world.positions(box)
	SlabXform.translate(box, SlabSelection.Mode.EDGE, PackedInt64Array([edge]), Vector3(0.0, 0.5, 0.0))
	var d0: Vector3 = _world.vertex_world(box, ends[0]) - before[ends[0]]
	var d1: Vector3 = _world.vertex_world(box, ends[1]) - before[ends[1]]
	expect(d0.is_equal_approx(d1) and d0.is_equal_approx(Vector3(0.0, 0.5, 0.0)),
		"both endpoints share the gizmo delta")
	expect(box.call("face_count") == 6, "a gizmo translate never bevels")


func case_the_move_gizmo_translates_a_face_by_one_delta() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var ring: PackedInt64Array = box.call("face_vertices", face)
	var before: Dictionary = _world.positions(box)
	SlabXform.translate(box, SlabSelection.Mode.FACE, PackedInt64Array([face]), Vector3(0.0, 0.5, 0.0))
	expect(box.call("face_count") == 6, "a gizmo translate never extrudes")
	for v in ring:
		expect((_world.vertex_world(box, v) - before[v]).is_equal_approx(Vector3(0.0, 0.5, 0.0)),
			"the whole face moves by the gizmo delta")


func case_the_move_gizmo_applies_each_delta_from_the_rest_pose() -> void:
	var box: Node3D = _world.box()
	var vertex: int = _world.top_vertex(box)
	var ids := PackedInt64Array([vertex])
	var rest: PackedByteArray = box.get("data")
	var origin: Vector3 = SlabXform.centroid(box, SlabSelection.Mode.VERTEX, ids)
	box.set("data", rest)
	SlabXform.translate(box, SlabSelection.Mode.VERTEX, ids, Vector3(0.5, 0.0, 0.0))
	box.set("data", rest)
	SlabXform.translate(box, SlabSelection.Mode.VERTEX, ids, Vector3(0.25, 0.0, 0.0))
	expect(box.call("vertex_position", vertex).is_equal_approx(origin + Vector3(0.25, 0.0, 0.0)),
		"a later gizmo sample replaces the earlier one instead of stacking")


func case_shift_drag_a_selected_edge_bevels_it() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var edges: PackedInt64Array = box.call("face_edges", face)
	var edge: int = edges[0]
	var ends: PackedVector3Array = box.call("edge_endpoints", edge)
	var faces: PackedInt64Array = box.call("edge_faces", edge)
	var axis: Vector3 = (box.call("face_normal", faces[0]) + box.call("face_normal", faces[1])).normalized()
	var mid: Vector3 = box.to_global((ends[0] + ends[1]) * 0.5)
	_select(box, SlabSelection.Mode.EDGE)
	var at: Vector2 = _world.along_edge_on_face(box, edge, 0.5, face)
	_session.handle(_world.camera(), _world.click(at))
	_session.handle(_world.camera(), _world.release(at))
	var target: Vector2 = _world.toward(mid, axis, FAR)
	var volume_before: float = box.call("volume")

	_session.handle(_world.camera(), _world.click(at, true))
	var verdict: int = _session.handle(_world.camera(), _world.drag_to(target, true))
	_session.handle(_world.camera(), _world.release(target, true))

	expect(verdict == SlabViewport.Verdict.STOP, "bevel drag motion is claimed")
	expect(box.call("face_count") == 7 and box.call("vertex_count") == 10,
		"one shift-drag bevels exactly once: one chamfer face and two split vertices, got %d faces %d vertices" % [box.call("face_count"), box.call("vertex_count")])
	expect(box.call("edge_count") == 15, "bevel replaces one edge with the chamfer ring, got %d edges" % box.call("edge_count"))
	expect(box.call("volume") < volume_before, "the chamfer takes material off the corner")
	expect(_session.state().ids.is_empty(), "the retired edge is not kept selected, got %s" % _session.state().ids)


func case_shift_drag_a_selected_face_extrudes_by_the_drag_distance() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var base_ring: PackedInt64Array = box.call("face_vertices", face)
	var normal: Vector3 = box.call("face_normal", face)
	var centroid: Vector3 = box.to_global(box.call("face_centroid", face))
	_select(box, SlabSelection.Mode.FACE)
	var at: Vector2 = _world.at_face(box, face)
	_session.handle(_world.camera(), _world.click(at))
	_session.handle(_world.camera(), _world.release(at))
	var target: Vector2 = _world.toward(centroid, normal, FAR)

	_session.handle(_world.camera(), _world.click(at, true))
	var verdict: int = _session.handle(_world.camera(), _world.drag_to(target, true))
	_session.handle(_world.camera(), _world.release(target, true))

	expect(verdict == SlabViewport.Verdict.STOP, "extrude drag motion is claimed")
	expect(box.call("face_count") == 10 and box.call("vertex_count") == 12,
		"one shift-drag extrudes exactly once: 4 side faces and 4 new vertices, got %d faces %d vertices" % [box.call("face_count"), box.call("vertex_count")])
	expect(box.call("is_alive", face), "the dragged face id survives as the cap")
	expect(_session.state().ids == PackedInt64Array([face]), "the cap stays selected, got %s" % _session.state().ids)
	var cap_ring: PackedInt64Array = box.call("face_vertices", face)
	for v in cap_ring:
		expect(not base_ring.has(v), "the cap rides on new vertices")
	expect(_world.unchanged(box, base_ring), "the original ring stays as the base")
	var lift: Vector3 = box.to_global(box.call("face_centroid", face)) - centroid
	expect(lift.cross(normal).length() < 0.001 and lift.dot(normal) > 0.05, "the cap moved outward along the normal")
	expect(_world.camera().unproject_position(centroid + lift).distance_to(target) < 1.5, "the cap follows the cursor, so the extrude distance is the drag distance")


func case_shift_click_without_crossing_the_threshold_stays_an_additive_toggle() -> void:
	var box: Node3D = _world.box()
	var faces: PackedInt64Array = box.call("get_faces")
	_select(box, SlabSelection.Mode.FACE)
	var pristine: PackedByteArray = box.get("data")
	_session.handle(_world.camera(), _world.click(_world.at_face(box, faces[0])))
	_session.handle(_world.camera(), _world.release(_world.at_face(box, faces[0])))
	var second: Vector2 = _world.at_face(box, faces[1])

	_session.handle(_world.camera(), _world.click(second, true))
	_session.handle(_world.camera(), _world.drag_to(second + Vector2(NUDGE, 0.0), true))
	_session.handle(_world.camera(), _world.release(second + Vector2(NUDGE, 0.0), true))

	expect(_session.state().ids.size() == 2, "shift added the second face, got %s" % _session.state().ids)
	expect(box.get("data") == pristine, "no extrusion under the threshold")


func case_double_click_an_edge_selects_the_edge_loop() -> void:
	var ringed: Dictionary = _world.ringed_box()
	var box: Node3D = ringed["solid"]
	var edge: int = ringed["ring_edge"]
	_select(box, SlabSelection.Mode.EDGE)
	var pristine: PackedByteArray = box.get("data")
	var at: Vector2 = _world.along_edge(box, edge, 0.5)
	_session.handle(_world.camera(), _world.click(at))
	_session.handle(_world.camera(), _world.release(at))

	var verdict: int = _session.handle(_world.camera(), _world.double_click(at))
	_session.handle(_world.camera(), _world.release(at))

	var loop: PackedInt64Array = SlabTopology.edge_loop(box, edge)
	expect(verdict == SlabViewport.Verdict.STOP, "the double-click is claimed")
	expect(loop.size() > 1, "the ringed box offers a loop to find, got %d" % loop.size())
	expect(_session.state().ids == loop, "double-click selects the whole loop, got %s want %s" % [_session.state().ids, loop])
	expect(box.get("data") == pristine, "a double-click never drags")


func case_object_mode_never_moves_vertices() -> void:
	var box: Node3D = _world.box()
	_session.state().mode = SlabSelection.Mode.OBJECT
	var pristine: PackedByteArray = box.get("data")
	var start: Vector2 = _world.at_face(box, _world.top_face(box))
	var target: Vector2 = start + Vector2(FAR, 0.0)

	var press: int = _session.handle(_world.camera(), _world.click(start))
	var motion: int = _session.handle(_world.camera(), _world.drag_to(target))
	_session.handle(_world.camera(), _world.release(target))

	expect(press == SlabViewport.Verdict.CUSTOM and _host.focused() == box, "object mode still focuses the solid on press")
	expect(motion == SlabViewport.Verdict.PASS, "object mode never enters the grab; held motion is Godot's")
	expect(box.get("data") == pristine, "object mode never moves vertices")
	expect(_session.state().ids.is_empty(), "object mode selects no elements")


func case_hover_without_buttons_still_passes_in_every_mode() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	var at: Vector2 = _world.at_face(box, _world.top_face(box))
	for mode in SlabSelection.MODE_LABELS:
		_session.state().mode = mode
		var verdict: int = _session.handle(_world.camera(), _world.motion(at))
		expect(verdict == SlabViewport.Verdict.PASS, "%s-mode hover never claims the event" % SlabSelection.MODE_LABELS[mode])
	expect(_session.state().hover_solid == box, "hover still tracks the solid")


func case_release_ends_the_grab_and_the_next_drag_starts_from_the_new_positions() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var normal: Vector3 = box.call("face_normal", face)
	var centroid: Vector3 = box.to_global(box.call("face_centroid", face))
	_select(box, SlabSelection.Mode.FACE)
	var at: Vector2 = _world.at_face(box, face)
	_session.handle(_world.camera(), _world.click(at))
	_session.handle(_world.camera(), _world.release(at))
	var target: Vector2 = _world.toward(centroid, normal, FAR)

	_session.handle(_world.camera(), _world.click(at, true))
	_session.handle(_world.camera(), _world.drag_to(target, true))
	_session.handle(_world.camera(), _world.release(target, true))
	var after_first: Vector3 = box.to_global(box.call("face_centroid", face))
	expect(box.call("vertex_count") == 12, "the first shift-drag extruded")

	var idle: int = _session.handle(_world.camera(), _world.motion(target + Vector2(25.0, 0.0)))
	expect(idle == SlabViewport.Verdict.PASS, "after release, motion is hover again")
	expect(box.to_global(box.call("face_centroid", face)).is_equal_approx(after_first), "release ended the grab; hover moves nothing")

	var at2: Vector2 = _world.at_face(box, face)
	var centroid2: Vector3 = box.to_global(box.call("face_centroid", face))
	var target2: Vector2 = _world.toward(centroid2, normal, FAR)
	_session.handle(_world.camera(), _world.click(at2, true))
	_session.handle(_world.camera(), _world.drag_to(target2, true))
	_session.handle(_world.camera(), _world.release(target2, true))

	expect(box.call("vertex_count") == 16, "the second shift-drag extrudes from the new cap")
	expect(_world.camera().unproject_position(box.to_global(box.call("face_centroid", face))).distance_to(target2) < 1.5,
		"the second grab continues from the new position, not the original")
	expect(_host.undo() == null, "this host has no undo manager and geometry still moved")


func case_one_undo_snapshot_per_finished_drag_when_the_host_has_undo() -> void:
	var undo := SlabTestUndo.new()
	_host.stub_undo(undo)
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var normal: Vector3 = box.call("face_normal", face)
	var centroid: Vector3 = box.to_global(box.call("face_centroid", face))
	_select(box, SlabSelection.Mode.FACE)
	var pristine: PackedByteArray = box.get("data")
	var at: Vector2 = _world.at_face(box, face)
	_session.handle(_world.camera(), _world.click(at))
	_session.handle(_world.camera(), _world.release(at))
	var target: Vector2 = _world.toward(centroid, normal, FAR)

	_session.handle(_world.camera(), _world.click(at, true))
	_session.handle(_world.camera(), _world.drag_to(target, true))
	expect(undo.actions.is_empty(), "nothing is recorded while the drag is live")
	_session.handle(_world.camera(), _world.release(target, true))
	var at2: Vector2 = _world.at_face(box, face)
	var centroid2: Vector3 = box.to_global(box.call("face_centroid", face))
	var target2: Vector2 = _world.toward(centroid2, normal, FAR)
	_session.handle(_world.camera(), _world.click(at2, true))
	_session.handle(_world.camera(), _world.drag_to(target2, true))
	_session.handle(_world.camera(), _world.release(target2, true))

	expect(undo.actions.size() == 2, "exactly one action per finished drag, got %d" % undo.actions.size())
	if undo.actions.size() < 2:
		return
	expect(undo.actions[0]["undo"] == pristine, "the first action restores the pre-drag data")
	expect(undo.actions[0]["do"] == undo.actions[1]["undo"], "the second drag's undo lands on the first drag's result")
	expect(undo.actions[1]["do"] == box.get("data"), "the last action's do value is the live mesh")
	expect(undo.actions[0]["execute"] == false, "the live mesh is already mutated, so commit does not re-run")
	expect(undo.actions[0]["context"] == box and String(undo.actions[0]["name"]).begins_with("Slab "), "actions are scoped to the solid and labelled like the panel's")


func case_escape_during_a_drag_restores_the_snapshot_and_keeps_the_mode() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var normal: Vector3 = box.call("face_normal", face)
	var centroid: Vector3 = box.to_global(box.call("face_centroid", face))
	_select(box, SlabSelection.Mode.FACE)
	var pristine: PackedByteArray = box.get("data")
	var at: Vector2 = _world.at_face(box, face)
	_session.handle(_world.camera(), _world.click(at))
	_session.handle(_world.camera(), _world.release(at))
	var target: Vector2 = _world.toward(centroid, normal, FAR)
	_session.handle(_world.camera(), _world.click(at, true))
	_session.handle(_world.camera(), _world.drag_to(target, true))
	expect(box.get("data") != pristine, "the drag extruded the face")

	var verdict: int = _session.handle(_world.camera(), _world.key(KEY_ESCAPE))

	expect(verdict == SlabViewport.Verdict.STOP, "escape mid-drag is claimed")
	expect(box.get("data") == pristine, "escape restores the pre-drag data")
	expect(_session.state().mode == SlabSelection.Mode.FACE, "escape mid-drag cancels the grab, not the mode")


func case_motion_without_the_button_held_ends_a_stale_grab() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var normal: Vector3 = box.call("face_normal", face)
	var centroid: Vector3 = box.to_global(box.call("face_centroid", face))
	_select(box, SlabSelection.Mode.FACE)
	var at: Vector2 = _world.at_face(box, face)
	_session.handle(_world.camera(), _world.click(at))
	_session.handle(_world.camera(), _world.release(at))
	var target: Vector2 = _world.toward(centroid, normal, FAR)
	_session.handle(_world.camera(), _world.click(at, true))
	_session.handle(_world.camera(), _world.drag_to(target, true))
	var landed: PackedByteArray = box.get("data")

	_session.handle(_world.camera(), _world.motion(target + Vector2(FAR, 0.0)))

	expect(box.get("data") == landed, "a motion without the button ends the grab instead of dragging")
	var again: int = _session.handle(_world.camera(), _world.motion(at))
	expect(again == SlabViewport.Verdict.PASS, "and the session is idle again")


func _select(solid: Node3D, mode: int) -> void:
	_host.stub_host_selection([solid])
	_session.adopt_host_selection()
	_session.state().mode = mode


func _initialize() -> void:
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		push_error("SlabSolid missing. Build the extension first.")
		quit(1)
		return
	_world = SlabTestWorld.staged(self)


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_run_all()
	return true


func _run_all() -> void:
	for case_name in _case_names():
		_host = SlabTestHost.over(_world.stage())
		_session = SlabViewport.new(_host)
		call(case_name)
		_world.reset()
		_ran += 1
	_world.tear_down()
	if _fails != 0:
		push_error(str(_fails) + " failures")
		quit(1)
	else:
		print("viewport_smoke ok cases=%d" % _ran)
		quit(0)


func _case_names() -> PackedStringArray:
	var names := PackedStringArray()
	var filter: String = OS.get_environment("SLAB_CASE")
	for method in get_method_list():
		var method_name: String = method.name
		if not method_name.begins_with("case_"):
			continue
		if filter != "" and method_name != filter and method_name != "case_" + filter:
			continue
		names.append(method_name)
	return names


func expect(ok: bool, what: String) -> void:
	if ok:
		print("ok ", what)
		return
	push_error("FAIL " + what)
	print("FAIL ", what)
	_fails += 1
