extends SceneTree

const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabTopology := preload("res://addons/slab/slab_topology.gd")
const SlabTestHost := preload("res://tests/slab_test_host.gd")
const SlabTestWorld := preload("res://tests/slab_test_world.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")

const VOID := Vector2(20000.0, 20000.0)
const FAR := 40.0
const NUDGE := 1.0

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
	_host.stub_host_selection([box])
	_session.adopt_host_selection()
	_session.state().mode = SlabSelection.Mode.EDGE

	_session.handle(_world.camera(), _world.click(_world.past_pick_radius(box)))

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


func case_click_without_drag_still_selects_and_never_mutates() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	_select(box, SlabSelection.Mode.FACE)
	var pristine: PackedByteArray = box.get("data")
	var at: Vector2 = _world.at_face(box, face)

	var verdict: int = _session.handle(_world.camera(), _world.click(at))
	var release: int = _session.handle(_world.camera(), _world.release(at))

	expect(verdict == SlabViewport.Verdict.STOP, "the press is still claimed by Slab")
	expect(release == SlabViewport.Verdict.STOP, "the release that ends a claimed press is claimed too")
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

	expect(verdict == SlabViewport.Verdict.STOP, "a pressed gesture is Slab's until release, even under the threshold")
	expect(box.get("data") == pristine, "one pixel is a click, not a drag")
	expect(_session.state().ids == PackedInt64Array([face]), "the selection from the press survives")


func case_a_drag_well_past_the_threshold_moves_geometry() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	_select(box, SlabSelection.Mode.FACE)
	var pristine: PackedByteArray = box.get("data")
	var at: Vector2 = _world.at_face(box, face)
	var normal: Vector3 = box.call("face_normal", face)
	var target: Vector2 = _world.toward(box.to_global(box.call("face_centroid", face)), normal, FAR)

	_session.handle(_world.camera(), _world.click(at))
	_session.handle(_world.camera(), _world.drag_to(target))
	_session.handle(_world.camera(), _world.release(target))

	expect(box.get("data") != pristine, "forty pixels is a drag")
	expect(not _world.moved_vertices(box).is_empty(), "geometry moved")


func case_drag_threshold_is_a_named_constant_in_the_session() -> void:
	expect(SlabViewport.DRAG_THRESHOLD_PX >= 4.0 and SlabViewport.DRAG_THRESHOLD_PX <= 8.0,
		"the threshold is a small named constant, got %s" % SlabViewport.DRAG_THRESHOLD_PX)
	expect(NUDGE < SlabViewport.DRAG_THRESHOLD_PX and FAR > SlabViewport.DRAG_THRESHOLD_PX * 2.0,
		"the smoke's nudge and far distances bracket the threshold")


func case_drag_a_selected_vertex_moves_it_in_the_camera_plane() -> void:
	var box: Node3D = _world.box()
	var vertex: int = _world.top_vertex(box)
	_select(box, SlabSelection.Mode.VERTEX)
	var start: Vector2 = _world.at_vertex(box, vertex)
	var target: Vector2 = start + Vector2(FAR, 0.0)
	var before: Vector3 = _world.vertex_world(box, vertex)

	_session.handle(_world.camera(), _world.click(start))
	var verdict: int = _session.handle(_world.camera(), _world.drag_to(target))
	_session.handle(_world.camera(), _world.release(target))

	var after: Vector3 = _world.vertex_world(box, vertex)
	expect(verdict == SlabViewport.Verdict.STOP, "motion during an active drag is claimed; orbit cannot steal it")
	expect(_session.state().ids == PackedInt64Array([vertex]), "the pressed vertex is the selection")
	expect(_world.camera().unproject_position(after).distance_to(target) < 1.0,
		"the vertex lands under the cursor, off by %s px" % _world.camera().unproject_position(after).distance_to(target))
	expect(absf((after - before).dot(_world.forward())) < 0.01, "the move stays in the camera plane")
	expect(_world.moved_vertices(box) == PackedInt64Array([vertex]), "only the grabbed vertex moved, got %s" % _world.moved_vertices(box))


func case_drag_a_selected_edge_moves_both_endpoints_in_the_camera_plane() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var edges: PackedInt64Array = box.call("face_edges", face)
	var edge: int = edges[0]
	var ends: PackedInt64Array = box.call("edge_vertices", edge)
	_select(box, SlabSelection.Mode.EDGE)
	var start: Vector2 = _world.along_edge_on_face(box, edge, 0.5, face)
	var target: Vector2 = start + Vector2(0.0, FAR)
	var before: Dictionary = _world.positions(box)

	_session.handle(_world.camera(), _world.click(start))
	var verdict: int = _session.handle(_world.camera(), _world.drag_to(target))
	_session.handle(_world.camera(), _world.release(target))

	var moved: PackedInt64Array = _world.moved_vertices(box)
	var d0: Vector3 = _world.vertex_world(box, ends[0]) - before[ends[0]]
	var d1: Vector3 = _world.vertex_world(box, ends[1]) - before[ends[1]]
	expect(verdict == SlabViewport.Verdict.STOP, "edge drag motion is claimed")
	expect(_session.state().ids == PackedInt64Array([edge]), "the pressed edge is the selection")
	expect(moved.size() == 2 and moved.has(ends[0]) and moved.has(ends[1]), "exactly the edge's two vertices moved, got %s" % moved)
	expect(d0.is_equal_approx(d1), "both endpoints share one delta")
	expect(d0.length() > 0.05, "the edge travelled")
	expect(absf(d0.dot(_world.forward())) < 0.01, "the move stays in the camera plane")
	expect(box.call("face_count") == 6, "a plain edge drag never bevels")


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


func case_drag_a_selected_face_pulls_it_along_its_normal() -> void:
	var box: Node3D = _world.box()
	var face: int = _world.top_face(box)
	var ring: PackedInt64Array = box.call("face_vertices", face)
	var normal: Vector3 = box.call("face_normal", face)
	var centroid: Vector3 = box.to_global(box.call("face_centroid", face))
	_select(box, SlabSelection.Mode.FACE)
	var start: Vector2 = _world.at_face(box, face)
	var target: Vector2 = _world.toward(centroid, normal, FAR)
	var before: Dictionary = _world.positions(box)

	_session.handle(_world.camera(), _world.click(start))
	var verdict: int = _session.handle(_world.camera(), _world.drag_to(target))
	_session.handle(_world.camera(), _world.release(target))

	expect(verdict == SlabViewport.Verdict.STOP, "face drag motion is claimed")
	expect(box.call("face_count") == 6, "a plain drag never extrudes")
	var moved: PackedInt64Array = _world.moved_vertices(box)
	expect(moved.size() == 4, "the four ring vertices moved, got %s" % moved)
	var first: Vector3 = _world.vertex_world(box, ring[0]) - before[ring[0]]
	for v in ring:
		var d: Vector3 = _world.vertex_world(box, v) - before[v]
		expect(d.is_equal_approx(first), "the whole face moves by one delta")
		expect(d.cross(normal).length() < 0.001, "the delta is parallel to the face normal")
	expect(first.dot(normal) > 0.05, "the wall was pulled outward")
	var cap: Vector3 = box.to_global(box.call("face_centroid", face))
	expect(_world.camera().unproject_position(cap).distance_to(target) < 1.5, "the face follows the cursor along the normal's screen line")


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

	expect(press == SlabViewport.Verdict.STOP and _host.focused() == box, "object mode still focuses the solid on press")
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
	var vertex: int = _world.top_vertex(box)
	_select(box, SlabSelection.Mode.VERTEX)
	var p0: Vector2 = _world.at_vertex(box, vertex)
	var p1: Vector2 = p0 + Vector2(FAR, 0.0)
	_session.handle(_world.camera(), _world.click(p0))
	_session.handle(_world.camera(), _world.drag_to(p1))
	_session.handle(_world.camera(), _world.release(p1))
	var after_first: Vector3 = _world.vertex_world(box, vertex)

	var idle: int = _session.handle(_world.camera(), _world.motion(p1 + Vector2(25.0, 0.0)))
	expect(idle == SlabViewport.Verdict.PASS, "after release, motion is hover again")
	expect(_world.vertex_world(box, vertex) == after_first, "release ended the grab; hover moves nothing")

	var p1b: Vector2 = _world.at_vertex(box, vertex)
	var p2: Vector2 = p1b + Vector2(0.0, 30.0)
	_session.handle(_world.camera(), _world.click(p1b))
	_session.handle(_world.camera(), _world.drag_to(p2))
	_session.handle(_world.camera(), _world.release(p2))

	expect(_world.camera().unproject_position(_world.vertex_world(box, vertex)).distance_to(p2) < 1.0,
		"the second drag continues from the new position, not the original")
	expect(_host.undo() == null, "this host has no undo manager and geometry still moved")


func case_one_undo_snapshot_per_finished_drag_when_the_host_has_undo() -> void:
	var undo := SlabTestUndo.new()
	_host.stub_undo(undo)
	var box: Node3D = _world.box()
	var vertex: int = _world.top_vertex(box)
	_select(box, SlabSelection.Mode.VERTEX)
	var pristine: PackedByteArray = box.get("data")

	var p0: Vector2 = _world.at_vertex(box, vertex)
	_session.handle(_world.camera(), _world.click(p0))
	_session.handle(_world.camera(), _world.drag_to(p0 + Vector2(FAR, 0.0)))
	expect(undo.actions.is_empty(), "nothing is recorded while the drag is live")
	_session.handle(_world.camera(), _world.release(p0 + Vector2(FAR, 0.0)))
	var p1: Vector2 = _world.at_vertex(box, vertex)
	_session.handle(_world.camera(), _world.click(p1))
	_session.handle(_world.camera(), _world.drag_to(p1 + Vector2(0.0, 30.0)))
	_session.handle(_world.camera(), _world.release(p1 + Vector2(0.0, 30.0)))

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
	var vertex: int = _world.top_vertex(box)
	_select(box, SlabSelection.Mode.VERTEX)
	var pristine: PackedByteArray = box.get("data")
	var p0: Vector2 = _world.at_vertex(box, vertex)
	_session.handle(_world.camera(), _world.click(p0))
	_session.handle(_world.camera(), _world.drag_to(p0 + Vector2(FAR, 0.0)))
	expect(box.get("data") != pristine, "the drag moved the vertex")

	var verdict: int = _session.handle(_world.camera(), _world.key(KEY_ESCAPE))

	expect(verdict == SlabViewport.Verdict.STOP, "escape mid-drag is claimed")
	expect(box.get("data") == pristine, "escape restores the pre-drag data")
	expect(_session.state().mode == SlabSelection.Mode.VERTEX, "escape mid-drag cancels the grab, not the mode")


func case_motion_without_the_button_held_ends_a_stale_grab() -> void:
	var box: Node3D = _world.box()
	var vertex: int = _world.top_vertex(box)
	_select(box, SlabSelection.Mode.VERTEX)
	var p0: Vector2 = _world.at_vertex(box, vertex)
	_session.handle(_world.camera(), _world.click(p0))
	_session.handle(_world.camera(), _world.drag_to(p0 + Vector2(FAR, 0.0)))
	var landed: Vector3 = _world.vertex_world(box, vertex)

	_session.handle(_world.camera(), _world.motion(p0 + Vector2(FAR * 2.0, 0.0)))

	expect(_world.vertex_world(box, vertex) == landed, "a motion without the button ends the grab instead of dragging")
	var again: int = _session.handle(_world.camera(), _world.motion(p0))
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
