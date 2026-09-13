extends SceneTree

const SlabPaint := preload("res://addons/slab/slab_paint.gd")
const SlabPaintUv := preload("res://addons/slab/slab_paint_uv.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")

var _fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _expect(ClassDB.class_exists("SlabSolid"), "SlabSolid is registered"):
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var solid_a: Node3D = ClassDB.instantiate("SlabSolid")
	var solid_b: Node3D = ClassDB.instantiate("SlabSolid")
	world.add_child(solid_a)
	world.add_child(solid_b)
	solid_a.position.x = -2.0
	solid_b.position.x = 2.0
	solid_a.call("make_box", Vector3(2, 2, 2))
	solid_b.call("make_box", Vector3(2, 2, 2))
	var top_a: int = _top_face(solid_a)
	var top_b: int = _top_face(solid_b)
	var selection := SlabSelection.new()
	selection.mode = SlabSelection.Mode.FACE
	var actions := SlabActions.new(selection)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, SlabTestUndo.new())
	paint.enter()
	var mat_a: StandardMaterial3D = _make_unique(paint, selection, actions, solid_a, top_a, Color(0.1, 0.25, 0.8))
	var mat_b: StandardMaterial3D = _make_unique(paint, selection, actions, solid_b, top_b, Color(0.1, 0.8, 0.25))
	paint.tool = SlabPaint.Tool.PIXEL
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0, 8, 7), Vector3.ZERO, Vector3.UP)
	camera.current = true
	var screen_a: Vector2 = camera.unproject_position(solid_a.to_global(solid_a.call("face_centroid", top_a)))
	var screen_b: Vector2 = camera.unproject_position(solid_b.to_global(solid_b.call("face_centroid", top_b)))
	selection.set_objects([solid_a])
	selection.set_ids(PackedInt64Array([top_a]))
	actions.material_slot = int(solid_a.call("face_uv", top_a).get("slot", -1))
	paint.rebind()
	_expect(paint.material() == mat_a, "A is selected before clicking B")
	var before_a: PackedByteArray = mat_a.albedo_texture.get_image().get_data()
	var unpainted_b: PackedByteArray = mat_b.albedo_texture.get_image().get_data()
	paint.handle_3d(camera, _button(screen_b, true), world)
	paint.handle_3d(camera, _button(screen_b, false), world)
	_expect(paint.material() == mat_b, "click binds the hit face material")
	_expect(mat_a.albedo_texture.get_image().get_data() == before_a, "clicking B does not paint selected A")
	_expect(mat_b.albedo_texture.get_image().get_data() != unpainted_b, "clicking B paints B")

	var before_b: PackedByteArray = mat_b.albedo_texture.get_image().get_data()
	var local_a: Vector3 = solid_a.call("face_centroid", top_a)
	var local_a2: Vector3 = local_a + Vector3(0.6, 0.0, 0.0)
	var screen_a2: Vector2 = camera.unproject_position(solid_a.to_global(local_a2))
	var uv_a: Vector2 = SlabPaintUv.point_uv(solid_a, top_a, local_a)
	var uv_a2: Vector2 = SlabPaintUv.point_uv(solid_a, top_a, local_a2)
	var image_a: Image = mat_a.albedo_texture.get_image()
	var midpoint_uv: Vector2 = uv_a.lerp(uv_a2, 0.5)
	var midpoint: Vector2i = SlabPaintUv.uv_to_pixel(
		midpoint_uv, image_a.get_width(), image_a.get_height())
	var midpoint_before: Color = image_a.get_pixelv(midpoint)
	paint.brush_radius = 1.0
	paint.handle_3d(camera, _button(screen_a, true), world)
	paint.handle_3d(camera, _motion(screen_b), world)
	paint.handle_3d(camera, _motion(screen_a2), world)
	paint.handle_3d(camera, _button(screen_b, false), world)
	_expect(mat_b.albedo_texture.get_image().get_data() == before_b, "dragging onto another material does not paint it")
	_expect(paint.material() == mat_a, "dragging keeps the stroke material bound")
	var midpoint_after: Color = mat_a.albedo_texture.get_image().get_pixelv(midpoint)
	_expect(midpoint_after.is_equal_approx(midpoint_before),
		"returning after a rejected hit does not interpolate across the gap")

	solid_b.call("set_face_material", PackedInt64Array([top_b]), 0)
	paint.handle_3d(camera, _motion(screen_b), world)
	var preview: MeshInstance3D = paint.brush_preview()
	_expect(preview == null or not preview.visible, "hover hides the brush on a non-owned material")

	var mats_b: Array = solid_b.get("materials")
	mats_b.append(mat_a)
	solid_b.set("materials", mats_b)
	solid_b.call("set_face_material", PackedInt64Array([top_b]), mats_b.size() - 1)
	paint.handle_3d(camera, _button(screen_a, true), world)
	var after_shared_down: PackedByteArray = mat_a.albedo_texture.get_image().get_data()
	paint.handle_3d(camera, _motion(screen_b), world)
	paint.handle_3d(camera, _button(screen_b, false), world)
	_expect(paint.material() == mat_a, "shared material identity remains the stroke target across solids")
	_expect(mat_a.albedo_texture.get_image().get_data() != after_shared_down,
		"dragging across solids paints their shared material")

	var packed := PackedScene.new()
	_expect(packed.pack(solid_a) == OK, "owned paint solid packs")
	var reopened: Node3D = packed.instantiate()
	root.add_child(reopened)
	var reopened_slot: int = int(reopened.call("face_uv", top_a).get("slot", -1))
	var reopened_material: StandardMaterial3D = (reopened.get("materials") as Array)[reopened_slot]
	_expect(paint.is_owned(reopened_material), "reopened material keeps paint ownership")
	selection.set_objects([reopened])
	selection.set_ids(PackedInt64Array([top_a]))
	actions.material_slot = reopened_slot
	paint.rebind()
	_expect(paint.begin_stroke(), "reopened owned material remains editable")
	paint.cancel_stroke()
	reopened.free()
	paint.exit()
	world.free()
	_finish()


func _make_unique(paint: RefCounted, selection: RefCounted, actions: RefCounted,
		solid: Node3D, face: int, color: Color) -> StandardMaterial3D:
	var shared := StandardMaterial3D.new()
	shared.albedo_color = color
	solid.set("materials", [shared])
	selection.set_objects([solid])
	selection.set_ids(PackedInt64Array([face]))
	actions.material_slot = 0
	paint.rebind()
	paint.make_unique()
	return paint.material()


func _button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = position
	return event


func _motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = position
	return event


func _top_face(solid: Node3D) -> int:
	var best := 0
	var up := -2.0
	for id in PackedInt64Array(solid.call("get_faces")):
		var y: float = (solid.call("face_normal", id) as Vector3).y
		if y > up:
			up = y
			best = id
	return best


func _expect(ok: bool, message: String) -> bool:
	if ok:
		print("ok ", message)
		return true
	push_error("FAIL " + message)
	_fails += 1
	return false


func _finish() -> void:
	if _fails > 0:
		push_error("%d paint_hit_scope_smoke failures" % _fails)
		quit(1)
		return
	print("paint_hit_scope_smoke ok")
	quit(0)
