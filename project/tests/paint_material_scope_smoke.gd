extends SceneTree

const SlabPaint := preload("res://addons/slab/slab_paint.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")

class FocusHost extends RefCounted:
	var selection: RefCounted
	func focus_solid(solid: Node3D, _additive: bool) -> void:
		# Native focus synchronously changes selection before the click finishes.
		selection.set_objects([solid])

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var a := _box(world, "Source", Vector3(-3, 0, 0))
	var b := _box(world, "Target", Vector3(3, 0, 0))
	var stone := StandardMaterial3D.new()
	stone.resource_name = "Stone"
	stone.albedo_color = Color(0.2, 0.3, 0.8)
	var timber := StandardMaterial3D.new()
	timber.resource_name = "Timber"
	timber.albedo_color = Color(0.6, 0.3, 0.1)
	a.set("materials", [stone, timber])
	b.set("materials", [stone, stone])
	var top_a := _top(a)
	var top_b := _top(b)
	var side_a := _other(a, top_a)
	var side_b := _other(b, top_b)
	a.call("set_face_material", PackedInt64Array([top_a]), 1)
	b.call("set_face_material", PackedInt64Array([top_b]), 1)
	var original_a: PackedByteArray = a.get("data")
	var original_b: PackedByteArray = b.get("data")
	var original_materials: Array = (b.get("materials") as Array).duplicate()
	var selection := SlabSelection.new()
	selection.mode = SlabSelection.Mode.FACE
	_select(selection, a, [top_a])
	var actions := SlabActions.new(selection)
	var undo := SlabTestUndo.new()
	var host := FocusHost.new()
	host.selection = selection
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo, host)
	paint.enter()
	_check(paint.brush_material() == timber and paint.material() == timber,
		"entry inspects the face's nonzero material slot")
	_check(a.get("data") == original_a and undo.actions.is_empty(),
		"entry inspection does not edit geometry or history")

	_select(selection, b, [top_b])
	_check(paint.brush_material() == timber and paint.material() == timber and paint.slot() == -1,
		"selection preserves the brush even when absent from target slots")
	_check(b.get("materials") == original_materials, "selection alone does not append a material")
	paint.sample_face(a, top_a)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0, 9, 8), Vector3.ZERO, Vector3.UP)
	camera.current = true
	var point := camera.unproject_position(b.to_global(b.call("face_centroid", top_b)))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	paint.handle_3d(camera, click, world)
	var painted_b: PackedByteArray = b.get("data")
	var target_mats: Array = b.get("materials")
	_check(target_mats.size() == 3 and target_mats[2] == timber and _slot(b, top_b) == 2,
		"viewport paint transfers resource identity despite conflicting slot one")
	_check(a.get("data") == original_a and _slot(b, side_b) == 0,
		"paint changes only the hit face, leaving source and other target faces intact")
	_check(undo.actions.size() == 1, "material transfer creates one undo action")
	undo.undo()
	_check(b.get("data") == original_b and b.get("materials") == original_materials,
		"Undo restores target bytes and removes the appended material")
	_check(paint.brush_material() == timber and paint.slot() == -1,
		"Undo does not replace the brush with target slot zero")
	undo.redo()
	_check(b.get("data") == painted_b and (b.get("materials") as Array)[2] == timber,
		"Redo restores the same resource and face assignment")
	paint.handle_3d(camera, click, world)
	_check((b.get("materials") as Array).size() == 3 and undo.actions.size() == 1,
		"repainting the same face reuses its material without a redundant action")

	_select(selection, b, [side_b])
	paint.tool = SlabPaint.Tool.PIXEL
	_check(paint.material() == stone and paint.brush_material() == timber,
		"Pixel binds the selected face while preserving the material brush")
	_check(not paint.begin_stroke(), "shared selected texture refuses pixel mutation")
	_select(selection, b, [top_b, side_b])
	_check(paint.material() == null and not paint.begin_stroke(),
		"mixed Pixel selection cannot edit an unrelated brush image")
	paint.tool = SlabPaint.Tool.MATERIAL_UV
	_check(paint.material() == timber and paint.brush_material() == timber,
		"returning to Material/UV restores the chosen brush")

	paint.exit()
	_select(selection, a, [top_a, side_a])
	var history_before := undo.actions.size()
	paint.enter()
	_check(paint.selected_material_summary() == "Mixed" and paint.brush_material() == null,
		"mixed entry reports mixed faces and chooses no arbitrary brush")
	paint.assign_active_to_selection()
	_check(a.get("data") == original_a and undo.actions.size() == history_before,
		"Assign without a brush leaves a mixed selection unchanged")
	_check(not paint.sample_selection() and selection.ids.size() == 2,
		"Sample refuses mixed materials without collapsing selection")
	_check(not paint.can_make_unique() and paint.make_unique() == -1,
		"Make Unique refuses a mixed selection with no chosen brush")
	_check(a.get("data") == original_a and undo.actions.size() == history_before,
		"refused mixed Make Unique leaves faces and history untouched")
	paint.select_material_slot(1)
	_check(paint.can_make_unique(), "an explicitly chosen brush can replace a mixed Material/UV selection")

	paint.exit()
	_select(selection, a, [top_a])
	paint.enter()
	var copy_target := _box(world, "CopyTarget", Vector3(14, 0, 0))
	copy_target.set("materials", [stone, stone])
	_select(selection, copy_target, [_top(copy_target)])
	_check(paint.make_unique() >= 0 and paint.material() != timber
		and paint.material().albedo_color == timber.albedo_color,
		"Make Unique copies an absent brush resource before any Assign")

	paint.exit()
	var blank := _box(world, "Default", Vector3(10, 0, 0))
	_select(selection, blank, [_top(blank)])
	paint.enter()
	_check(paint.selected_material_summary() == "Default" and paint.brush_material() == null,
		"default entry does not retain an unrelated material")
	_check(paint.make_unique() >= 0 and paint.material() != stone and paint.material() != timber,
		"Make Unique can start artwork on a default face")
	_check(paint.brush_material() == paint.material(), "Make Unique selects its new copy as the brush")
	var owned := paint.material()
	var b_mats: Array = b.get("materials")
	b_mats.append(owned)
	b.set("materials", b_mats)
	_select(selection, b, [side_b])
	paint.tool = SlabPaint.Tool.PIXEL
	paint.select_material_slot(b_mats.size() - 1)
	_check(paint.material() == stone and not paint.begin_stroke(),
		"choosing an owned palette brush cannot redirect Pixel away from the selected face")
	paint.exit()
	world.free()
	print("paint_material_scope_smoke failures=%d" % _failures)
	quit(1 if _failures else 0)


func _box(parent: Node, title: String, position: Vector3) -> Node3D:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	parent.add_child(solid)
	solid.name = title
	solid.position = position
	solid.call("make_box", Vector3(2, 2, 2))
	return solid


func _select(selection: RefCounted, solid: Node3D, faces: Array) -> void:
	selection.set_objects([solid])
	selection.set_ids(PackedInt64Array(faces))


func _top(solid: Node3D) -> int:
	for face in solid.call("get_faces"):
		if (solid.call("face_normal", face) as Vector3).y > 0.9:
			return face
	return 0


func _other(solid: Node3D, excluded: int) -> int:
	for face in solid.call("get_faces"):
		if face != excluded:
			return face
	return 0


func _slot(solid: Node3D, face: int) -> int:
	return int(solid.call("face_uv", face).get("slot", -1))


func _check(ok: bool, message: String) -> void:
	if ok:
		print("ok ", message)
		return
	_failures += 1
	push_error(message)
