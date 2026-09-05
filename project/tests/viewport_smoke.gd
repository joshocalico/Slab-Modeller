extends SceneTree

const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabTestHost := preload("res://tests/slab_test_host.gd")
const SlabTestWorld := preload("res://tests/slab_test_world.gd")

const VOID := Vector2(20000.0, 20000.0)

var _world: SlabTestWorld
var _host: SlabTestHost
var _session: SlabViewport
var _fails := 0
var _ran := 0
var _frames := 0


func case_empty_selection_first_click_selects_the_solid() -> void:
	var box: Node3D = _world.box()
	expect(_host.selected_nodes().is_empty(), "the editor selection starts empty")

	var verdict: int = _session.handle(_world.camera(), _world.click(_world.at_face(box, _world.top_face(box))))

	expect(verdict == SlabViewport.Verdict.STOP, "the very first click is claimed by Slab")
	expect(_host.focused() == box, "the first click focuses the solid, got %s" % _host.focused())


func case_empty_space_click_keeps_slab_authority() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.FACE
	_session.state().set_ids(PackedInt64Array([_world.top_face(box)]))

	var verdict: int = _session.handle(_world.camera(), _world.click(VOID))

	expect(verdict == SlabViewport.Verdict.STOP, "a miss with a solid selected stays inside Slab")
	expect(_session.state().ids.is_empty(), "the miss clears the element selection")
	expect(_host.commands().is_empty(), "a miss never touches the editor selection")


func case_empty_space_click_with_nothing_selected_passes() -> void:
	_session.state().mode = SlabSelection.Mode.FACE

	var verdict: int = _session.handle(_world.camera(), _world.click(VOID))

	expect(verdict == SlabViewport.Verdict.PASS, "with nothing selected a miss leaves the viewport alone")


func case_object_mode_selects_the_solid_not_its_mesh_child() -> void:
	var box: Node3D = _world.box()
	_session.state().mode = SlabSelection.Mode.OBJECT

	var verdict: int = _session.handle(_world.camera(), _world.click(_world.at_face(box, _world.top_face(box))))

	expect(verdict == SlabViewport.Verdict.STOP, "an object-mode hit is claimed by Slab")
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
		expect(verdict == SlabViewport.Verdict.STOP, "a click %d%% along an edge is claimed" % int(t * 100.0))
		expect(_session.state().ids == PackedInt64Array([edge]),
			"a click %d%% along the edge selects it, got %s" % [int(t * 100.0), _session.state().ids])


func case_edge_click_past_the_radius_selects_nothing() -> void:
	var box: Node3D = _world.box()
	var edges: PackedInt64Array = box.call("face_edges", _world.top_face(box))
	var edge: int = edges[0]
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.EDGE

	var far_off: Vector2 = _world.along_edge(box, edge, 0.5) + Vector2(0.0, _world.metrics().pick_radius() * 4.0)
	_session.handle(_world.camera(), _world.click(far_off))

	expect(_session.state().ids.is_empty(), "a click well outside the radius picks no edge")


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


func case_element_click_at_the_solid_origin_still_stops() -> void:
	var box: Node3D = _world.box()
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.FACE

	var verdict: int = _session.handle(_world.camera(), _world.click(_world.at_origin(box)))

	expect(verdict == SlabViewport.Verdict.STOP, "a click over the gizmo origin is claimed by Slab")
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


func case_every_verdict_maps_to_an_editor_constant() -> void:
	expect(int(SlabViewport.Verdict.PASS) == 0, "PASS is 0, matching AFTER_GUI_INPUT_PASS")
	expect(int(SlabViewport.Verdict.STOP) == 1, "STOP is 1, matching AFTER_GUI_INPUT_STOP")
	if not ClassDB.class_exists("EditorPlugin"):
		return
	expect(SlabViewport.after_gui_input(SlabViewport.Verdict.PASS) == EditorPlugin.AFTER_GUI_INPUT_PASS,
		"PASS means pass")
	expect(SlabViewport.after_gui_input(SlabViewport.Verdict.STOP) == EditorPlugin.AFTER_GUI_INPUT_STOP,
		"STOP means stop")


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
