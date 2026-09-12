extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const PlaneCut := preload("res://addons/slab/slab_plane_cut.gd")
const Host := preload("res://tests/slab_test_host.gd")
const Undo := preload("res://tests/slab_test_undo.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("ok " if ok else "FAIL ", message)

func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	return event

func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 4, 4))
	var selection := Selection.new()
	selection.solid = solid
	selection.mode = Selection.Mode.OBJECT
	var undo := Undo.new()
	var host = Host.over(root).stub_undo(undo)
	var actions := Actions.new(selection, undo)
	var tool := PlaneCut.new(selection, actions, host)
	actions.plane_normal = Vector3(2, -3, 5)
	actions.plane_offset = 4.0 / sqrt(38.0)
	actions.plane_keep_positive = false
	actions.plane_cap_material = 7
	var before: PackedByteArray = solid.get("data")
	actions.run("plane_cut")
	check(tool.active and not tool.lines.is_empty(), "Plane Cut starts a visible oblique result preview")
	check(solid.get("data") == before, "preview leaves the serialized solid unchanged")
	tool.handle(null, key(KEY_ESCAPE))
	check(not tool.active and selection.preview_lines.is_empty(), "Escape clears the preview")
	check(solid.get("data") == before and undo.actions.is_empty(), "cancel changes neither geometry nor undo history")
	actions.plane_offset = 8.0 / sqrt(38.0)
	actions.run("plane_cut")
	tool.handle(null, key(KEY_ENTER))
	check(not tool.active and solid.call("volume") > 31.9 and solid.call("volume") < 32.1, "Enter applies an exact central oblique half")
	check(undo.actions.size() == 1, "confirmation creates one undo action")
	var after: PackedByteArray = solid.get("data")
	var found_cap := false
	for face in solid.call("get_faces"):
		var normal: Vector3 = solid.call("face_normal", face)
		var attrs: Dictionary = solid.call("face_uv", face)
		if absf(normal.dot(actions.plane_normal.normalized())) > 0.95 and int(attrs.get("slot", -1)) == 7:
			found_cap = true
	check(found_cap, "new cap carries the chosen material slot")
	undo.undo()
	check(solid.get("data") == before, "undo restores the original bytes")
	undo.redo()
	check(solid.get("data") == after, "redo restores the cut bytes")
	actions.run("plane_cut")
	selection.mode = Selection.Mode.FACE
	check(not tool.active and selection.preview_lines.is_empty(), "changing selection mode cancels the modal preview")
	check(solid.get("data") == after and undo.actions.size() == 1, "mode cancellation leaves geometry and history unchanged")
	selection.mode = Selection.Mode.OBJECT
	actions.run("plane_cut")
	solid.call("make_box", Vector3(2, 2, 2))
	var external_edit: PackedByteArray = solid.get("data")
	tool.confirm()
	check(not tool.active and solid.get("data") == external_edit, "confirmation cannot overwrite a solid changed since preview")
	print("plane_cut_smoke: %d failures" % failures)
	quit(1 if failures else 0)
