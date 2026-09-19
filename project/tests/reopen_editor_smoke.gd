extends "res://tests/native_gizmo_editor_smoke.gd"

## Editor-level reopen test for demo scenes.
## Verifies SlabSolid editability after reopen (modelling controls visible).
## scripts/godot --editor --path project --script res://tests/reopen_editor_smoke.gd

var _scenes := [
	{"path": "res://demo/demo.tscn", "solid": "SlabModule/Box"},
	{"path": "res://demo/modeller_lab.tscn", "solid": "Box2"},
	{"path": "res://demo/relay_yard/relay_yard.tscn", "solid": null},
	{"path": "res://demo/signal_foundry/signal_foundry.tscn", "solid": null},
]


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
	await create_timer(1.0).timeout
	for scene_config in _scenes:
		if not FileAccess.file_exists(scene_config.path):
			print("SKIP %s (not found)" % scene_config.path)
			continue
		await _test_scene(editor, scene_config.path, scene_config.solid)
	print("REOPEN_EDITOR_RESULT failures=", failures)
	quit(1 if failures else 0)


func _test_scene(editor: Object, scene_path: String, solid_path: Variant) -> void:
	print("\n=== Editor testing %s ===" % scene_path)
	editor.open_scene_from_path(scene_path)
	editor.set_main_screen_editor("3D")
	var deadline := Time.get_ticks_msec() + 15000
	var stable_frames := 0
	while stable_frames < 20:
		await process_frame
		var edited: Node = editor.get_edited_scene_root()
		stable_frames = stable_frames + 1 if edited != null and edited.scene_file_path == scene_path else 0
		if Time.get_ticks_msec() > deadline:
			_check(false, "%s did not load in time" % scene_path.get_file())
			return
	var scene: Node = editor.get_edited_scene_root()
	_check(scene != null, "%s loaded" % scene_path.get_file())
	if scene == null:
		return
	var solids: Array[Node] = scene.find_children("*", "SlabSolid", true, false)
	_check(solids.size() >= 1, "%s has SlabSolids" % scene_path.get_file())
	if solids.is_empty():
		return
	var solid: Node3D = null
	if solid_path != null:
		solid = scene.get_node_or_null(NodePath(str(solid_path)))
	else:
		solid = solids[0] as Node3D
	if solid == null or not solid.is_class("SlabSolid"):
		_check(false, "%s target solid exists" % scene_path.get_file())
		return
	var data: PackedByteArray = solid.get("data")
	_check(data.size() >= 100, "%s/%s has topology data" % [scene_path.get_file(), solid.name])
	var face_count: int = int(solid.call("face_count"))
	_check(face_count >= 1, "%s/%s has faces" % [scene_path.get_file(), solid.name])
	var collider: CollisionShape3D = solid.get_node_or_null("__body/__shape")
	_check(collider != null, "%s/%s has collision" % [scene_path.get_file(), solid.name])
	if collider != null:
		_check(collider.shape is ConcavePolygonShape3D, "%s/%s has ConcavePolygonShape3D" % [scene_path.get_file(), solid.name])
	editor.get_selection().clear()
	editor.get_selection().add_node(solid)
	editor.edit_node(solid)
	await create_timer(0.3).timeout
	var plugin := _plugin(root)
	var panel: Control = plugin.get("_panel")
	var selection: RefCounted = plugin.get("_selection")
	selection.set_objects([solid])
	selection.mode = 3  # FACE mode
	var top_face := 0
	for id in solid.call("get_faces"):
		if solid.call("face_normal", id).y > 0.9:
			top_face = id
			break
	if top_face == 0:
		top_face = solid.call("get_faces")[0]
	selection.set_ids(PackedInt64Array([top_face]))
	await create_timer(0.3).timeout
	var mode_face := _mode(panel, 3)
	if mode_face != null:
		await _click(mode_face)
		await create_timer(0.2).timeout
	var inset_btn: Button = _button_named(panel.find_child("Commands", true, false), "Inset")
	_check(inset_btn != null, "%s/%s shows Inset command in face mode" % [scene_path.get_file(), solid.name])
	var extrude_btn: Button = _button_named(panel.find_child("Commands", true, false), "Extrude")
	_check(extrude_btn != null, "%s/%s shows Extrude command in face mode" % [scene_path.get_file(), solid.name])
	print("ok %s/%s is editable in panel" % [scene_path.get_file(), solid.name])


func _click(button: Button) -> void:
	if button == null or button.disabled or not button.is_visible_in_tree():
		_fail("Requested panel button is unavailable")
		return
	var position := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = position
		event.global_position = position
		button.get_viewport().push_input(event)
	await create_timer(0.2).timeout


func _mode(node: Node, value: int) -> Button:
	if node is Button and node.get_meta("slab_mode", -1) == value:
		return node
	for child in node.get_children():
		var found := _mode(child, value)
		if found != null:
			return found
	return null
