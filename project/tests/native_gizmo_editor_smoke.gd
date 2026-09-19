extends SceneTree

# Run in a dedicated editor; never saves the scene.
# scripts/godot --editor --path project --script res://tests/native_gizmo_editor_smoke.gd -- /tmp/gesture.json
# Optional JSON: scene, node, tool (W/E/R), pivot (0/1/2), orientation (0/1/2),
# custom_pivot [x,y,z], start/end [x,y] in native viewport Control coordinates.
# delay, step_delay and after_drag_delay are seconds for visual inspection.
# rotation_degrees/scale configure the test object without saving. cancel sends Escape.
# Test setup uses editor selection state. The gesture enters Godot's native
# Node3DEditorViewport::_sinput through its connected gui_input signal.

const Selection := preload("res://addons/slab/slab_selection.gd")
const Frame := preload("res://addons/slab/slab_selection_frame.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")
var failures := 0

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void: _fail("Native editor test exceeded 90 seconds"))
	_run.call_deferred()

func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("Requires --editor")
		return
	var config: Dictionary = {}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
		if not parsed is Dictionary:
			_fail("Config must be a JSON object")
			return
		config = parsed
	var editor := Engine.get_singleton("EditorInterface")
	var deadline := Time.get_ticks_msec() + 30000
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		if Time.get_ticks_msec() > deadline:
			_fail("Editor initialization timed out")
			return
		await process_frame
	var scene_path: String = config.get("scene", "res://demo/modeller_lab.tscn")
	editor.open_scene_from_path(scene_path)
	editor.set_main_screen_editor("3D")
	while editor.get_edited_scene_root() == null or editor.get_edited_scene_root().scene_file_path != scene_path:
		if Time.get_ticks_msec() > deadline:
			_fail("Scene initialization timed out")
			return
		await process_frame
	var scene: Node = editor.get_edited_scene_root()
	var solid := scene.get_node_or_null(NodePath(config.get("node", "Box2"))) as Node3D
	if solid == null or not solid.is_class("SlabSolid"):
		_fail("Requested SlabSolid was not found")
		return
	if config.has("rotation_degrees"):
		solid.rotation_degrees = Vector3(config.rotation_degrees[0], config.rotation_degrees[1], config.rotation_degrees[2])
	if config.has("scale"):
		solid.scale = Vector3(config.scale[0], config.scale[1], config.scale[2])
	var plugin := _plugin(root)
	editor.get_selection().clear()
	editor.get_selection().add_node(solid)
	editor.edit_node(solid)
	await process_frame
	var selection: RefCounted = plugin.get("_selection")
	_prepare_selection(selection, solid, config)
	var viewport: SubViewport = editor.get_editor_viewport_3d(0)
	var surface := _surface(viewport.get_parent().get_parent())
	if surface == null:
		_fail("Native viewport gui_input recipient was not found")
		return
	var tool: String = config.get("tool", "W")
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Slab Native Gizmo Test " + tool)
	var spatial: Node = plugin.spatial_editor_root(viewport)
	var tool_button: Button = null
	for candidate in spatial.find_children("*", "Button", true, false):
		if plugin.shortcut_has_key(candidate.shortcut, OS.find_keycode_from_string(tool)):
			tool_button = candidate
			break
	if tool_button == null:
		_fail("Native transform tool was not found: " + tool)
		return
	tool_button.pressed.emit()
	# The editor restores selection asynchronously after opening the scene.
	# Wait for a stable configured selection instead of relying on a fixed delay.
	var stable_frames := 0
	var frame: Dictionary = {}
	deadline = Time.get_ticks_msec() + 15000
	while stable_frames < 20:
		await process_frame
		frame = Frame.from_selection(selection)
		if not frame.get("valid", false) or selection.solid != solid or selection.ids.is_empty():
			stable_frames = 0
			if not editor.get_selection().get_selected_nodes().has(solid):
				editor.get_selection().clear()
				editor.get_selection().add_node(solid)
				editor.edit_node(solid)
			_prepare_selection(selection, solid, config)
		else:
			stable_frames += 1
		if Time.get_ticks_msec() > deadline:
			_fail("Configured native selection did not stabilize")
			return
	# Frame the selected solid through the same native shortcut used in the editor.
	# This keeps the injected gesture within a visible, usable viewport.
	if bool(config.get("front_view", false)):
		var view := InputEventKey.new()
		view.keycode = KEY_KP_1
		view.physical_keycode = KEY_KP_1
		view.pressed = true
		surface.gui_input.emit(view)
		await create_timer(0.2).timeout
	var focus := InputEventKey.new()
	focus.keycode = KEY_F
	focus.physical_keycode = KEY_F
	focus.pressed = true
	surface.gui_input.emit(focus)
	await create_timer(0.5).timeout
	for i in 20: await process_frame
	frame = Frame.from_selection(selection)
	if not frame.get("valid", false):
		_fail("Selection was cleared while focusing the native viewport")
		return
	var camera := viewport.get_camera_3d()
	var world: Transform3D = frame.world
	var cam_z := -camera.global_basis.z
	var cam_y := -camera.global_basis.y
	var distance := absf(Plane(cam_z, camera.global_position).distance_to(world.origin))
	var projected_depth := camera.global_position + cam_z * distance
	var pixels_per_unit := absf(camera.unproject_position(projected_depth).y - camera.unproject_position(projected_depth + cam_y).y)
	if pixels_per_unit <= 0.00001:
		_fail("Cannot project native gizmo size")
		return
	var editor_scale := maxf(1.0, float(editor.get_editor_scale()))
	var manipulator_size: float = editor.get_editor_settings().get_setting("editors/3d/manipulator_gizmo_size")
	var container_height: float = viewport.get_parent().size.y
	var gizmo_scale := manipulator_size / pixels_per_unit * editor_scale * minf(400.0 * editor_scale, container_height) / (400.0 * editor_scale)
	var screen_ratio := surface.size / Vector2(viewport.size)
	var origin: Vector2 = camera.unproject_position(world.origin) * screen_ratio
	var axes: Array[Vector3] = [world.basis.x, world.basis.y, world.basis.z]
	var axis_index := 0
	var best_score := -1.0
	for index in 3:
		var projection := camera.unproject_position(world.origin + axes[index]) * screen_ratio - origin
		var score := absf(axes[index].dot(cam_z)) if tool == "E" else projection.length()
		if score > best_score:
			best_score = score
			axis_index = index
	if config.has("axis_index"):
		axis_index = int(config.axis_index)
	var drag_axis := axes[axis_index]
	var projected: Vector2 = camera.unproject_position(world.origin + drag_axis) * screen_ratio - origin
	var direction := projected.normalized()
	var handle_distance: float = float(config.get("handle_distance", 1.475 if tool == "R" else 1.575))
	var start: Vector2 = camera.unproject_position(world.origin + drag_axis * gizmo_scale * handle_distance) * screen_ratio
	var end: Vector2 = start + direction * 35.0
	if tool == "E":
		start = camera.unproject_position(world.origin + (axes[(axis_index + 1) % 3] * cos(0.6) + axes[(axis_index + 2) % 3] * sin(0.6)) * gizmo_scale * 1.1) * screen_ratio
		end = camera.unproject_position(world.origin + (axes[(axis_index + 1) % 3] * cos(0.9) + axes[(axis_index + 2) % 3] * sin(0.9)) * gizmo_scale * 1.1) * screen_ratio
	if config.has("start"): start = Vector2(config.start[0], config.start[1])
	if config.has("end"): end = Vector2(config.end[0], config.end[1])
	var visible_rect := Rect2(Vector2.ZERO, surface.size)
	if not visible_rect.has_point(start) or not visible_rect.has_point(end):
		_fail("Native gesture is outside the visible viewport: start=%s end=%s size=%s" % [start, end, surface.size])
		return
	print("NATIVE_READY ", JSON.stringify({"tool": tool, "axis_index": axis_index, "surface_position": str(surface.global_position), "surface_size": str(surface.size), "origin": str(origin), "start": str(start), "end": str(end)}))
	await create_timer(float(config.get("delay", 2.0))).timeout
	if not Frame.from_selection(selection).get("valid", false):
		_fail("Selection was cleared before the native gesture")
		return
	await _capture(editor, config, "before")
	var before: PackedByteArray = solid.get("data")
	var vertices_before := _vertices(solid)
	var node_before := solid.transform
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	var history := manager.get_history_undo_redo(manager.get_object_history_id(solid))
	var version := history.get_version()
	if bool(config.get("paint_empty_gesture", false)):
		var configured_mode: int = selection.mode
		var configured_ids: PackedInt64Array = selection.ids.duplicate()
		await _check_paint_empty_gesture(plugin, scene, solid, selection, camera, surface, start, end,
			history, before, node_before, version, configured_mode, configured_ids)
		quit(1 if failures else 0)
		return
	_button(surface, start, true)
	await process_frame
	var previous: Vector2 = start
	for step in range(1, 21):
		var position: Vector2 = start.lerp(end, step / 20.0)
		var motion := InputEventMouseMotion.new()
		motion.position = position
		motion.global_position = surface.global_position + position
		motion.relative = position - previous
		motion.screen_relative = motion.relative
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		surface.gui_input.emit(motion)
		previous = position
		if float(config.get("step_delay", 0.0)) > 0:
			await create_timer(float(config.step_delay)).timeout
		else:
			await process_frame
	if bool(config.get("cancel", false)):
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		surface.gui_input.emit(escape)
		await process_frame
	_button(surface, end, false)
	for i in 3: await process_frame
	var after: PackedByteArray = solid.get("data")
	var action_name := history.get_current_action_name()
	await _capture(editor, config, "after")
	print("NATIVE_DRAG_FINISHED ", JSON.stringify({"changed": after != before, "after_sha256": _hash(after)}))
	if float(config.get("after_drag_delay", 0.0)) > 0:
		await create_timer(float(config.after_drag_delay)).timeout
	_check(solid.transform == node_before, "node_transform_unchanged")
	if bool(config.get("cancel", false)):
		_check(after == before, "cancel_exact_restore")
		_check(history.get_version() == version, "cancel_creates_no_action")
	else:
		_check(after != before, "mesh_changed")
		_check(history.get_version() != version, "native_undo_action_created")
		if tool == "W" and after != before:
			var vertices_after := _vertices(solid)
			var first_id: int = vertices_before.keys()[0]
			var delta: Vector3 = vertices_after[first_id] - vertices_before[first_id]
			var max_error := 0.0
			for id in vertices_before:
				max_error = maxf(max_error, ((vertices_after[id] - vertices_before[id]) as Vector3).distance_to(delta))
			_check(max_error < 0.01, "move_translates_every_vertex_equally")
		if history.get_version() != version:
			_check(history.get_current_action_name() == "Slab Transform Elements", "element_action_name")
			history.undo()
			_check(solid.get("data") == before, "undo_exact_restore")
			history.redo()
			_check(solid.get("data") == after, "redo_exact_restore")
			history.undo()
	print("NATIVE_RESULT ", JSON.stringify({"tool": tool, "failures": failures, "before_sha256": _hash(before), "after_sha256": _hash(after), "restored_sha256": _hash(solid.get("data")), "action_name": action_name, "motion_button_mask": MOUSE_BUTTON_MASK_LEFT, "motion_count": 20}))
	quit(1 if failures else 0)


func _check_paint_empty_gesture(plugin: EditorPlugin, scene: Node, solid: Node3D, selection: RefCounted,
		camera: Camera3D, surface: Control, start: Vector2, end: Vector2, history: UndoRedo,
		before: PackedByteArray, node_before: Transform3D, version: int,
		configured_mode: int, configured_ids: PackedInt64Array) -> void:
	selection.mode = Selection.Mode.OBJECT
	selection.set_ids(PackedInt64Array())
	_check(not solid.has_meta("_edit_lock_"), "solid_unlocked_before_paint_entry")
	var paint_button := _button_named(plugin.get("_panel"), "Surface Paint")
	paint_button.pressed.emit()
	for i in 3: await process_frame
	_check(plugin.get("_paint").active, "surface_paint_entered_without_face_ids")
	_check(solid.has_meta("_edit_lock_") and solid.get_meta("_edit_lock_") == true,
		"paint_entry_hides_native_transform_gizmo_via_edit_lock")
	_check(SlabPick.pick_world_hit(scene, camera, start).is_empty(), "native_gizmo_axis_start_is_outside_geometry")
	await _native_drag(surface, start, end)
	_check(solid.get("data") == before, "paint_empty_drag_keeps_exact_mesh_data")
	_check(solid.transform == node_before, "paint_empty_drag_keeps_node_transform")
	_check(history.get_version() == version, "paint_empty_drag_creates_no_history")
	_check(selection.ids.is_empty(), "paint_empty_drag_selects_nothing")
	paint_button.pressed.emit()
	for i in 3: await process_frame
	_check(not solid.has_meta("_edit_lock_"), "paint_exit_restores_native_transform_gizmo")
	selection.mode = configured_mode
	selection.set_ids(configured_ids)
	for i in 10: await process_frame
	await _native_drag(surface, start, end)
	_check(solid.get("data") != before, "same_native_axis_drag_works_after_paint_exit")
	_check(history.get_version() != version, "post_paint_native_drag_creates_history")
	if history.get_version() != version:
		history.undo()
		_check(solid.get("data") == before, "post_paint_native_drag_undo_restores_mesh")
	print("NATIVE_RESULT ", JSON.stringify({"tool": "paint_empty_gesture", "failures": failures}))


func _native_drag(surface: Control, start: Vector2, end: Vector2) -> void:
	_button(surface, start, true)
	await process_frame
	var previous := start
	for step in range(1, 21):
		var position := start.lerp(end, step / 20.0)
		var motion := InputEventMouseMotion.new()
		motion.position = position
		motion.global_position = surface.global_position + position
		motion.relative = position - previous
		motion.screen_relative = motion.relative
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		surface.gui_input.emit(motion)
		previous = position
		await process_frame
	_button(surface, end, false)
	for i in 3: await process_frame


func _capture(editor: Object, config: Dictionary, stage: String) -> void:
	if DisplayServer.get_name() == "headless" or not config.has("capture_prefix"):
		return
	# The editor can stop drawing when covered or idle. Request a real frame
	# before reading its texture instead of waiting for an unsolicited draw.
	RenderingServer.force_sync()
	RenderingServer.force_draw(true)
	var image: Image = editor.get_base_control().get_viewport().get_texture().get_image()
	if config.has("capture_rect"):
		image = image.get_region(Rect2i(config.capture_rect))
	var output: String = str(config.capture_prefix) + "-" + stage + ".png"
	var result := image.save_png(output)
	_check(result == OK, "capture_" + stage)
	print("NATIVE_CAPTURE ", JSON.stringify({"stage": stage, "path": output, "error": result}))

func _vertices(solid: Node3D) -> Dictionary:
	var positions: Dictionary = {}
	for id in solid.call("get_vertices"):
		positions[id] = solid.to_global(solid.call("vertex_position", id))
	return positions

func _prepare_selection(selection: RefCounted, solid: Node3D, config: Dictionary) -> void:
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE if int(config.get("orientation", 0)) == 2 else Selection.Mode.VERTEX
	selection.set_ids(solid.call("get_faces") if selection.mode == Selection.Mode.FACE else solid.call("get_vertices"))
	var custom: Array = config.get("custom_pivot", [0, 0, 0])
	selection.configure_pivot(int(config.get("pivot", 0)), Vector3(custom[0], custom[1], custom[2]))
	selection.configure_orientation(int(config.get("orientation", 0)))

func _plugin(node: Node) -> EditorPlugin:
	var script: Script = node.get_script()
	if script != null and script.resource_path == "res://addons/slab/plugin.gd": return node as EditorPlugin
	for child in node.get_children():
		var found := _plugin(child)
		if found != null: return found
	return null

func _surface(node: Node) -> Control:
	for child in node.get_children():
		if child is Control:
			for connection in child.get_signal_connection_list("gui_input"):
				if str(connection.callable).contains("::_sinput"): return child
	return null

func _button_named(node: Node, label: String) -> Button:
	if node is Button and String(node.get_meta("slab_label", node.text)) == label:
		return node
	for child in node.get_children():
		var found := _button_named(child, label)
		if found != null:
			return found
	return null

func _button(surface: Control, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = surface.global_position + position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	surface.gui_input.emit(event)

func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("NATIVE_CHECK ", JSON.stringify({"check": label, "passed": ok}))

func _fail(message: String) -> void:
	printerr("NATIVE_FAILURE ", message)
	quit(1)
