extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
const PlaneCut := preload("res://addons/slab/slab_plane_cut.gd")
const Host := preload("res://tests/slab_test_host.gd")
const History := preload("res://tests/slab_test_undo.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func _solid() -> Node3D:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	return solid

func _seed_uv(selection: RefCounted, solid: Node3D) -> int:
	var face: int = solid.call("get_faces")[0]
	var corner: int = solid.call("face_uv", face).ids[0]
	selection.set_uv_mode(Selection.UVMode.UV_VERT)
	selection.set_uv_selection(PackedInt64Array([corner]))
	selection.set_hover(solid, face)
	return corner

func _cleared(selection: RefCounted) -> bool:
	return selection.ids.is_empty() and selection.get_uv_selection().is_empty() and selection.hover_id == 0

func _run() -> void:
	_boolean()
	_plane_cut()
	_bevel()
	print("REBUILD_SELECTION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _boolean() -> void:
	var solid := _solid()
	var cutter := _solid()
	cutter.position.x = 2
	var selection := Selection.new()
	selection.set_objects([solid, cutter])
	var history := History.new()
	var actions := Actions.new(selection, history)
	_seed_uv(selection, solid)
	check(selection.ids.is_empty() and not selection.get_uv_selection().is_empty(), "fixture has cached UV handles with empty 3D selection")
	actions.run("boolean_union")
	check(history.actions.size() == 1 and _cleared(selection), "Boolean apply clears UV and hover handles despite empty 3D IDs")
	_seed_uv(selection, solid)
	history.undo()
	check(_cleared(selection), "Boolean Undo invalidates handles picked on the result")
	_seed_uv(selection, solid)
	history.redo()
	check(_cleared(selection), "Boolean Redo invalidates handles picked on the original")
	solid.free()
	cutter.free()

func _plane_cut() -> void:
	var solid := _solid()
	var selection := Selection.new()
	selection.solid = solid
	var history := History.new()
	var host = Host.over(root).stub_undo(history)
	var actions := Actions.new(selection, history)
	var tool := PlaneCut.new(selection, actions, host)
	actions.plane_normal = Vector3.RIGHT
	actions.plane_offset = 2
	_seed_uv(selection, solid)
	actions.run("plane_cut")
	tool.cancel()
	check(not selection.get_uv_selection().is_empty(), "cancelled cut retains valid UV selection")
	actions.run("plane_cut")
	tool.confirm()
	check(history.actions.size() == 1 and _cleared(selection), "Plane Cut clears cached UV and hover handles")
	_seed_uv(selection, solid)
	history.undo()
	check(_cleared(selection), "Plane Cut Undo clears result handles")
	_seed_uv(selection, solid)
	history.redo()
	check(_cleared(selection), "Plane Cut Redo clears original handles")
	solid.free()

func _bevel() -> void:
	var solid := _solid()
	var other := _solid()
	var history := History.new()
	var host = Host.over(root).stub_undo(history)
	var session := SlabViewport.new(host)
	var selection: RefCounted = session.state()
	selection.solid = solid
	selection.mode = Selection.Mode.FACE
	var top := 0
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > .9: top = face
	selection.set_ids(PackedInt64Array([top]))
	_seed_uv(selection, solid)
	selection.enter_face_isolation()
	var actions := Actions.new(selection, history)
	session.bind_actions(actions)
	actions.bevel_amount = .1
	actions.bevel_segments = 2
	var before: PackedByteArray = solid.get("data")
	actions.run("bevel_edges")
	actions.operation_apply_requested.emit()
	check(solid.get("data") != before and history.actions.size() == 1, "connected face bevel rebuilds geometry")
	check(_cleared(selection) and not selection.face_isolated, "bevel clears cached elements, UVs, hover and old face-isolation mask")
	history.undo()
	check(selection.ids == PackedInt64Array([top]), "bevel Undo restores selection against original geometry")
	_seed_uv(selection, solid)
	history.redo()
	check(_cleared(selection), "bevel Redo clears handles from original geometry")
	selection.solid = other
	selection.mode = Selection.Mode.FACE
	var other_face: int = other.call("get_faces")[0]
	selection.set_ids(PackedInt64Array([other_face]))
	var other_corner := _seed_uv(selection, other)
	history.undo()
	check(selection.solid == other and selection.ids == PackedInt64Array([other_face]) and selection.get_uv_selection() == PackedInt64Array([other_corner]), "Undo on old solid does not overwrite another solid's selection")
	solid.free()
	other.free()
