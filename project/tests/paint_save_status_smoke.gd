extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPaint := preload("res://addons/slab/slab_paint.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3.ONE)
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([solid.call("get_faces")[0]]))
	var paint := SlabPaint.new()
	paint.bind(selection, SlabActions.new(selection), SlabTestUndo.new())
	paint.enter()
	paint.make_unique()
	solid.set("scene_file_path", "res://owner.tscn")
	var path := "user://slab_paint_test/save_status.png"
	_check(paint.save_png(path) == OK, "Save Paint writes its image")
	_check(paint.save_status() == "Texture saved. Scene still needs saving.",
		"Save Paint waits for the owning scene")

	paint.scene_saved("res://unrelated.tscn")
	_check(paint.save_status() == "Texture saved. Scene still needs saving.",
		"saving an unrelated scene does not clear the pending message")

	paint.scene_saved("res://owner.tscn")
	_check(paint.save_status().is_empty(), "saving the owning scene clears the pending message")
	_check(paint.save_png(path) == OK, "Save Paint can create another pending scene save")
	solid.set("scene_file_path", "res://owner-renamed.tscn")
	paint.scene_saved("res://owner-renamed.tscn")
	_check(paint.save_status().is_empty(), "Save As clears the owning scene's pending message")

	paint.tool = SlabPaint.Tool.PIXEL
	_check(paint.begin_stroke(), "a new stroke starts after saving")
	paint.dab_pixel(Vector2(12, 12))
	paint.end_stroke()
	_check(paint.save_status() == "Unsaved paint", "a new stroke truthfully reports unsaved paint")

	paint.exit()
	solid.free()
	print("paint_save_status_smoke failures=%d" % _failures)
	quit(1 if _failures else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	push_error(message)
