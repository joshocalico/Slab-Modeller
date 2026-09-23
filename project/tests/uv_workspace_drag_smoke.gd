extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const Paint := preload("res://addons/slab/slab_paint.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const Metrics := preload("res://addons/slab/slab_metrics.gd")

var failures := 0


func _init() -> void:
	_run.call_deferred()


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _button(canvas: Control, point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = point
	canvas.call("_gui_input", event)


func _motion(canvas: Control, point: Vector2, shift: bool = false, rotate: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.shift_pressed = shift
	event.meta_pressed = rotate
	canvas.call("_gui_input", event)


func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([solid.call("get_faces")[0]]))
	var undo := UndoRedo.new()
	var actions := Actions.new(selection, undo)
	var paint := Paint.new()
	paint.bind(selection, actions, undo)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, Metrics.at_scale(1.0))
	panel.bind_paint(paint)
	root.add_child(panel)
	panel.size = Vector2(1100, 500)
	paint.enter()
	await process_frame
	await process_frame
	var canvas: Control = panel.find_child("PaintCanvas", true, false)
	canvas.call("frame_uv")
	var start := canvas.size * Vector2(0.55, 0.6)
	var before: PackedByteArray = solid.get("data")
	expect(not canvas.call("is_uv_element_mode"), "UV opens in explicit Place tool with working drag")
	_button(canvas, start, true)
	_motion(canvas, start + Vector2(35, 20))
	expect(solid.get("data") != before, "canvas motion previews placement through panel bindings")
	_button(canvas, start + Vector2(35, 20), false)
	var after: PackedByteArray = solid.get("data")
	undo.undo()
	expect(solid.get("data") == before, "Undo restores mapping after canvas drag")
	undo.redo()
	expect(solid.get("data") == after, "Redo restores mapping after canvas drag")
	undo.undo()

	for gesture in ["scale", "rotate"]:
		_button(canvas, start, true)
		_motion(canvas, start + Vector2(20, 15), gesture == "scale", gesture == "rotate")
		expect(solid.get("data") != before, gesture + " gesture changes mapping")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		canvas.call("_gui_input", escape)
		_button(canvas, start, false)
		expect(solid.get("data") == before, "Escape restores " + gesture + " without committing")

	var strip: Control = panel.find_child("UVModeStripButtons", true, false)
	for button in strip.get_children():
		if button is Button and button.get_meta("slab_uv_mode") == Selection.UVMode.UV_FACE:
			button.pressed.emit()
	expect(canvas.call("is_uv_element_mode"), "UV Face switches canvas to element selection")
	var center := Vector2.ZERO
	var uvs := paint.selected_uvs()
	for uv in uvs:
		center += uv
	center /= float(uvs.size())
	var pick: Vector2 = canvas.call("_uv_to_canvas", center)
	_button(canvas, pick, true)
	_button(canvas, pick, false)
	expect(selection.uv_selection_count() == 1, "UV Face click selects an actual canvas face")
	expect(solid.get("data") == before, "click-only element selection preserves mapping")
	_button(canvas, pick, true)
	_motion(canvas, pick + Vector2(10, 10))
	_button(canvas, pick + Vector2(10, 10), false)
	var element_after: PackedByteArray = solid.get("data")
	expect(element_after != before, "UV Face drag directly edits selected corners")
	undo.undo()
	expect(solid.get("data") == before, "one Undo restores direct face drag")
	undo.redo()
	expect(solid.get("data") == element_after, "Redo restores direct face drag")
	undo.undo()
	var place: Button = panel.find_child("UVPlaceMapping", true, false)
	place.pressed.emit()
	expect(not canvas.call("is_uv_element_mode") and place.button_pressed, "Place restores drag after UV element selection")
	_button(canvas, start, true)
	_motion(canvas, start + Vector2(30, 10))
	_button(canvas, start + Vector2(30, 10), false)
	expect(solid.get("data") != before, "placement works again after switching tools")
	paint.exit()
	undo.clear_history()
	panel.free()
	solid.free()
	undo.free()
	print("uv_workspace_drag_smoke: %d failures" % failures)
	quit(1 if failures else 0)
