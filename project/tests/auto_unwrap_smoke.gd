extends SceneTree

const Actions := preload("res://addons/slab/slab_actions.gd")
const Selection := preload("res://addons/slab/slab_selection.gd")
const History := preload("res://tests/slab_test_undo.gd")
const External := preload("res://addons/slab/slab_external_mesh.gd")
const PaintUv := preload("res://addons/slab/slab_paint_uv.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	check(solid.call("make_cylinder", 1.0, 2.0, 8) == OK, "curved auto unwrap fixture builds")
	var selection := Selection.new()
	selection.set_objects([solid])
	var history := History.new()
	var actions := Actions.new(selection, history)
	var reports: Array[String] = []
	actions.reported.connect(func(message: String) -> void: reports.append(message))
	actions.uv_pixels_per_meter = 64.0
	actions.uv_texture_resolution = 1024
	var row: Dictionary = actions.find("uv_auto_unwrap")
	check(not row.is_empty() and row.modes.has(Selection.Mode.OBJECT) and actions.disabled_reason(row).is_empty(), "Auto Unwrap is enabled in Object mode with no selected faces")
	var faces: PackedInt64Array = solid.call("get_faces")
	var seam: int = solid.call("get_edges")[0]
	solid.call("mark_uv_seams", PackedInt64Array([seam]), true)
	var before: PackedByteArray = solid.get("data")
	var before_objects: Array = selection.objects.duplicate()
	actions.run("uv_auto_unwrap")
	check(history.actions.size() == 1 and solid.get("data") != before, "whole object unwrap is one geometry transaction")
	check(selection.mode == Selection.Mode.OBJECT and selection.ids.is_empty() and selection.objects == before_objects, "Auto Unwrap preserves object selection without selecting faces")
	check(reports.back().contains("ready to paint"), "successful Auto Unwrap reports paint-ready atlas")
	check(PackedInt64Array(solid.call("get_uv_seams")).has(seam), "authored seam survives automatic object unwrap")
	var centre_pixels: Dictionary = {}
	for face in faces:
		var attrs: Dictionary = solid.call("face_uv", face)
		check(bool(attrs.unwrapped), "every face receives an unfolded mapping")
		for uv in PaintUv.face_uvs(solid, face):
			check(uv.x >= -0.00001 and uv.y >= -0.00001 and uv.x <= 1.00001 and uv.y <= 1.00001, "whole-object UVs fit paint atlas")
		var centre: Vector2 = PaintUv.point_uv(solid, face, solid.call("face_centroid", face))
		centre_pixels[PaintUv.uv_to_pixel(centre, 1024, 1024)] = true
	check(centre_pixels.size() == faces.size(), "all face centres occupy distinct paint texels")
	var after: PackedByteArray = solid.get("data")
	selection.set_uv_selection(PackedInt64Array([faces[0]]))
	history.undo()
	check(solid.get("data") == before and selection.ids.is_empty() and selection.get_uv_selection().is_empty() and selection.objects == before_objects, "Undo restores original geometry and selection")
	history.redo()
	check(solid.get("data") == after and selection.mode == Selection.Mode.OBJECT, "Redo restores packed geometry in Object mode")
	selection.mode = Selection.Mode.FACE
	check(selection.ids.is_empty() and actions.disabled_reason(row).is_empty(), "Face-mode Auto Unwrap needs no manual face selection")
	var face: int = faces[0]
	var pinned_uv: Vector2 = solid.call("face_uv", face).points[0]
	solid.call("pin_uv_corners", face, PackedInt32Array([0]), true)
	actions.run("uv_auto_unwrap")
	check(reports.back().contains("ready to paint"), "compatible pinned object can auto unwrap again")
	check(solid.call("face_uv", face).points[0].distance_to(pinned_uv) < .00001 and solid.call("face_uv", face).pins[0] == 1, "Auto Unwrap keeps pinned UV position and pin state")
	var points: PackedVector2Array = solid.call("face_uv", face).points
	points[1] = points[0] + Vector2(10, 10)
	solid.call("set_face_uv_points", face, points)
	solid.call("pin_uv_corners", face, PackedInt32Array([0, 1]), true)
	var incompatible: PackedByteArray = solid.get("data")
	var history_count: int = history.actions.size()
	actions.run("uv_auto_unwrap")
	check(solid.get("data") == incompatible and history.actions.size() == history_count, "incompatible pins refuse atomically without Undo entry")
	check(reports.back().to_lower().contains("pin"), "pin refusal explains constraint")
	# A separate clean source makes atlas overflow independent of pin refusal.
	var large: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(large)
	large.call("make_box", Vector3(20, 20, 20))
	selection.set_objects([large])
	var large_before: PackedByteArray = large.get("data")
	actions.uv_pixels_per_meter = 512
	actions.uv_texture_resolution = 128
	actions.run("uv_auto_unwrap")
	check(large.get("data") == large_before and history.actions.size() == history_count and reports.back().contains("too small"), "atlas overflow refuses without altering geometry or history")
	selection.set_objects([solid, large])
	check(not actions.disabled_reason(row).is_empty(), "multiple objects refuse rather than partially unwrapping only one")
	var external := External.from_mesh(BoxMesh.new())
	root.add_child(external)
	selection.mode = Selection.Mode.OBJECT
	selection.set_objects([external])
	actions.run("uv_auto_unwrap")
	check(reports.back() == Actions.PROMOTE_FIRST_TOOLTIP and history.actions.size() == history_count, "External mesh gets explicit Promote-first refusal")
	external.free()
	large.free()
	solid.free()
	print("AUTO_UNWRAP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
