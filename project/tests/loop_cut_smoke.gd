extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const LoopCut := preload("res://addons/slab/slab_loop_cut.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const Metrics := preload("res://addons/slab/slab_metrics.gd")
const Host := preload("res://tests/slab_test_host.gd")
const Undo := preload("res://tests/slab_test_undo.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("ok " if ok else "FAIL ", message)

func key(code: int, unicode_value: int = 0) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.unicode = unicode_value
	return event

func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	var camera := Camera3D.new()
	root.add_child(camera)
	var selection := Selection.new()
	selection.solid = solid
	selection.mode = Selection.Mode.EDGE
	var edge: int = solid.call("get_edges")[0]
	selection.set_ids(PackedInt64Array([edge]))
	var undo := Undo.new()
	var host = Host.over(root).stub_undo(undo)
	var actions := Actions.new(selection, undo)
	var tool := LoopCut.new(selection, actions, host)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, Metrics.at_scale(1.0))
	root.add_child(panel)
	var before: PackedByteArray = solid.get("data")
	actions.loop_count = 3
	actions.run("insert_loop")
	check(tool.active and not tool.lines.is_empty(), "toolbar begins a visible multi-cut preview")
	check(actions.loop_active and actions.loop_can_apply, "selected-edge preview enables panel Apply")
	var away := InputEventMouseMotion.new()
	away.position = Vector2(-1000, -1000)
	tool.handle(camera, away)
	check(tool.edge == edge and not tool.lines.is_empty(), "selected edge stays fixed while moving to panel controls")
	check(solid.get("data") == before, "preview does not modify serialized geometry")
	(panel.find_child("LoopCancel", true, false) as Button).pressed.emit()
	check(not tool.active and selection.preview_lines.is_empty(), "panel Cancel removes preview")
	check(not actions.loop_active and not actions.loop_can_apply, "panel Cancel clears published loop state")
	check(solid.get("data") == before and undo.actions.is_empty(), "cancel changes neither geometry nor undo history")
	var reports: Array[String] = []
	actions.reported.connect(func(message: String) -> void: reports.append(message))
	selection.clear_ids()
	tool.begin()
	check(actions.loop_active and not actions.loop_can_apply and selection.preview_lines.is_empty(),
		"a candidate-less session publishes disabled Apply and clears stale preview lines")
	check(not reports.is_empty() and reports[-1].contains("hover an edge"),
		"a candidate-less session replaces stale cut guidance")
	tool.handle(camera, key(KEY_ESCAPE))
	check(not tool.active, "Escape cancels a candidate-less session")
	selection.set_ids(PackedInt64Array([edge]))
	actions.loop_count = 1
	tool.begin()
	tool.handle(camera, key(KEY_2, 50))
	tool.handle(camera, key(KEY_5, 53))
	check(is_equal_approx(actions.loop_position, 0.25), "typed 25 places the cut exactly at one quarter")
	var preview: PackedVector3Array = tool.lines.duplicate()
	tool.handle(camera, key(KEY_ENTER))
	check(not tool.active and solid.call("face_count") == 10, "Enter commits a closed box loop")
	check(undo.actions.size() == 1, "confirmation is one undo action")
	var after: PackedByteArray = solid.get("data")
	var vertices: PackedInt64Array = solid.call("get_vertices")
	var all_match := true
	for position in preview:
		var found := false
		for vertex in vertices:
			if solid.call("vertex_position", vertex).is_equal_approx(position):
				found = true
		all_match = all_match and found
	check(all_match, "committed vertices match exact preview endpoints")
	undo.undo()
	check(solid.get("data") == before, "undo restores original bytes")
	undo.redo()
	check(solid.get("data") == after, "redo restores committed bytes")
	undo.undo()
	selection.set_ids(PackedInt64Array([edge]))
	tool.begin()
	var cuts := panel.find_child("loop_count", true, false).find_children("*", "SpinBox", true, false)[0] as SpinBox
	cuts.get_line_edit().text = "3"
	(panel.find_child("LoopApply", true, false) as Button).pressed.emit()
	check(actions.loop_count == 3 and not tool.active and solid.get("data") != before,
		"panel Apply commits a pending Cuts value before confirming")
	undo.undo()
	selection.set_ids(PackedInt64Array([edge]))
	tool.begin()
	selection.mode = Selection.Mode.FACE
	check(not tool.active and selection.preview_lines.is_empty(), "changing mode cancels modal preview")
	print("loop_cut_smoke: %d failures" % failures)
	quit(1 if failures else 0)
