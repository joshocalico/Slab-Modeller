extends SceneTree

const SlabPaint := preload("res://addons/slab/slab_paint.gd")
const SlabPaintUv := preload("res://addons/slab/slab_paint_uv.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")

class FocusHost extends RefCounted:
	var selection: RefCounted
	func focus_solid(solid: Node3D, _additive: bool) -> void:
		selection.set_objects([solid])

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	_check_curved_first_target(world)
	_check_curved_mixed_materials(world)
	_check_curved_uv_framing(world)
	_check_curved_pixel_mip_refresh(world)
	_check_cross_solid_curved_transfer(world)
	_check_curved_undo_brush_preservation(world)

	world.free()
	print("paint_curved_region_smoke failures=%d" % _failures)
	quit(1 if _failures else 0)


func _check_curved_first_target(world: Node3D) -> void:
	var cylinder := _cylinder(world, "CurvedFirstTarget", Vector3.ZERO)
	var teal := StandardMaterial3D.new()
	teal.resource_name = "Teal Steel"
	teal.albedo_color = Color(0.15, 0.45, 0.48)
	cylinder.set("materials", [teal])
	var sides := _side_faces(cylinder)
	_check(sides.size() >= 6, "cylinder has curved side faces")
	cylinder.call("set_face_material", sides, 0)
	var selection := SlabSelection.new()
	selection.mode = SlabSelection.Mode.FACE
	var actions := SlabActions.new(selection)
	var undo := SlabTestUndo.new()
	var host := FocusHost.new()
	host.selection = selection
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo, host)
	_select(selection, cylinder, [sides[0]])
	paint.enter()
	_check(paint.brush_material() == teal and paint.material() == teal,
		"curved face entry adopts its material as first-target brush")
	_check(undo.actions.is_empty(), "first-target inspection does not create history")
	_select(selection, cylinder, sides)
	_check(paint.brush_material() == teal and paint.selected_material_summary() == "Teal Steel",
		"multi-curved-face same-material shows material name, not Mixed")
	paint.exit()
	cylinder.free()


func _check_curved_mixed_materials(world: Node3D) -> void:
	var cylinder := _cylinder(world, "CurvedMixed", Vector3(5, 0, 0))
	var teal := StandardMaterial3D.new()
	teal.resource_name = "Teal Steel"
	var timber := StandardMaterial3D.new()
	timber.resource_name = "Timber"
	cylinder.set("materials", [teal, timber])
	var sides := _side_faces(cylinder)
	var half := sides.size() / 2
	cylinder.call("set_face_material", sides.slice(0, half), 0)
	cylinder.call("set_face_material", sides.slice(half), 1)
	var selection := SlabSelection.new()
	selection.mode = SlabSelection.Mode.FACE
	var actions := SlabActions.new(selection)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, SlabTestUndo.new())
	_select(selection, cylinder, sides)
	paint.enter()
	_check(paint.selected_material_summary() == "Mixed" and paint.brush_material() == null,
		"multi-curved-face mixed materials shows Mixed and clears brush")
	_check(paint.brush_preview_caption().begins_with("Selected: Mixed"),
		"mixed curved selection gives recovery guidance caption")
	_check(not paint.can_make_unique(), "Make Unique refuses mixed curved selection")
	paint.choose_brush_material(teal)
	_check(paint.can_make_unique(), "explicit brush allows Make Unique on mixed curved")
	paint.exit()
	cylinder.free()


func _check_curved_uv_framing(world: Node3D) -> void:
	var cylinder := _cylinder(world, "CurvedFrame", Vector3(10, 0, 0))
	var teal := StandardMaterial3D.new()
	teal.resource_name = "Teal Steel"
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(teal.albedo_color)
	teal.albedo_texture = ImageTexture.create_from_image(img)
	cylinder.set("materials", [teal])
	var sides := _side_faces(cylinder)
	var selection := SlabSelection.new()
	selection.mode = SlabSelection.Mode.FACE
	var undo := SlabTestUndo.new()
	var actions := SlabActions.new(selection, undo)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	_select(selection, cylinder, sides)
	paint.enter()
	var data_before_unwrap: PackedByteArray = cylinder.get("data")
	actions.uv_pixels_per_meter = 64.0
	actions.uv_texture_resolution = 512
	actions.run("uv_unwrap")
	var data_after_unwrap: PackedByteArray = cylinder.get("data")
	var loops: Array = paint.selected_uv_loops()
	_check(loops.size() == sides.size(), "unwrapped curved faces each have UV loops")
	var all_finite := true
	var all_in_unit := true
	for loop: PackedVector2Array in loops:
		for uv: Vector2 in loop:
			if not is_finite(uv.x) or not is_finite(uv.y):
				all_finite = false
			if uv.x < -0.01 or uv.y < -0.01 or uv.x > 1.01 or uv.y > 1.01:
				all_in_unit = false
	_check(all_finite, "curved unwrapped UVs are all finite")
	_check(all_in_unit, "curved unwrapped UVs fit within [0,1] tile")
	undo.undo()
	_check(cylinder.get("data") == data_before_unwrap, "Undo restores planar mapping data")
	undo.redo()
	_check(cylinder.get("data") == data_after_unwrap, "Redo restores unwrapped mapping data")
	paint.exit()
	cylinder.free()


func _check_curved_pixel_mip_refresh(world: Node3D) -> void:
	var cylinder := _cylinder(world, "CurvedPixel", Vector3(15, 0, 0))
	var teal := StandardMaterial3D.new()
	teal.resource_name = "Teal Steel"
	cylinder.set("materials", [teal])
	var sides := _side_faces(cylinder)
	var selection := SlabSelection.new()
	selection.mode = SlabSelection.Mode.FACE
	var actions := SlabActions.new(selection)
	actions.uv_texture_resolution = 128
	var undo := SlabTestUndo.new()
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	_select(selection, cylinder, [sides[0]])
	paint.enter()
	var slot := paint.make_unique()
	_check(slot >= 0, "Make Unique on curved face succeeds")
	_check(paint.is_owned(paint.material()), "curved unique material is owned")
	paint.tool = SlabPaint.Tool.PIXEL
	_check(paint.begin_stroke(), "curved pixel stroke starts on owned material")
	var before_center: Color = paint.image().get_pixel(64, 64)
	paint.dab_uv(Vector2(0.5, 0.5))
	paint.end_stroke()
	var after_center: Color = paint.image().get_pixel(64, 64)
	var color_changed := _color_distance(before_center, after_center) > 0.2
	_check(color_changed,
		"curved pixel dab writes to image center: before=%s after=%s" % [before_center, after_center])
	var tex: ImageTexture = paint.texture() as ImageTexture
	_check(tex != null and tex.get_image() != null and tex.get_image().has_mipmaps(),
		"curved stroke regenerates mipmaps for viewport display")
	var mip_level: int = 1
	var mip_offset: int = paint.image().get_mipmap_offset(mip_level)
	var mip_width: int = maxi(1, paint.image().get_width() >> mip_level)
	var mip_height: int = maxi(1, paint.image().get_height() >> mip_level)
	var mip_center_idx: int = mip_offset + (mip_height / 2 * mip_width + mip_width / 2) * 4
	var data: PackedByteArray = paint.image().get_data()
	var mip_center_r: float = float(data[mip_center_idx]) / 255.0
	_check(mip_center_r > 0.35, "minified mip level shows the painted red: %.3f" % mip_center_r)
	paint.exit()
	cylinder.free()


func _check_cross_solid_curved_transfer(world: Node3D) -> void:
	var source := _cylinder(world, "CurvedSource", Vector3(20, 0, 0))
	var target := _cylinder(world, "CurvedTarget", Vector3(25, 0, 0))
	var teal := StandardMaterial3D.new()
	teal.resource_name = "Teal Steel"
	var timber := StandardMaterial3D.new()
	timber.resource_name = "Timber"
	source.set("materials", [teal])
	target.set("materials", [timber])
	var source_sides := _side_faces(source)
	var target_sides := _side_faces(target)
	var selection := SlabSelection.new()
	selection.mode = SlabSelection.Mode.FACE
	var actions := SlabActions.new(selection)
	var undo := SlabTestUndo.new()
	var host := FocusHost.new()
	host.selection = selection
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo, host)
	_select(selection, source, [source_sides[0]])
	paint.enter()
	_check(paint.brush_material() == teal, "source curved entry adopts Teal brush")
	_select(selection, target, [target_sides[0]])
	_check(paint.brush_material() == teal and paint.slot() == -1,
		"switching to target preserves Teal brush even though target has Timber")
	var original_data: PackedByteArray = target.get("data")
	var original_mats: Array = (target.get("materials") as Array).duplicate()
	paint.assign_active_to_selection()
	_check(target.get("data") != original_data, "cross-solid Assign edits target curved face")
	var new_mats: Array = target.get("materials")
	_check(new_mats.has(teal), "cross-solid Assign transfers Teal by resource identity")
	_check(_slot(target, target_sides[0]) == new_mats.find(teal),
		"cross-solid Assign assigns correct slot for transferred resource")
	undo.undo()
	_check(target.get("data") == original_data and target.get("materials") == original_mats,
		"Undo restores original curved target data and materials")
	_check(paint.brush_material() == teal,
		"Cmd-Z restores curved faces while brush label stays (A4)")
	paint.exit()
	source.free()
	target.free()


func _check_curved_undo_brush_preservation(world: Node3D) -> void:
	var cylinder := _cylinder(world, "CurvedUndoBrush", Vector3(30, 0, 0))
	var teal := StandardMaterial3D.new()
	teal.resource_name = "Teal Steel"
	var timber := StandardMaterial3D.new()
	timber.resource_name = "Timber"
	cylinder.set("materials", [teal])
	var sides := _side_faces(cylinder)
	var selection := SlabSelection.new()
	selection.mode = SlabSelection.Mode.FACE
	var actions := SlabActions.new(selection)
	var undo := SlabTestUndo.new()
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	_select(selection, cylinder, [sides[0]])
	paint.enter()
	_check(paint.brush_material() == teal, "curved entry brush is Teal")
	paint.choose_brush_material(timber)
	_check(paint.brush_material() == timber, "explicitly chosen Timber brush")
	paint.assign_active_to_selection()
	_check(paint.brush_material() == timber, "Assign preserves chosen brush")
	var after_assign: PackedByteArray = cylinder.get("data")
	undo.undo()
	_check(paint.brush_material() == timber and cylinder.get("data") != after_assign,
		"Undo restores data but keeps Timber brush label (A4 - Cmd-Z)")
	undo.redo()
	_check(paint.brush_material() == timber and cylinder.get("data") == after_assign,
		"Redo restores assignment while brush label stays")
	paint.exit()
	cylinder.free()


func _cylinder(parent: Node, title: String, position: Vector3) -> Node3D:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	parent.add_child(solid)
	solid.name = title
	solid.position = position
	solid.call("make_cylinder", 1.0, 2.0, 8)
	return solid


func _side_faces(solid: Node3D) -> PackedInt64Array:
	var out := PackedInt64Array()
	for face in PackedInt64Array(solid.call("get_faces")):
		var n: Vector3 = solid.call("face_normal", face)
		if absf(n.y) < 0.3:
			out.append(face)
	return out


func _select(selection: RefCounted, solid: Node3D, faces: Array) -> void:
	selection.set_objects([solid])
	selection.set_ids(PackedInt64Array(faces))


func _slot(solid: Node3D, face: int) -> int:
	return int(solid.call("face_uv", face).get("slot", -1))


func _color_distance(a: Color, b: Color) -> float:
	return sqrt((a.r - b.r) ** 2 + (a.g - b.g) ** 2 + (a.b - b.b) ** 2)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("ok ", message)
		return
	_failures += 1
	push_error(message)
