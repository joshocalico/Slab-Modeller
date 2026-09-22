extends SceneTree

const ProjectionAdapter := preload("res://addons/slab/slab_editor_projection.gd")
const Pick := preload("res://addons/slab/slab_pick.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)


func _view_fixture(size: Vector2i) -> Dictionary:
	var wrapper := Control.new()
	root.add_child(wrapper)
	var container := SubViewportContainer.new()
	wrapper.add_child(container)
	var view := SubViewport.new()
	view.size = size
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(view)
	var surface := Control.new()
	wrapper.add_child(surface)
	return {"wrapper": wrapper, "view": view, "surface": surface}


func _run() -> void:
	root.size = Vector2i(1225, 768)
	var source := Camera3D.new()
	root.add_child(source)
	var source_parent := source.get_parent()
	var source_transform := source.transform
	var first := _view_fixture(Vector2i(640, 260))
	var second := _view_fixture(Vector2i(320, 500))
	var views := [first.view, second.view]
	_check(root.size == Vector2i(1225, 768) and first.view.size == Vector2i(640, 260),
		"scene and editor viewport retain distinct sizes and aspect ratios")
	_check(ProjectionAdapter.input_view(source, views, first.surface, second.surface) == first.view,
		"hovered preview surface wins over another split view's keyboard focus")
	_check(ProjectionAdapter.input_view(source, views, null, second.surface) == second.view,
		"held gestures retain their focused editor viewport")
	_check(ProjectionAdapter.input_view(source, views, null, null) == null,
		"an unidentified preview surface cannot silently use window coordinates")
	var reference := Camera3D.new()
	first.view.add_child(reference)
	reference.make_current()
	var adapter := ProjectionAdapter.new()
	root.add_child(adapter)
	var solid := ClassDB.instantiate("SlabSolid") as Node3D
	root.add_child(solid)
	solid.call("make_box", Vector3.ONE)
	solid.position = Vector3(-0.5, -0.5, -5)
	await process_frame
	# Reproduce Godot Preview: the scene camera's RID renders in another viewport,
	# while Camera3D.get_viewport() continues to return the scene's root window.
	RenderingServer.viewport_attach_camera(first.view.get_viewport_rid(), source.get_camera_rid())
	var centre := Vector2(first.view.size) * 0.5
	_check(Pick.pick_solid(root, source, centre) != solid,
		"unadapted scene camera reproduces the wrong pick at editor-view centre")
	var adapted: Camera3D = adapter.camera_for(source, first.view)
	_check(Pick.pick_solid(root, adapted, centre) == solid,
		"preview pick hits the solid rendered at editor-view centre")
	var overlay := adapted.unproject_position(Vector3(0, 0, -4.5))
	_check(overlay.is_equal_approx(centre), "preview overlay and pick share the same screen centre")
	source.position = Vector3(3, 2, 1)
	source.rotation = Vector3(0.1, 0.4, 0)
	source_transform = source.transform
	reference.global_transform = source.global_transform
	source.near = 0.12
	source.far = 50
	reference.near = source.near
	reference.far = source.far
	for mode in [Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_ORTHOGONAL, Camera3D.PROJECTION_FRUSTUM]:
		for aspect in [Camera3D.KEEP_HEIGHT, Camera3D.KEEP_WIDTH]:
			source.projection = mode
			source.keep_aspect = aspect
			source.fov = 51
			source.size = 4
			source.frustum_offset = Vector2(0.12, -0.07)
			source.h_offset = 0.2
			source.v_offset = -0.1
			reference.projection = mode
			reference.keep_aspect = aspect
			reference.fov = source.fov
			reference.size = source.size
			reference.frustum_offset = source.frustum_offset
			reference.h_offset = source.h_offset
			reference.v_offset = source.v_offset
			adapted = adapter.camera_for(source, first.view)
			var matches := true
			for point in [centre, Vector2(60, 70), Vector2(510, 210)]:
				matches = matches and adapted.project_ray_origin(point).is_equal_approx(reference.project_ray_origin(point))
				matches = matches and adapted.project_ray_normal(point).is_equal_approx(reference.project_ray_normal(point))
			matches = matches and adapted.unproject_position(Vector3(0.4, 0.2, -5)).is_equal_approx(reference.unproject_position(Vector3(0.4, 0.2, -5)))
			_check(matches, "preview rays and overlays match rendered projection mode=%s aspect=%s" % [mode, aspect])
	_check(source.get_parent() == source_parent and source.transform == source_transform
		and source.fov == 51 and is_equal_approx(source.h_offset, 0.2) and is_equal_approx(source.v_offset, -0.1),
		"projection adaptation leaves authored camera and scene placement unchanged")
	_check(first.view.get_camera_3d() == reference and root.get_camera_3d() == source and source.get_viewport() == root,
		"adapter does not replace either real viewport's camera")
	_check(adapter.camera_for(reference, first.view) == reference,
		"normal editor navigation uses the original camera unchanged")
	first.view.size = Vector2i(810, 330)
	source.position.x += 0.5
	adapted = adapter.refresh_camera(adapted)
	_check(adapted.global_transform == source.global_transform,
		"overlay redraw refreshes an authored camera move without another input event")
	_check(adapted.get_viewport().size == first.view.size,
		"resizing the editor viewport updates the projection coordinate space")
	var camera_ref: WeakRef = weakref(adapted)
	var viewport_ref: WeakRef = weakref(adapted.get_viewport())
	adapter.free()
	_check(camera_ref.get_ref() == null and viewport_ref.get_ref() == null,
		"adapter teardown releases its camera and non-rendering viewport")
	first.wrapper.free()
	second.wrapper.free()
	solid.free()
	source.free()
	print("preview_projection_smoke failures=", failures)
	quit(1 if failures else 0)
