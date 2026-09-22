extends "res://tests/native_gizmo_editor_smoke.gd"

const FIXTURE := "res://tests/isolation_save_fixture.tscn"


func _run() -> void:
	var editor := Engine.get_singleton("EditorInterface")
	var deadline := Time.get_ticks_msec() + 30000
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		if Time.get_ticks_msec() > deadline:
			_fail("Editor initialization timed out")
			return
		await process_frame
	var fixture := Node3D.new()
	fixture.name = "IsolationSave"
	for label in ["Selected", "Other", "Hidden"]:
		var solid: Node3D = ClassDB.instantiate("SlabSolid")
		solid.name = label
		fixture.add_child(solid)
		solid.owner = fixture
		solid.call("make_box", Vector3.ONE)
		solid.visible = label != "Hidden"
	var packed := PackedScene.new()
	_check(packed.pack(fixture) == OK, "fixture packs")
	_check(ResourceSaver.save(packed, FIXTURE) == OK, "fixture saves")
	fixture.free()
	editor.open_scene_from_path(FIXTURE)
	var scene: Node
	while scene == null or scene.scene_file_path != FIXTURE:
		await process_frame
		scene = editor.get_edited_scene_root()
		if Time.get_ticks_msec() > deadline:
			_fail("Fixture did not open")
			return
	await process_frame
	var plugin := _plugin(root)
	var selection: RefCounted = plugin.get("_selection")
	selection.set_objects([scene.get_node("Selected")])
	_check(selection.enter_isolation(scene), "editor enters isolation")
	_check(not scene.get_node("Other").visible, "editor hides other solid")
	_check(editor.save_scene() == OK, "EditorInterface saves isolated scene")
	await process_frame
	_check(selection.isolated and not scene.get_node("Other").visible, "save keeps editor isolation")
	var saved: PackedScene = ResourceLoader.load(FIXTURE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var reopened := saved.instantiate()
	_check(reopened.get_node("Other").visible, "saved scene preserves other visibility")
	_check(not reopened.get_node("Hidden").visible, "saved scene preserves intentional hiding")
	reopened.free()
	plugin._on_scene_changed(null)
	_check(not selection.isolated and scene.get_node("Other").visible, "scene switch restores visibility")
	selection.set_objects([scene.get_node("Selected")])
	selection.enter_isolation(scene)
	editor.set_plugin_enabled("slab", false)
	_check(scene.get_node("Other").visible, "plugin disable restores visibility")
	editor.set_plugin_enabled("slab", true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
	print("ISOLATION_SAVE_EDITOR_RESULT failures=", failures)
	quit(1 if failures else 0)
