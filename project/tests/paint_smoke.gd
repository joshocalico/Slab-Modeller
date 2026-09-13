extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPaint := preload("res://addons/slab/slab_paint.gd")
const SlabPaintUv := preload("res://addons/slab/slab_paint_uv.gd")
const SlabPaintRaster := preload("res://addons/slab/slab_paint_raster.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")
const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
const SlabTestHost := preload("res://tests/slab_test_host.gd")
const SlabPaintCanvas := preload("res://addons/slab/slab_paint_canvas.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")

var _fails := 0


func _init() -> void:
	call_deferred("_boot")


func _boot() -> void:
	if not _expect(ClassDB.class_exists("SlabSolid"), "SlabSolid is registered"):
		_finish()
		return
	_check_uv_matches_emit()
	_check_texture_resolution_coherence()
	_check_material_labels()
	_check_uv_modifier_dispatch()
	_check_brush_preview_caption()
	_check_uv_transform_and_wrap()
	_check_numeric_uv_apply_and_selection_sync()
	_check_uv_drag_transaction()
	_check_cylinder_and_concave()
	_check_raster_wrap_and_stroke()
	_check_wrap_outline_tiles()
	_check_unique_paint_undo_save()
	_check_unique_copies_full_material_and_needs_a_face()
	_check_undo_after_switching_slots()
	_check_engine_undo_switch_save_escape()
	_check_dark_texture_preserved()
	_check_imported_svg_unique_stroke_roundtrip()
	await _check_canvas_letterbox_and_press()
	_check_scene_roundtrip()
	await process_frame
	await process_frame
	_check_viewport_paint_does_not_extrude()
	_finish()


func _check_material_labels() -> void:
	var named := StandardMaterial3D.new()
	named.resource_name = "Named Copper"
	var external := StandardMaterial3D.new()
	external.take_over_path("res://materials/external_brick.tres")
	var built_in := StandardMaterial3D.new()
	built_in.take_over_path("res://demo/test_scene.tscn::StandardMaterial3D_abc")
	_expect(SlabPaint.material_label(named, 2) == "Named Copper", "material labels prefer explicit resource names")
	_expect(SlabPaint.material_label(external, 2) == "external_brick", "external material labels use the resource filename")
	_expect(SlabPaint.material_label(built_in, 2) == "Material 3", "built-in material labels avoid scene subresource IDs")
	_expect(SlabPaint.material_label(StandardMaterial3D.new(), -1) == "New material", "unassigned materials have a stable label")


func _check_brush_preview_caption() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var faces: PackedInt64Array = solid.call("get_faces")
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([faces[0]]))
	var actions := SlabActions.new(selection)
	var undo := SlabTestUndo.new()
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	var assigned := StandardMaterial3D.new()
	assigned.resource_name = "Limestone"
	var preview := StandardMaterial3D.new()
	preview.resource_name = "Limestone"
	solid.set("materials", [assigned, preview])
	paint.enter()
	_expect(paint.brush_preview_caption().is_empty(), "matching selected material keeps the UV gesture hint")
	var imported_preview := StandardMaterial3D.new()
	imported_preview.resource_name = "Copper"
	var before_choice_materials: Array = (solid.get("materials") as Array).duplicate()
	var before_choice_data: PackedByteArray = solid.get("data")
	var before_choice_undo: int = undo.actions.size()
	paint.choose_brush_material(imported_preview)
	_expect(paint.brush_material() == imported_preview and paint.brush_preview_caption().contains("Assign to apply")
		and solid.get("materials") == before_choice_materials and solid.get("data") == before_choice_data
		and undo.actions.size() == before_choice_undo,
		"choosing an imported brush previews without mutating geometry or Undo")
	paint.assign_active_to_selection()
	_expect((solid.get("materials") as Array).has(imported_preview) and solid.get("data") != before_choice_data
		and undo.actions.size() == before_choice_undo + 1,
		"Assign applies the chosen brush as one undoable geometry edit")
	undo.undo()
	_expect(solid.get("materials") == before_choice_materials and solid.get("data") == before_choice_data,
		"brush assignment Undo restores exact materials and face data")
	paint.select_material_slot(1)
	_expect(paint.brush_preview_caption().contains("Assign to apply"),
		"same-label distinct material resources still show a brush preview warning")
	selection.set_ids(PackedInt64Array())
	_expect(paint.brush_preview_caption().contains("Click a face to paint"),
		"chosen brush without selected faces gives a truthful next step")
	selection.set_ids(PackedInt64Array([faces[0]]))
	var panel := SlabPanel.new()
	panel.setup(selection, actions, preload("res://addons/slab/slab_metrics.gd").at_scale(1.0))
	panel.bind_paint(paint)
	root.add_child(panel)
	var hint: Label = panel.find_child("PaintUvHint", true, false)
	_expect(hint.text.begins_with("Brush preview: Limestone") and hint.tooltip_text.begins_with(hint.text + "\n")
		and hint.tooltip_text.ends_with(SlabPaint.uv_canvas_hint()) and hint.mouse_filter == Control.MOUSE_FILTER_PASS,
		"canvas caption tooltip preserves its full context and UV gestures while events reach the canvas")
	paint.assign_active_to_selection()
	_expect(paint.brush_preview_caption().is_empty() and hint.text == SlabPaint.uv_canvas_hint(),
		"Assign returns the canvas to its gesture hint")
	undo.undo()
	_expect(paint.brush_preview_caption().contains("Assign to apply") and hint.text.begins_with("Brush preview:"),
		"Undo restores the unassigned brush preview caption")
	paint.tool = SlabPaint.Tool.PIXEL
	_expect(paint.brush_preview_caption().is_empty() and not hint.visible, "Pixel mode is unaffected by the UV brush caption")
	paint.tool = SlabPaint.Tool.MATERIAL_UV
	solid.call("set_face_material", PackedInt64Array([faces[1]]), 1)
	selection.set_ids(PackedInt64Array([faces[0], faces[1]]))
	var mixed_paint := SlabPaint.new()
	mixed_paint.bind(selection, actions, SlabTestUndo.new())
	mixed_paint.enter()
	_expect(mixed_paint.brush_preview_caption().begins_with("Selected: Mixed"),
		"mixed selection without a brush gives truthful recovery guidance")
	solid.call("set_face_material", PackedInt64Array([faces[0], faces[1]]), 2)
	mixed_paint.enter()
	_expect(mixed_paint.selected_material_summary() == "Default" and mixed_paint.brush_preview_caption().is_empty(),
		"uniform default faces keep the normal gesture hint instead of claiming a brush mismatch")
	panel.free()
	paint.exit()
	mixed_paint.exit()
	solid.free()


func _check_uv_drag_transaction() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([_top_face(solid)]))
	var actions := SlabActions.new(selection)
	var undo := SlabTestUndo.new()
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	paint.enter()
	var before: PackedByteArray = solid.get("data")
	var offset: Vector2 = actions.uv_offset
	paint.begin_uv_drag()
	paint.drag_uv(Vector2(0.2, 0.1))
	_expect(solid.get("data") != before, "UV drag previews on the mesh")
	paint.cancel_uv_drag()
	paint.end_uv_drag()
	_expect(solid.get("data") == before and actions.uv_offset == offset and undo.actions.is_empty(), "UV cancel restores mesh and controls without history")
	paint.begin_uv_drag()
	paint.drag_uv(Vector2(0.2, 0.1))
	selection.set_ids(PackedInt64Array([_side_face(solid)]))
	paint.end_uv_drag()
	_expect(solid.get("data") == before and undo.actions.is_empty(), "selection change cancels original UV transaction")
	paint.begin_uv_drag()
	paint.drag_uv(Vector2(0.3, 0.1))
	paint.tool = SlabPaint.Tool.PIXEL
	_expect(solid.get("data") == before and not paint.uv_drag_active, "tool change cancels UV transaction")
	paint.tool = SlabPaint.Tool.MATERIAL_UV
	paint.begin_uv_drag()
	paint.drag_uv(Vector2(0.2, 0.1))
	paint.end_uv_drag()
	var after: PackedByteArray = solid.get("data")
	_expect(undo.actions.size() == 1 and after != before, "UV release commits one action")
	undo.undo()
	_expect(solid.get("data") == before, "UV undo restores exact mesh")
	undo.redo()
	_expect(solid.get("data") == after, "UV redo restores exact placement")
	paint.exit()
	solid.free()


func _check_uv_matches_emit() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	_expect(solid.call("make_box", Vector3(2, 3, 2)) == 0, "uv box builds")
	var top: int = _top_face(solid)
	var corner: Vector3 = PackedVector3Array(solid.call("face_corners", top))[0]
	var mapped: Vector2 = SlabPaintUv.point_uv(solid, top, corner)
	var mesh: ArrayMesh = solid.call("build_mesh")
	_expect(_uv_matches_emit(mesh, corner, mapped), "GDScript UV matches emit.cpp, %s" % mapped)
	var attrs: Dictionary = solid.call("face_uv", top)
	_expect(attrs.has("slot"), "face_uv reports the material slot")
	solid.free()


func _check_texture_resolution_coherence() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var top: int = _top_face(solid)
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	var panel_undo := SlabTestUndo.new()
	var actions := SlabActions.new(selection, panel_undo)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, panel_undo)
	paint.enter()
	var flat := StandardMaterial3D.new()
	flat.albedo_color = Color(0.2, 0.3, 0.4)
	solid.set("materials", [flat])
	actions.material_slot = 0
	paint.rebind()
	actions.uv_texture_resolution = 1024
	paint.make_unique()
	_expect(paint.image().get_width() == 1024 and paint.image().get_height() == 1024,
		"Make Unique allocates a blank texture at Texture px")

	var existing_image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	existing_image.fill(Color(0.7, 0.1, 0.2))
	var existing := StandardMaterial3D.new()
	existing.albedo_texture = ImageTexture.create_from_image(existing_image)
	solid.set("materials", [existing])
	actions.material_slot = 0
	actions.uv_texture_resolution = 4096
	paint.rebind()
	paint.make_unique()
	_expect(paint.image().get_width() == 32 and paint.image().get_height() == 32,
		"Make Unique preserves existing artwork dimensions")
	_expect(actions.uv_texture_resolution == 32,
		"Texture px reflects the bound artwork width for coherent unwrap density")
	paint.exit()
	solid.free()


func _check_uv_modifier_dispatch() -> void:
	var plain := InputEventMouseMotion.new()
	_expect(SlabPaint.uv_mode_for(plain) == SlabPaint.UV_MOVE, "unmodified drag moves UV")
	var shift := InputEventMouseMotion.new()
	shift.shift_pressed = true
	_expect(SlabPaint.uv_mode_for(shift) == SlabPaint.UV_SCALE, "Shift drag scales UV")
	var meta := InputEventMouseMotion.new()
	meta.meta_pressed = true
	_expect(SlabPaint.uv_mode_for(meta) == SlabPaint.UV_ROTATE, "Meta/Cmd drag rotates UV")
	var ctrl := InputEventMouseMotion.new()
	ctrl.ctrl_pressed = true
	_expect(SlabPaint.uv_mode_for(ctrl) == SlabPaint.UV_ROTATE, "Ctrl drag rotates UV in the event path")
	var hint: String = SlabPaint.uv_canvas_hint()
	var shown: String = SlabPaint.uv_rotate_modifier_name()
	_expect(hint.contains("%s rotates" % shown), "the canvas hint names the platform rotate modifier, got %s" % hint)
	if OS.get_name() == "macOS":
		_expect(shown == "Cmd" and hint.contains("Cmd rotates"),
			"macOS advertises Cmd rotate, not Ctrl, got %s" % hint)
	else:
		_expect(shown == "Ctrl" and hint.contains("Ctrl rotates"),
			"non-macOS advertises Ctrl rotate, got %s" % hint)


func _check_uv_transform_and_wrap() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 3, 2))
	var top: int = _top_face(solid)
	solid.call("set_face_uv", PackedInt64Array([top]), Vector2(2, 2), Vector2(0.35, -0.2), PI * 0.5)
	var corner: Vector3 = PackedVector3Array(solid.call("face_corners", top))[1]
	var mapped: Vector2 = SlabPaintUv.point_uv(solid, top, corner)
	_expect(_uv_matches_emit(solid.call("build_mesh"), corner, mapped),
		"scaled/rotated/offset UV matches emit, %s" % mapped)
	var px: Vector2i = SlabPaintUv.uv_to_pixel(Vector2(-0.25, 1.75), 64, 64)
	_expect(px.x >= 0 and px.x < 64 and px.y >= 0 and px.y < 64, "UV wrap lands in the texture, got %s" % px)
	solid.rotation.y = PI * 0.25
	var still: Vector2 = SlabPaintUv.point_uv(solid, top, corner)
	_expect(still.distance_to(mapped) < 0.0001, "node rotation does not change local UV")
	solid.free()


func _check_numeric_uv_apply_and_selection_sync() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	_expect(solid.call("make_box", Vector3(4, 1, 4)) == 0, "numeric UV box builds")
	var top: int = _top_face(solid)
	var selection := SlabSelection.new()
	selection.mode = SlabSelection.Mode.FACE
	selection.set_objects([solid])
	selection.set_ids(PackedInt64Array([top]))
	var undo := SlabTestUndo.new()
	var actions := SlabActions.new(selection, undo)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	paint.enter()
	actions.uv_scale = Vector2(4.0, 4.0)
	actions.uv_offset = Vector2(0.25, -0.5)
	actions.uv_rotation_degrees = 30.0
	paint.apply_uv()
	var attrs: Dictionary = solid.call("face_uv", top)
	_expect((attrs.get("scale", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(4.0, 4.0)), "numeric UV applies four repeats")
	_expect((attrs.get("offset", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(0.25, -0.5)), "numeric UV applies both offsets")
	_expect(is_equal_approx(float(attrs.get("rotation", 0.0)), deg_to_rad(30.0)), "numeric UV applies degree rotation")
	_expect(undo.actions.size() == 1 and undo.actions[0]["name"] == "Slab Apply UV", "numeric UV apply is one undoable action")

	actions.uv_scale = Vector2.ONE
	actions.uv_offset = Vector2.ZERO
	actions.uv_rotation_degrees = 0.0
	selection.set_ids(PackedInt64Array())
	selection.set_ids(PackedInt64Array([top]))
	_expect(actions.uv_scale.is_equal_approx(Vector2(4.0, 4.0)), "face selection restores numeric repeat fields")
	_expect(actions.uv_offset.is_equal_approx(Vector2(0.25, -0.5)), "face selection restores numeric offset fields")
	_expect(is_equal_approx(actions.uv_rotation_degrees, 30.0), "face selection restores numeric rotation field")
	solid.free()


func _check_cylinder_and_concave() -> void:
	var cyl: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(cyl)
	_expect(cyl.call("make_cylinder", 1.0, 2.0, 12) == 0, "cylinder builds")
	var side: int = 0
	for id in PackedInt64Array(cyl.call("get_faces")):
		var n: Vector3 = cyl.call("face_normal", id)
		if absf(n.y) < 0.4:
			side = id
			break
	_expect(side != 0, "found a cylinder side face")
	var c0: Vector3 = PackedVector3Array(cyl.call("face_corners", side))[0]
	var mapped: Vector2 = SlabPaintUv.point_uv(cyl, side, c0)
	_expect(_uv_matches_emit(cyl.call("build_mesh"), c0, mapped),
		"cylinder segment UV matches emit, %s" % mapped)
	cyl.free()
	var prism: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(prism)
	var poly := PackedVector3Array([
		Vector3(0, 0, 4), Vector3(1, 0, 4), Vector3(1, 0, 1), Vector3(3, 0, 1),
		Vector3(3, 0, 4), Vector3(4, 0, 4), Vector3(4, 0, 0), Vector3(0, 0, 0),
	])
	var err: int = prism.call("make_prism", poly, 2.0)
	_expect(err == 0, "concave C prism builds, err %d" % err)
	if err == 0:
		var top: int = _top_face(prism)
		var uvs: PackedVector2Array = SlabPaintUv.face_uvs(prism, top)
		_expect(uvs.size() >= 8, "concave cap keeps all UV corners, got %d" % uvs.size())
		var mid: Vector3 = prism.call("face_centroid", top)
		var uv: Vector2 = SlabPaintUv.point_uv(prism, top, mid)
		_expect(uv.length() < 64.0, "concave centroid UV is finite, %s" % uv)
	prism.free()


func _check_raster_wrap_and_stroke() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	SlabPaintRaster.stamp(img, Vector2(0.5, 0.5), 3.0, Color.RED, 1.0)
	_expect(img.get_pixel(0, 0).r > 0.5, "stamp writes the center pixel")
	_expect(img.get_pixel(31, 0).r > 0.15, "stamp wraps across the U seam")
	var dabs: PackedVector2Array = SlabPaintRaster.interpolate(Vector2.ZERO, Vector2(10, 0), 2.0)
	_expect(dabs.size() >= 5, "a stroke interpolates dabs, got %d" % dabs.size())
	SlabPaintRaster.stroke(img, Vector2(4, 16), Vector2(20, 16), 2.0, Color.BLUE, 1.0)
	_expect(img.get_pixel(12, 16).b > 0.3, "interpolated stroke paints the mid dab")
	var beige := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	beige.fill(Color(0.725, 0.643, 0.533, 1.0))
	var compressed: bool = beige.compress(Image.COMPRESS_S3TC) == OK and beige.is_compressed()
	if not compressed:
		compressed = beige.compress(Image.COMPRESS_ETC2) == OK and beige.is_compressed()
	if compressed:
		var copy: Image = SlabPaintRaster.clone_rgba(beige)
		_expect(copy != null and not copy.is_compressed(), "clone_rgba decompresses block-compressed albedo")
		_expect(copy.get_pixel(4, 4).r > 0.5, "decompressed beige is not a zero buffer, %s" % copy.get_pixel(4, 4))
	var dark := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	dark.fill(Color(0.0, 0.0, 0.0, 1.0))
	dark.set_pixel(1, 1, Color(0.0, 0.0, 0.0, 0.4))
	var dark_copy: Image = SlabPaintRaster.clone_rgba(dark)
	_expect(dark_copy.get_pixel(16, 16).r < 0.08, "clone_rgba keeps a dark fill, %s" % dark_copy.get_pixel(16, 16))
	_expect(dark_copy.get_pixel(1, 1).a < 0.7, "clone_rgba keeps transparent dark texels")
	var dark_block: Image = dark.duplicate()
	if dark_block.compress(Image.COMPRESS_S3TC) == OK or dark_block.compress(Image.COMPRESS_ETC2) == OK:
		var from_block: Image = SlabPaintRaster.clone_rgba(dark_block)
		_expect(from_block.get_pixel(16, 16).r < 0.15, "decompressed dark fill stays dark, %s" % from_block.get_pixel(16, 16))


func _check_wrap_outline_tiles() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var wrapped := PackedVector2Array()
	for uv in square:
		wrapped.append(Vector2(SlabPaintUv.wrap01(uv.x), SlabPaintUv.wrap01(uv.y)))
	_expect(wrapped[1].distance_to(wrapped[0]) < 0.001, "wrapping each vertex collapses UV 0 and 1")
	var loops: Array = SlabPaintUv.tiled_loops(square)
	_expect(loops.size() == 1, "a unit island stays one tile, got %d" % loops.size())
	var saw_zero := false
	var saw_one := false
	for uv in loops[0]:
		if uv.x <= 0.001:
			saw_zero = true
		if uv.x >= 0.999:
			saw_one = true
	_expect(saw_zero and saw_one, "tiled outline keeps both U=0 and U=1")
	var seam := PackedVector2Array([
		Vector2(0.8, 0.2), Vector2(1.2, 0.2), Vector2(1.2, 0.6), Vector2(0.8, 0.6),
	])
	_expect(SlabPaintUv.crosses_wrap(seam), "a wrapping island is flagged")
	var tiled: Array = SlabPaintUv.tiled_loops(seam)
	_expect(tiled.size() >= 2, "a wrapping island repeats across tiles, got %d" % tiled.size())
	var saw_left := false
	var saw_right := false
	for loop in tiled:
		for uv in loop:
			if uv.x <= 0.001:
				saw_left = true
			if uv.x >= 0.999:
				saw_right = true
	_expect(saw_left and saw_right, "clipped tiles draw the seam at both 0 and 1")


func _check_unique_paint_undo_save() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.name = "PaintBox"
	solid.call("make_box", Vector3(2, 3, 2))
	var top: int = _top_face(solid)
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	var actions := SlabActions.new(selection)
	var undo := SlabTestUndo.new()
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	paint.enter()
	var shared := StandardMaterial3D.new()
	shared.albedo_color = Color(0.2, 0.4, 0.8)
	solid.set("materials", [shared])
	actions.material_slot = 0
	paint.rebind()
	var slot: int = paint.make_unique()
	_expect(slot == 1, "Make Unique appends a slot, got %d" % slot)
	_expect(paint.material() != null and paint.material().resource_local_to_scene, "the unique material is local")
	_expect(int(solid.call("face_uv", top).get("slot", -1)) == slot, "selected face uses the unique slot")
	var before_faces: int = solid.call("face_count")
	paint.tool = SlabPaint.Tool.PIXEL
	_expect(paint.begin_stroke(), "pixel stroke starts on a unique material")
	paint.dab_uv(Vector2(0.5, 0.5))
	paint.dab_uv(Vector2(0.7, 0.5))
	paint.end_stroke()
	_expect(solid.call("face_count") == before_faces, "painting never changes geometry")
	var painted: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_expect(painted.r > 0.4, "the stroke wrote red into the albedo, %s" % painted)
	var painted_mip_color := _mip_center(paint.image(), 1)
	_expect(painted_mip_color.r > 0.35 and painted_mip_color.r > painted_mip_color.b * 1.4,
		"live paint regenerates the minified mip level, got %s" % painted_mip_color)
	_expect(undo.actions.size() >= 2, "unique and stroke recorded undo")
	var stroke_action: Dictionary = undo.actions[undo.actions.size() - 1]
	_expect(String(stroke_action.get("name", "")) == "Slab Paint Stroke",
		"the last undo action is the stroke, got %s" % stroke_action.get("name", ""))
	var do_ops: Array = stroke_action.get("do_ops", [])
	_expect(do_ops.size() > 0 and do_ops[0].has("property") and not do_ops[0].has("callable"),
		"stroke undo uses add_do_property, not Callable.bind")
	_expect(str(do_ops[0].get("property", "")) == "albedo_texture",
		"stroke records albedo_texture, got %s" % do_ops[0].get("property", ""))
	undo.undo()
	var restored: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_expect(restored.r < painted.r - 0.1, "undo restores the pre-stroke albedo, %s" % restored)
	_expect(_mip_center(paint.image(), 1).r < painted_mip_color.r - 0.1,
		"undo restores the prior minified mip level")
	undo.redo()
	var redone: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_expect(redone.r > 0.4, "redo reapplies the stroke")
	_expect(_mip_center(paint.image(), 1).r > 0.35,
		"redo reapplies the painted minified mip level")
	var path: String = "user://slab_paint_test/paintbox.png"
	_expect(paint.save_png(path) == OK, "save writes a PNG")
	_expect(FileAccess.file_exists(path), "the PNG exists on disk")
	var loaded := Image.new()
	_expect(loaded.load(path) == OK, "the PNG reloads")
	var disk: Color = loaded.get_pixel(loaded.get_width() / 2, loaded.get_height() / 2)
	_expect(disk.r > 0.4, "reopened PNG keeps the stripe, %s" % disk)
	_expect(paint.save_status().to_lower().find("scene") >= 0, "save tells the user the scene still needs saving")
	_expect(not paint.dirty, "save clears paint dirty")
	undo.undo()
	_expect(paint.dirty, "undo after save marks that material unsaved")
	undo.redo()
	_expect(not paint.dirty, "redo matching saved pixels is clean even with generated mipmaps")
	paint.begin_stroke()
	paint.dab_uv(Vector2(0.1, 0.1))
	paint.cancel_stroke()
	_expect(not paint.stroke_active, "Escape cancel ends the stroke")
	paint.exit()
	solid.free()


func _check_viewport_paint_does_not_extrude() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var host: RefCounted = SlabTestHost.over(world)
	var session := SlabViewport.new(host)
	var selection: RefCounted = session.state()
	var actions := SlabActions.new(selection)
	session.bind_actions(actions)
	var paint := SlabPaint.new()
	var undo := SlabTestUndo.new()
	paint.bind(selection, actions, undo)
	session.bind_paint(paint)
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	world.add_child(solid)
	solid.call("make_box", Vector3(2, 3, 2))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(6, 8, 10), Vector3(1, 1.5, 1), Vector3.UP)
	cam.current = true
	var top: int = _top_face(solid)
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	paint.enter()
	paint.tool = SlabPaint.Tool.PIXEL
	paint.make_unique()
	var screen: Vector2 = cam.unproject_position(solid.to_global(solid.call("face_centroid", top)))
	var faces: int = solid.call("face_count")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen
	var verdict: int = session.handle(cam, down)
	_expect(verdict == SlabViewport.Verdict.STOP, "a paint click is claimed")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = screen
	session.handle(cam, up)
	_expect(solid.call("face_count") == faces, "a 3D paint click does not extrude")
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	_expect(session.handle(cam, key) == SlabViewport.Verdict.STOP, "E is swallowed while painting")
	_expect(solid.call("face_count") == faces, "E does not extrude in Surface Paint")
	key.keycode = KEY_F
	_expect(session.handle(cam, key) == SlabViewport.Verdict.PASS and paint.active, "F remains available to frame the painted object")
	for navigation_key in [KEY_KP_8, KEY_KP_2, KEY_KP_4, KEY_KP_6, KEY_KP_1, KEY_KP_3, KEY_KP_5, KEY_KP_7]:
		key.keycode = navigation_key
		_expect(session.handle(cam, key) == SlabViewport.Verdict.PASS and paint.active,
			"native keypad view key %s passes through Surface Paint" % navigation_key)
	key.keycode = KEY_Z
	key.meta_pressed = true
	_expect(session.handle(cam, key) == SlabViewport.Verdict.PASS, "Cmd-Z reaches editor Undo while painting")
	key.meta_pressed = false
	key.ctrl_pressed = true
	key.shift_pressed = true
	_expect(session.handle(cam, key) == SlabViewport.Verdict.PASS, "Ctrl-Shift-Z reaches editor Redo while painting")
	key.ctrl_pressed = false
	key.shift_pressed = false
	var hit: Dictionary = SlabPick.pick_face_hit(solid, cam, screen)
	_expect(not hit.is_empty() and int(hit["id"]) == top, "3D hit lands on the selected face")
	if not hit.is_empty():
		_expect(SlabPaintUv.faces_camera(solid, top, cam, hit["world"]), "the top face faces the camera")
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	session.handle(cam, motion)
	var preview: MeshInstance3D = paint.brush_preview()
	_expect(preview != null and preview.visible, "Pixel mode shows a 3D brush hover")
	key.keycode = KEY_3
	_expect(session.handle(cam, key) == SlabViewport.Verdict.STOP, "mode shortcut is claimed while painting")
	_expect(not paint.active and selection.mode == SlabSelection.Mode.EDGE, "mode shortcut leaves painting for modelling")
	paint.enter()
	selection.request_mode(SlabSelection.Mode.FACE)
	_expect(not paint.active, "explicit same-mode choice leaves painting")
	paint.exit()
	_expect(paint.brush_preview() == null, "closing Paint frees the 3D brush")
	world.free()


func _check_unique_copies_full_material_and_needs_a_face() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 3, 2))
	var top: int = _top_face(solid)
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	var actions := SlabActions.new(selection)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, SlabTestUndo.new())
	paint.enter()
	var steel := StandardMaterial3D.new()
	steel.resource_name = "Teal Steel"
	steel.albedo_color = Color(0.15, 0.45, 0.48)
	steel.metallic = 0.4
	steel.roughness = 0.35
	solid.set("materials", [steel])
	actions.material_slot = 0
	paint.rebind()
	_expect(paint.make_unique() < 0, "Make Unique without a face does not invent a material")
	selection.set_ids(PackedInt64Array([top]))
	var slot: int = paint.make_unique()
	_expect(slot == 1, "Make Unique with a face appends a slot")
	var copy: StandardMaterial3D = paint.material()
	_expect(copy != null and copy != steel, "the unique material is a new resource")
	_expect(is_equal_approx(copy.metallic, 0.4), "unique keeps metallic, got %s" % copy.metallic)
	_expect(is_equal_approx(copy.roughness, 0.35), "unique keeps roughness")
	_expect(paint.is_owned(copy), "unique is marked owned, not merely local_to_scene")
	_expect(not paint.is_owned(steel), "the shared original stays locked")
	_expect(not paint.begin_stroke() or paint.is_owned(paint.material()), "pixel paint stays on an owned copy")
	paint.exit()
	solid.free()


func _check_undo_after_switching_slots() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 3, 2))
	var top: int = _top_face(solid)
	var side: int = _side_face(solid)
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	var actions := SlabActions.new(selection)
	var undo := SlabTestUndo.new()
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	paint.enter()
	solid.set("materials", [StandardMaterial3D.new()])
	(solid.get("materials")[0] as StandardMaterial3D).albedo_color = Color(0.2, 0.4, 0.8)
	actions.material_slot = 0
	paint.rebind()
	var slot_a: int = paint.make_unique()
	selection.set_ids(PackedInt64Array([side]))
	actions.material_slot = 0
	paint.rebind()
	var slot_b: int = paint.make_unique()
	_expect(slot_a == 1 and slot_b == 2, "two unique slots, got %d and %d" % [slot_a, slot_b])
	paint.tool = SlabPaint.Tool.PIXEL
	_expect(paint.begin_stroke(), "stroke starts on unique B")
	paint.dab_uv(Vector2(0.5, 0.5))
	paint.end_stroke()
	var painted_b: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_expect(painted_b.r > 0.4, "B received the red dab")
	var mats: Array = solid.get("materials")
	var image_a: Image = (mats[slot_a] as StandardMaterial3D).albedo_texture.get_image()
	var before_a: Color = image_a.get_pixel(image_a.get_width() / 2, image_a.get_height() / 2)
	actions.material_slot = slot_a
	paint.rebind()
	_expect(paint.slot() == slot_a, "switched the editor to unique A")
	undo.undo()
	var still_a: Image = (mats[slot_a] as StandardMaterial3D).albedo_texture.get_image()
	var after_a: Color = still_a.get_pixel(still_a.get_width() / 2, still_a.get_height() / 2)
	_expect(after_a.r == before_a.r and after_a.g == before_a.g,
		"undoing B's stroke does not rewrite A")
	actions.material_slot = slot_b
	paint.rebind()
	var restored_b: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_expect(restored_b.r < painted_b.r - 0.1, "undo restores B after the editor left that slot")
	undo.redo()
	var redone_b: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_expect(redone_b.r > 0.4, "redo paints B again, not A")
	paint.exit()
	solid.free()


func _check_dark_texture_preserved() -> void:
	var dark := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	dark.fill(Color(0.0, 0.0, 0.0, 1.0))
	dark.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 0.25))
	var tex := ImageTexture.create_from_image(dark)
	var cpu: Image = SlabPaint.new().cpu_image_from_texture(tex)
	_expect(cpu != null and cpu.get_pixel(32, 32).r < 0.02,
		"dark ImageTexture is not treated as a failed readback, %s" % (cpu.get_pixel(32, 32) if cpu else Color()))
	_expect(cpu != null and cpu.get_pixel(0, 0).a < 0.4, "transparent black is kept")
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 3, 2))
	var top: int = _top_face(solid)
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	var actions := SlabActions.new(selection)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, SlabTestUndo.new())
	paint.enter()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	solid.set("materials", [mat])
	actions.material_slot = 0
	paint.rebind()
	paint.make_unique()
	var mid: Color = paint.image().get_pixel(32, 32)
	_expect(mid.r < 0.05 and mid.g < 0.05 and mid.b < 0.05,
		"Make Unique preserves a black albedo, %s" % mid)
	paint.exit()
	solid.free()


func _check_imported_svg_unique_stroke_roundtrip() -> void:
	var src_mat: Resource = load("res://demo/relay_yard/materials/limestone.tres")
	_expect(src_mat is StandardMaterial3D, "limestone.tres loads")
	var imported: Texture2D = (src_mat as StandardMaterial3D).albedo_texture if src_mat is StandardMaterial3D else null
	_expect(imported != null, "limestone.tres has an albedo texture")
	_expect(imported != null and not (imported is ImageTexture),
		"imported SVG is not an ImageTexture, got %s" % (imported.get_class() if imported else "null"))
	var readback: Image = SlabPaint.new().cpu_image_from_texture(imported)
	_expect(readback != null and not readback.is_empty(), "imported SVG readback produced CPU pixels")
	var fill: Color = readback.get_pixel(mini(8, readback.get_width() - 1), mini(8, readback.get_height() - 1)) if readback != null else Color()
	_expect(fill.r > 0.5 and fill.g > 0.4,
		"readback keeps limestone fill rather than a zeroed get_image(), %s" % fill)
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.name = "ImportedPaint"
	solid.call("make_box", Vector3(2, 3, 2))
	var top: int = _top_face(solid)
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	var actions := SlabActions.new(selection)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, SlabTestUndo.new())
	paint.enter()
	var shared: StandardMaterial3D = (src_mat as StandardMaterial3D).duplicate()
	solid.set("materials", [shared])
	actions.material_slot = 0
	paint.rebind()
	var slot: int = paint.make_unique()
	_expect(slot >= 1, "Make Unique appends a slot from the imported material")
	var unique_fill: Color = paint.image().get_pixel(8, 8)
	_expect(unique_fill.r > 0.5, "Make Unique copies imported texels, %s" % unique_fill)
	paint.tool = SlabPaint.Tool.PIXEL
	_expect(paint.begin_stroke(), "pixel stroke starts on the imported unique copy")
	paint.dab_uv(Vector2(0.5, 0.5))
	paint.end_stroke()
	var painted: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_expect(painted.r > 0.6, "the stroke wrote red into the imported albedo, %s" % painted)
	var path: String = "user://slab_paint_test/imported_limestone.png"
	_expect(paint.save_png(path) == OK, "imported paint saves a PNG")
	var packed := PackedScene.new()
	_expect(packed.pack(solid) == OK, "the imported painted solid packs")
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	var selection2 := SlabSelection.new()
	selection2.set_objects([inst])
	selection2.mode = SlabSelection.Mode.FACE
	selection2.set_ids(PackedInt64Array([top]))
	var actions2 := SlabActions.new(selection2)
	var paint2 := SlabPaint.new()
	paint2.bind(selection2, actions2, SlabTestUndo.new())
	paint2.enter()
	var reopened_slot: int = int(inst.call("face_uv", top).get("slot", 0))
	actions2.material_slot = reopened_slot
	paint2.rebind()
	var mid: Color = paint2.image().get_pixel(paint2.image().get_width() / 2, paint2.image().get_height() / 2)
	_expect(mid.r > 0.6, "reopened imported paint keeps the red stroke, %s" % mid)
	paint2.exit()
	paint.exit()
	inst.free()
	solid.free()


func _check_engine_undo_switch_save_escape() -> void:
	_expect(ClassDB.class_exists("UndoRedo"), "engine UndoRedo exists")
	var undo := UndoRedo.new()
	var solid_a: Node3D = ClassDB.instantiate("SlabSolid")
	var solid_b: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid_a)
	root.add_child(solid_b)
	solid_a.name = "PaintA"
	solid_b.name = "PaintB"
	solid_a.call("make_box", Vector3(2, 3, 2))
	solid_b.call("make_box", Vector3(2, 3, 2))
	var top_a: int = _top_face(solid_a)
	var selection := SlabSelection.new()
	selection.set_objects([solid_a])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top_a]))
	var actions := SlabActions.new(selection)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	paint.enter()
	var shared := StandardMaterial3D.new()
	shared.albedo_color = Color(0.2, 0.4, 0.8)
	solid_a.set("materials", [shared])
	actions.material_slot = 0
	paint.rebind()
	paint.make_unique()
	paint.tool = SlabPaint.Tool.PIXEL
	_expect(paint.begin_stroke(), "engine undo: stroke starts")
	paint.dab_uv(Vector2(0.5, 0.5))
	paint.end_stroke()
	var painted: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_expect(painted.r > 0.4, "engine undo: stroke wrote red, %s" % painted)
	var slot_a: int = paint.slot()
	selection.set_objects([solid_b])
	selection.set_ids(PackedInt64Array([_top_face(solid_b)]))
	paint.rebind()
	undo.undo()
	selection.set_objects([solid_a])
	selection.set_ids(PackedInt64Array([top_a]))
	actions.material_slot = slot_a
	paint.rebind()
	var restored: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_expect(restored.r < painted.r - 0.1, "engine undo restores A after switching solids, %s" % restored)
	undo.redo()
	var redone: Color = paint.image().get_pixel(paint.image().get_width() / 2, paint.image().get_height() / 2)
	_expect(redone.r > 0.4, "engine redo paints A again, %s" % redone)
	var path: String = "user://slab_paint_test/engine_undo.png"
	_expect(paint.save_png(path) == OK, "engine undo: save writes a PNG")
	_expect(not paint.dirty, "engine undo: save clears dirty")
	undo.undo()
	_expect(paint.dirty, "engine undo after save marks unsaved")
	undo.redo()
	paint.begin_stroke()
	paint.dab_uv(Vector2(0.15, 0.15))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	var cam := Camera3D.new()
	root.add_child(cam)
	_expect(paint.handle_3d(cam, esc, root) == SlabPaint.VERDICT_STOP, "Escape is claimed while painting")
	_expect(not paint.stroke_active, "Escape cancel ends the engine-undo stroke")
	cam.free()
	paint.exit()
	solid_a.free()
	solid_b.free()
	undo.free()


func _check_canvas_letterbox_and_press() -> void:
	root.size = Vector2i(1280, 800)
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 3, 2))
	var top: int = _top_face(solid)
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	var panel_undo := SlabTestUndo.new()
	var actions := SlabActions.new(selection, panel_undo)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, panel_undo)
	paint.enter()
	var shared := StandardMaterial3D.new()
	shared.resource_name = "Limestone"
	shared.albedo_color = Color(0.2, 0.4, 0.8)
	var huge := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	huge.fill(Color(0.15, 0.55, 0.35))
	shared.albedo_texture = ImageTexture.create_from_image(huge)
	solid.set("materials", [shared])
	actions.material_slot = 0
	paint.rebind()
	var thumb: Texture2D = paint.thumbnail(shared, 28)
	_expect(thumb != null and thumb.get_width() == 28 and thumb.get_height() == 28,
		"imported-size albedo thumbs are 28px, got %sx%s" % [
			thumb.get_width() if thumb else -1, thumb.get_height() if thumb else -1
		])
	paint.make_unique()
	paint.tool = SlabPaint.Tool.PIXEL
	var panel: Control = SlabPanel.new()
	_expect(is_instance_valid(panel), "the paint dock instantiates")
	panel.setup(selection, actions, preload("res://addons/slab/slab_metrics.gd").at_scale(1.0))
	panel.bind_paint(paint)
	root.add_child(panel)
	panel.theme = ThemeDB.get_default_theme()
	panel.size = Vector2(1226, SlabPaint.PAINT_HEIGHT)
	panel.resized.emit()
	await process_frame
	await process_frame
	var canvas: Control = panel.find_child("PaintCanvas", true, false)
	_expect(canvas != null, "the dock wires a PaintCanvas")
	var fitted: Rect2 = canvas.image_rect()
	_expect(fitted.size.x > 1.0 and is_equal_approx(fitted.size.x, fitted.size.y),
		"letterbox keeps the albedo square, got %s in %s" % [fitted.size, canvas.size])
	_expect(fitted.size.y <= canvas.size.y + 0.5, "letterbox fits the shorter canvas side")
	_expect(canvas.size.x > fitted.size.x + 8.0, "a wide dock canvas keeps letterbox bars")
	var scale: float = canvas.pixel_scale()
	_expect(is_equal_approx(scale * 8.0, paint.brush_radius * scale), "brush ring uses the letterboxed pixel scale")
	var target: Control = panel.find_child("PaintTarget", true, false)
	var actions_row: Control = panel.find_child("PaintActions", true, false)
	var palette: Control = panel.find_child("PaintPalette", true, false)
	_expect(target != null and actions_row != null and palette != null, "paint rows exist")
	_expect(target.custom_minimum_size.y <= SlabPanel.PAINT_ROW_HEIGHT + 0.5,
		"the target row is an explicit %s px band" % SlabPanel.PAINT_ROW_HEIGHT)
	_expect(actions_row.get_combined_minimum_size().y > SlabPanel.PAINT_PICKER_HEIGHT,
		"the inspector naturally reserves its buttons and native picker")
	_expect(not _rects_overlap(target.get_global_rect(), actions_row.get_global_rect()),
		"target and actions do not overlap, %s vs %s" % [target.get_global_rect(), actions_row.get_global_rect()])
	_expect(not palette.visible and not panel.find_child("PaintAssign", true, false).visible
		and not panel.find_child("PaintSample", true, false).visible
		and not panel.find_child("PaintMaterialPickerWrap", true, false).visible,
		"Pixel removes material-assignment controls and palette")
	var save_button: Button = panel.find_child("PaintSave", true, false)
	_expect(save_button.visible and not save_button.disabled,
		"Pixel exposes Save Paint for its editable texture")
	_expect(not _rects_overlap(actions_row.get_global_rect(), canvas.get_global_rect()),
		"compact Pixel actions do not overlap the larger canvas")
	var pixel_canvas_height := canvas.size.y
	var pixel_canvas_width := canvas.size.x
	var pixel_help: Label = panel.find_child("PaintHelp", true, false)
	_expect(pixel_help.visible and pixel_help.text.contains("Save Paint"),
		"editable Pixel texture has visible painting and saving guidance")
	var mapping: Control = panel.find_child("PaintMapping", true, false)
	var mapping_resolution: SpinBox = panel.find_child("paint_uv_texture_resolution", true, false).get_child(1) as SpinBox
	_expect(mapping != null and mapping.is_visible_in_tree()
		and panel.find_child("PaintMappingState", true, false).visible == false
		and panel.find_child("paint_uv_pixels_per_meter", true, false).visible == false
		and panel.find_child("PaintUnwrap", true, false).visible == false,
		"Pixel reduces Mapping to image-size controls")
	_expect(not mapping_resolution.editable
		and (mapping_resolution.get_parent().get_child(0) as Label).text == "Texture px",
		"existing Pixel artwork reports its dimensions without offering a resize")
	var face_label: Label = panel.find_child("PaintTarget", true, false).get_child(2) as Label
	_expect(face_label != null and face_label.text.begins_with("%s · 1 face · " % solid.name)
		and face_label.text.ends_with(paint.selected_material_summary()),
		"the target row describes the selected face count, got %s" % (face_label.text if face_label else "missing"))
	var header_context: Label = panel.find_child("SelectionContext", true, false)
	_expect(header_context != null and header_context.text == face_label.text,
		"the persistent header carries the selected face and material context")
	var original_name := solid.name
	solid.name = "PowerHouseExteriorCourtyardNorthRetainingWall"
	panel.call("_refresh_paint_chrome")
	await process_frame
	_expect(face_label.text.begins_with(solid.name + " · 1 face · ")
		and face_label.tooltip_text == face_label.text,
		"a clipped long target keeps its complete name and count in the tooltip")
	_expect(header_context.tooltip_text == face_label.text,
		"the long authoritative target stays complete in the header tooltip")
	solid.name = original_name
	panel.call("_refresh_paint_chrome")
	selection.set_ids(PackedInt64Array())
	_expect(SlabPanel.paint_target_text(selection) == "%s · Select a face to paint." % solid.name,
		"zero-face context names the current solid")
	var other: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(other)
	other.call("make_box", Vector3.ONE)
	selection.set_objects([solid, other])
	_expect(SlabPanel.paint_target_text(selection) == "2 solids selected · Select one solid to paint.",
		"multi-target context explains how to recover")
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	panel.call("_refresh_paint_chrome")
	other.free()
	var picker_wrap: Control = panel.find_child("PaintMaterialPickerWrap", true, false)
	_expect(picker_wrap is MarginContainer, "the resource picker sits in a layout container")
	_expect(picker_wrap != null and picker_wrap.custom_minimum_size.y >= SlabPanel.PAINT_PICKER_HEIGHT,
		"the picker slot reserves %s px, got %s" % [
			SlabPanel.PAINT_PICKER_HEIGHT, picker_wrap.custom_minimum_size.y if picker_wrap else -1
		])
	var preview: Node = panel.find_child("Preview", true, false)
	_expect(preview == null or (preview is CanvasItem and not (preview as CanvasItem).visible),
		"the resource preview sphere is hidden")
	var unique: Button = null
	for button in _buttons_under(panel):
		if String(button.get_meta("slab_label", "")) == "Make Unique":
			unique = button
			break
	_expect(unique != null and unique.get_global_rect().size.y >= 20.0,
		"Make Unique is fully visible, size=%s" % (unique.get_global_rect().size if unique else Vector2.ZERO))
	var edge: Color = paint.image().get_pixel(0, 0)
	var image_center: Vector2 = canvas.global_position + fitted.get_center()
	_hover_at(panel, image_center)
	await process_frame
	var hovered: Control = panel.get_viewport().gui_get_hovered_control()
	_expect(hovered == canvas or (hovered != null and canvas.is_ancestor_of(hovered)),
		"gui_get_hovered_control at the albedo is the canvas, got %s" % hovered)
	_click_at(panel, image_center)
	var px: Vector2 = canvas.canvas_to_pixel(fitted.get_center())
	var dab: Color = paint.image().get_pixel(clampi(int(px.x), 0, paint.image().get_width() - 1), clampi(int(px.y), 0, paint.image().get_height() - 1))
	_expect(dab.r > 0.3, "viewport push_input on the dock canvas paints, %s" % dab)
	_expect(paint.save_status() != "", "a finished stroke reports paint status")
	var bar: Vector2 = canvas.global_position + Vector2(3.0, canvas.size.y * 0.5)
	_expect(not canvas.hits_image(bar - canvas.global_position), "the letterbox bar is outside the albedo")
	_click_at(panel, bar)
	var after_bar: Color = paint.image().get_pixel(0, 0)
	_expect(after_bar.is_equal_approx(edge), "letterbox clicks do not paint texture edges, %s vs %s" % [after_bar, edge])
	_expect(palette is ScrollContainer, "the palette scrolls instead of wrapping")
	_expect(palette.custom_minimum_size.y <= SlabPanel.PAINT_PALETTE_HEIGHT + 0.5,
		"the named palette is ~40px, got %s" % palette.custom_minimum_size.y)
	_expect(panel.custom_minimum_size.y >= SlabPaint.PAINT_HEIGHT
		and is_equal_approx(panel.custom_minimum_size.y, panel.get_combined_minimum_size().y),
		"the paint dock custom min matches its bounded workspace, got %s" % panel.custom_minimum_size.y)
	_expect(canvas.custom_minimum_size.y >= SlabPanel.PAINT_CANVAS_MIN_HEIGHT
		and canvas.size.y >= SlabPanel.PAINT_CANVAS_MIN_HEIGHT,
		"paint mode reserves a usable canvas, got min=%s size=%s" % [canvas.custom_minimum_size.y, canvas.size.y])
	var dock_height_before_slots := panel.get_combined_minimum_size().y
	var mats: Array = solid.get("materials")
	var extra: Array = mats.duplicate()
	for i in 8:
		var m := StandardMaterial3D.new()
		m.resource_name = "Fill %d" % i
		var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 0.3, 0.4))
		m.albedo_texture = ImageTexture.create_from_image(img)
		extra.append(m)
	solid.set("materials", extra)
	paint.rebind()
	panel.refresh()
	await process_frame
	_expect(panel.get_combined_minimum_size().y <= dock_height_before_slots + 0.5,
		"eight imported-size slots do not grow the dock, got %s" % panel.get_combined_minimum_size().y)
	var chip: Button = panel.find_child("paint_material_0", true, false)
	_expect(chip != null and chip.icon != null and chip.icon.get_width() <= 32,
		"palette icons are downscaled thumbs, got %s" % (chip.icon.get_width() if chip != null and chip.icon != null else -1))
	_expect(chip != null and chip.text.contains("Limestone"),
		"palette chips show material names, got %s" % (chip.text if chip else "missing"))
	_expect(chip != null and chip.custom_minimum_size.x >= 100.0,
		"Limestone is wider than three glyphs, min=%s" % (chip.custom_minimum_size.x if chip else -1))
	_expect(chip != null and chip.get_combined_minimum_size().y <= SlabPanel.PAINT_PALETTE_HEIGHT + 1.0,
		"a named chip stays inside the 40px palette, got %s" % (chip.get_combined_minimum_size().y if chip else -1))
	_expect(is_equal_approx(chip.self_modulate.r, 1.0) and is_equal_approx(chip.self_modulate.g, 1.0),
		"selected chips are not color-modulated over the thumb")
	_expect(target != null and target.get_child(0) != null and String(target.get_child(0).get_meta("slab_label", "")) == "Material / UV",
		"Material/UV sits first in the target row")
	var hint: Label = panel.find_child("PaintUvHint", true, false)
	_expect(hint != null, "UV modifiers are labeled next to the canvas")
	_expect(hint.get_parent() == canvas, "the UV hint overlays the canvas instead of adding a dock row")
	_expect(hint.text == SlabPaint.uv_canvas_hint(),
		"the live hint matches the platform rotate modifier, got %s" % hint.text)
	paint.tool = SlabPaint.Tool.MATERIAL_UV
	panel.refresh()
	await process_frame
	_expect(mapping_resolution.editable, "Material/UV can set the reference atlas resolution")
	_expect(panel.find_child("PaintMappingState", true, false).visible
		and panel.find_child("paint_uv_pixels_per_meter", true, false).visible
		and panel.find_child("PaintUnwrap", true, false).visible,
		"Material/UV exposes mapping state, density, and Unwrap")
	_expect(panel.find_child("PaintPlacementTitle", true, false).text == "Placement",
		"Mapping and Placement are distinct inspector sections")
	var repeat_u: SpinBox = panel.find_child("paint_uv_repeat_u", true, false).get_child(1) as SpinBox
	var repeat_v: SpinBox = panel.find_child("paint_uv_repeat_v", true, false).get_child(1) as SpinBox
	repeat_u.get_line_edit().text = "2"
	repeat_v.get_line_edit().text = "3"
	var repeat_up: Button
	var repeat_down: Button
	for button in _buttons_under(panel.find_child("PaintUvControls", true, false)):
		if String(button.get_meta("slab_label", "")) == "Repeat ×2": repeat_up = button
		if String(button.get_meta("slab_label", "")) == "Repeat ÷2": repeat_down = button
	var repeat_undo_before: int = panel_undo.actions.size()
	repeat_up.pressed.emit()
	_expect(actions.uv_scale == Vector2(4.0, 6.0) and repeat_u.value == 4.0 and repeat_v.value == 6.0
		and panel_undo.actions.size() == repeat_undo_before + 1,
		"Repeat ×2 flushes typed U/V fields and applies one undoable edit")
	repeat_down.pressed.emit()
	_expect(actions.uv_scale == Vector2(2.0, 3.0) and repeat_u.value == 2.0 and repeat_v.value == 3.0
		and panel_undo.actions.size() == repeat_undo_before + 2,
		"Repeat ÷2 halves both fields and applies one undoable edit, got %s fields %s/%s undo %s" % [actions.uv_scale, repeat_u.value, repeat_v.value, panel_undo.actions.size() - repeat_undo_before])
	mapping_resolution.get_line_edit().text = "777"
	panel.call("_commit_paint_mapping_inputs")
	_expect(actions.uv_texture_resolution == 777,
		"Mapping actions commit pending Texture px text before running")
	actions.uv_texture_resolution = 32
	_expect(palette.visible and panel.find_child("PaintAssign", true, false).visible
		and panel.find_child("PaintSample", true, false).visible
		and panel.find_child("PaintMaterialPickerWrap", true, false).visible,
		"Material/UV restores material placement controls")
	_expect(not save_button.visible and not pixel_help.visible,
		"Material/UV hides pixel-only save controls and guidance")
	_expect(absf(pixel_canvas_height - canvas.size.y) <= 1.0 and pixel_canvas_width > canvas.size.x + 20.0,
		"Pixel keeps the same canvas height and a wider canvas with its narrower brush inspector")
	_expect(not _rects_overlap(palette.get_global_rect(), canvas.get_global_rect()),
		"Material/UV palette stays beside the canvas without overlap")
	var fit_uv: Button = panel.find_child("PaintFitUv", true, false)
	_expect(fit_uv != null and fit_uv.visible, "Material/UV exposes an explicit Fit UV control")
	_expect(fit_uv != null and fit_uv.position.x >= 8.0 and fit_uv.position.x + fit_uv.size.x <= canvas.size.x - 7.0,
		"Fit UV stays inside the compact canvas with right padding")
	_expect(fit_uv != null and fit_uv.get_combined_minimum_size().x <= fit_uv.size.x + 0.5,
		"Fit UV has enough width for its complete label")
	var hint_style := hint.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(hint_style != null and hint_style.bg_color.a >= 0.75,
		"UV instructions have a readable translucent background")
	solid.call("set_face_uv", selection.ids, Vector2(3.0, 0.5), Vector2.ZERO, 0.0)
	paint.rebind()
	canvas.frame_uv()
	var expanded_uvs: PackedVector2Array = paint.selected_uvs()
	var expanded_bounds := SlabPaintCanvas._uv_bounds(expanded_uvs)
	_expect(expanded_bounds.size.x > 1.0, "UV fixture spans repeated texture tiles")
	var framed := true
	for uv in expanded_uvs:
		var point: Vector2 = canvas.call("_uv_to_canvas", uv)
		framed = framed and Rect2(Vector2.ZERO, canvas.size).grow(1.0).has_point(point)
	_expect(framed, "Fit UV frames every original unwrapped boundary corner")
	var second_face: int = 0
	for face in solid.call("get_faces"):
		if face != top:
			second_face = face
			break
	selection.set_ids(PackedInt64Array([top, second_face]))
	paint.rebind()
	canvas.frame_uv()
	var selected_loops: Array = paint.selected_uv_loops()
	_expect(second_face != 0 and selected_loops.size() == 2,
		"Material/UV renders every selected face outline")
	var all_framed := true
	for loop: PackedVector2Array in selected_loops:
		for uv in loop:
			all_framed = all_framed and Rect2(Vector2.ZERO, canvas.size).grow(1.0).has_point(canvas.call("_uv_to_canvas", uv))
	_expect(all_framed, "Fit UV frames all selected face outlines together")
	canvas.set("_uv_pixels_per_unit", 2.0)
	var before_zoom_out: float = canvas.get("_uv_pixels_per_unit")
	canvas.call("_zoom_at", canvas.size * 0.5, 1.0 / 1.12)
	_expect(float(canvas.get("_uv_pixels_per_unit")) < before_zoom_out,
		"UV wheel zoom-out stays monotonic after fitting a large extent")
	panel.free()
	paint.exit()
	solid.free()


func _rects_overlap(a: Rect2, b: Rect2) -> bool:
	return a.grow(-1.0).intersects(b.grow(-1.0))


func _mip_center(image: Image, level: int) -> Color:
	var width := maxi(1, image.get_width() >> level)
	var height := maxi(1, image.get_height() >> level)
	var offset := image.get_mipmap_offset(level)
	var data := image.get_data()
	var index := offset + ((height / 2) * width + width / 2) * 4
	return Color(data[index] / 255.0, data[index + 1] / 255.0, data[index + 2] / 255.0, data[index + 3] / 255.0)


func _buttons_under(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_buttons_under(child))
	return out


func _hover_at(control: Control, pos: Vector2) -> void:
	var vp: Viewport = control.get_viewport()
	if vp == null:
		return
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	vp.push_input(motion)


func _click_at(control: Control, pos: Vector2) -> void:
	var vp: Viewport = control.get_viewport()
	if vp == null:
		return
	vp.push_input(_mouse_button(true, pos))
	vp.push_input(_mouse_button(false, pos))


func _mouse_button(pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = pos
	event.global_position = pos
	return event


func _check_scene_roundtrip() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.name = "PaintRoundtrip"
	solid.call("make_box", Vector3(2, 3, 2))
	var top: int = _top_face(solid)
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	var actions := SlabActions.new(selection)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, SlabTestUndo.new())
	paint.enter()
	solid.set("materials", [StandardMaterial3D.new()])
	(solid.get("materials")[0] as StandardMaterial3D).albedo_color = Color(0.2, 0.4, 0.8)
	actions.material_slot = 0
	paint.rebind()
	paint.make_unique()
	paint.begin_stroke()
	paint.dab_uv(Vector2(0.5, 0.5))
	paint.end_stroke()
	var path: String = "user://slab_paint_test/roundtrip.png"
	_expect(paint.save_png(path) == OK, "roundtrip save writes a PNG")
	_expect(not paint.dirty, "save clears paint dirty")
	var packed := PackedScene.new()
	_expect(packed.pack(solid) == OK, "the painted solid packs")
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	var mats: Array = inst.get("materials")
	_expect(mats.size() >= 2, "reinstantiation keeps unique materials")
	var mat: StandardMaterial3D = mats[paint.slot()] if paint.slot() < mats.size() else null
	_expect(mat != null and mat.has_meta(SlabPaint.PNG_META), "the unique material still points at the PNG")
	var selection2 := SlabSelection.new()
	selection2.set_objects([inst])
	selection2.mode = SlabSelection.Mode.FACE
	selection2.set_ids(PackedInt64Array([top]))
	var actions2 := SlabActions.new(selection2)
	var paint2 := SlabPaint.new()
	paint2.bind(selection2, actions2, SlabTestUndo.new())
	paint2.enter()
	var slot: int = int(inst.call("face_uv", top).get("slot", 0))
	actions2.material_slot = slot
	paint2.rebind()
	var mid: Color = paint2.image().get_pixel(paint2.image().get_width() / 2, paint2.image().get_height() / 2)
	_expect(mid.r > 0.4, "reopened scene loads the painted albedo, %s" % mid)
	paint2.exit()
	paint.exit()
	inst.free()
	solid.free()


func _side_face(solid: Node3D) -> int:
	for id in PackedInt64Array(solid.call("get_faces")):
		var n: Vector3 = solid.call("face_normal", id)
		if absf(n.x) > 0.9:
			return id
	return _top_face(solid)


func _uv_matches_emit(mesh: ArrayMesh, local: Vector3, mapped: Vector2) -> bool:
	if mesh == null or mesh.get_surface_count() < 1:
		return false
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for i in verts.size():
		if verts[i].distance_to(local) > 0.002:
			continue
		if mapped.distance_to(uvs[i]) < 0.002:
			return true
	return false


func _top_face(solid: Node3D) -> int:
	var best: int = 0
	var up := -2.0
	for id in PackedInt64Array(solid.call("get_faces")):
		var n: Vector3 = solid.call("face_normal", id)
		if n.y > up:
			up = n.y
			best = id
	return best


func _expect(ok: bool, what: String) -> bool:
	if not ok:
		push_error("FAIL " + what)
		_fails += 1
	else:
		print("ok ", what)
	return ok


func _finish() -> void:
	if _fails != 0:
		push_error(str(_fails) + " paint_smoke failures")
		quit(1)
	else:
		print("paint_smoke ok")
		quit(0)
