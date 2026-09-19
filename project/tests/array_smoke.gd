extends SceneTree

const ArrayTool := preload("res://addons/slab/slab_array.gd")
const Host := preload("res://tests/slab_test_host.gd")
const Undo := preload("res://tests/slab_test_undo.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
const Paint := preload("res://addons/slab/slab_paint.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("ok " if ok else "FAIL ", message)


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.name = "ArraySource"
	scene.add_child(solid)
	solid.owner = scene
	check(int(solid.call("make_box", Vector3(2, 3, 4))) == OK, "source box builds")
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.7, 0.9)
	solid.set("materials", [material])
	solid.set("collision_enabled", false)
	solid.transform = Transform3D(Basis.from_euler(Vector3(0, 0.25, 0)), Vector3(1, 2, 3))
	var source_data: PackedByteArray = solid.get("data")
	var source_transform := solid.transform
	var undo := Undo.new()
	var host = Host.over(scene).stub_undo(undo)
	var tool := ArrayTool.new(host)

	tool.count = 4
	tool.linear_step = Vector3(2.5, -0.5, 1)
	check(tool.begin(solid), "linear array begins for a scene SlabSolid")
	var preview := tool.preview_transforms()
	check(preview.size() == 3, "count includes source and previews three copies")
	check(preview[2].origin.is_equal_approx(Vector3(8.5, 0.5, 6)), "linear preview uses exact parent-local vector spacing")
	check(scene.get_child_count() == 1 and solid.get("data") == source_data, "preview does not mutate scene or source")
	tool.cancel()
	check(scene.get_child_count() == 1 and undo.actions.is_empty(), "cancel changes neither scene nor undo history")

	tool.begin(solid)
	var copies := tool.confirm()
	check(copies.size() == 3 and scene.get_child_count() == 4, "linear confirmation creates all copies")
	check(undo.actions.size() == 1, "all linear copies use one undo action")
	for index in copies.size():
		var copy := copies[index]
		check(copy.get("data") == source_data, "copy %d preserves serialized geometry" % index)
		check(copy.get("materials") == solid.get("materials"), "copy %d preserves materials" % index)
		check(copy.get("collision_enabled") == false, "copy %d preserves collision setting" % index)
		check(copy.owner == scene, "copy %d belongs to edited scene" % index)
		check(copy.basis.is_equal_approx(source_transform.basis), "copy %d preserves basis" % index)
	undo.undo()
	check(scene.get_child_count() == 1, "one undo removes every linear copy")
	undo.redo()
	check(scene.get_child_count() == 4, "one redo restores every linear copy")

	for copy in copies:
		if copy.get_parent() != null:
			copy.get_parent().remove_child(copy)
		copy.free()
	undo = Undo.new()
	host.stub_undo(undo)
	tool = ArrayTool.new(host)
	tool.mode = ArrayTool.Mode.RADIAL
	tool.count = 4
	tool.radial_center = Vector3(1, 2, 1)
	tool.radial_axis = Vector3.UP
	tool.radial_angle_degrees = 90.0
	tool.rotate_radial_copies = true
	tool.begin(solid)
	preview = tool.preview_transforms()
	check(preview[0].origin.is_equal_approx(Vector3(3, 2, 1)), "radial preview rotates position exactly 90 degrees")
	check(preview[2].origin.is_equal_approx(Vector3(-1, 2, 1)), "radial preview reaches exact 270-degree position")
	check(preview[0].basis.is_equal_approx(Basis(Vector3.UP, PI / 2.0) * source_transform.basis), "radial rotate option turns copy basis")
	tool.rotate_radial_copies = false
	preview = tool.refresh_preview()
	check(preview[0].basis.is_equal_approx(source_transform.basis), "radial copies can retain source orientation")
	copies = tool.confirm()
	check(copies.size() == 3 and undo.actions.size() == 1, "radial confirmation is one undo action")

	undo = Undo.new()
	host.stub_undo(undo)
	tool = ArrayTool.new(host)
	tool.begin(solid)
	solid.position.x += 1.0
	check(tool.confirm().is_empty(), "confirmation refuses a source changed after preview")
	check(undo.actions.is_empty(), "refused stale preview creates no undo action")

	var integrated: Node3D = ClassDB.instantiate("SlabSolid")
	integrated.name = "IntegratedArraySource"
	scene.add_child(integrated)
	integrated.owner = scene
	integrated.call("make_box", Vector3.ONE)
	check(integrated.call("build_mesh") is ArrayMesh, "preview geometry comes from SlabSolid.build_mesh")
	undo = Undo.new()
	host = Host.over(scene).stub_undo(undo)
	host.stub_host_selection([integrated])
	var viewport := SlabViewport.new(host)
	var selection = viewport.state()
	viewport.adopt_host_selection()
	var actions := Actions.new(selection, undo)
	viewport.bind_actions(actions)
	var paint := Paint.new()
	paint.bind(selection, actions, undo)
	viewport.bind_paint(paint)
	var children_before := scene.get_child_count()
	actions.run("array")
	check(actions.array_active and selection.array_preview_transforms.size() == 1, "Array command starts a visible transform preview")
	check(scene.get_child_count() == children_before, "integrated preview adds no scene nodes")
	actions.array_count = 3
	actions.array_linear_step = Vector3(0, 0, 2.25)
	actions.array_settings_changed.emit()
	check(selection.array_preview_transforms.size() == 2, "settings refresh integrated preview count")
	check(selection.array_preview_transforms[1].origin.z == integrated.position.z + 4.5, "settings refresh exact integrated spacing")
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	check(viewport.handle(null, enter) == SlabViewport.Verdict.STOP, "Enter is consumed by Array modal")
	check(not actions.array_active and scene.get_child_count() == children_before + 2, "Enter confirms integrated copies")
	check(undo.actions.size() == 1, "integrated confirmation records one undo action")

	host.stub_host_selection([integrated])
	viewport.adopt_host_selection()
	actions.run("array")
	selection.mode = 1
	check(not actions.array_active and selection.array_preview_transforms.is_empty(), "mode change cancels Array preview")
	selection.mode = 0
	host.stub_host_selection([integrated])
	viewport.adopt_host_selection()
	actions.run("array")
	paint.enter()
	check(paint.active and not actions.array_active, "opening UV workspace cancels Array")
	selection.mode = 0
	host.stub_host_selection([integrated])
	viewport.adopt_host_selection()
	actions.run("array")
	check(actions.array_active and not paint.active, "starting Array closes UV workspace")
	actions.run("plane_cut")
	check(not actions.array_active and actions.plane_active, "starting Plane Cut cancels Array")
	actions.run("array")
	check(actions.array_active and not actions.plane_active, "starting Array cancels Plane Cut")
	actions.array_cancel_requested.emit()
	check(not actions.array_active and selection.array_preview_transforms.is_empty(), "Cancel clears integrated preview")

	print("array_smoke: %d failures" % failures)
	scene.free()
	quit(1 if failures else 0)
