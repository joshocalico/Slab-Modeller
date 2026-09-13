extends SceneTree

const Frame := preload("res://addons/slab/slab_selection_frame.gd")
const Selection := preload("res://addons/slab/slab_selection.gd")
const SolidGizmo := preload("res://addons/slab/gizmos/slab_solid_gizmo.gd")

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("ok " if ok else "FAIL ", message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parent := Node3D.new()
	parent.transform = Transform3D(Basis(Vector3.UP, 0.31), Vector3(4, -2, 1))
	root.add_child(parent)
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	parent.add_child(solid)
	solid.transform = Transform3D(Basis(Vector3.RIGHT, -0.27).scaled(Vector3(2.0, 0.5, 1.5)), Vector3(1, 3, -2))
	solid.call("make_box", Vector3(2, 4, 6))
	var vertices: PackedInt64Array = solid.call("get_vertices")
	var pair := PackedInt64Array([vertices[0], vertices[1]])
	var centre := Frame.make(solid, Selection.Mode.VERTEX, pair, Frame.Pivot.SELECTION)
	var expected: Vector3 = (solid.call("vertex_position", vertices[0]) + solid.call("vertex_position", vertices[1])) * 0.5
	check(centre.valid and centre.pivot_local.is_equal_approx(expected), "selection centre averages resolved vertices")
	check(centre.pivot_world.is_equal_approx(solid.to_global(expected)), "local and world pivots describe the same point")

	var active := Frame.make(solid, Selection.Mode.VERTEX, pair, Frame.Pivot.ACTIVE, Frame.Orientation.WORLD, vertices[1])
	check(active.pivot_local.is_equal_approx(solid.call("vertex_position", vertices[1])), "active element chooses the requested selected vertex")
	var custom_world := Vector3(3, 2, 1)
	var custom := Frame.make(solid, Selection.Mode.VERTEX, pair, Frame.Pivot.CUSTOM, Frame.Orientation.LOCAL, 0, custom_world)
	check(custom.pivot_world.is_equal_approx(custom_world), "custom pivot is accepted in world space")
	check(custom.world.basis.is_equal_approx(solid.global_transform.basis.orthonormalized()), "object axes discard nonuniform scale")

	var top := _top_face(solid)
	var face_ids := PackedInt64Array([top])
	var face_a := Frame.make(solid, Selection.Mode.FACE, face_ids, Frame.Pivot.ACTIVE, Frame.Orientation.FACE, top)
	var face_b := Frame.make(solid, Selection.Mode.FACE, face_ids, Frame.Pivot.ACTIVE, Frame.Orientation.FACE, top)
	check(face_a.valid and face_a.world.is_equal_approx(face_b.world), "selected-face frame is deterministic")
	var basis: Basis = face_a.world.basis
	check(is_equal_approx(basis.x.length(), 1.0) and is_equal_approx(basis.y.length(), 1.0) and is_equal_approx(basis.z.length(), 1.0), "face axes are unit length")
	check(absf(basis.x.dot(basis.y)) < 0.00001 and absf(basis.y.dot(basis.z)) < 0.00001, "face axes are orthogonal")
	var expected_normal := (solid.global_transform.basis.inverse().transposed() * (solid.call("face_normal", top) as Vector3)).normalized()
	check(basis.y.dot(expected_normal) > 0.99999, "face Y follows the inverse-transpose world normal")
	check(not Frame.make(solid, Selection.Mode.EDGE, PackedInt64Array([solid.call("get_edges")[0]]), Frame.Pivot.SELECTION, Frame.Orientation.FACE).valid, "face axes require a face selection")
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	selection.set_ids(face_ids)
	selection.configure_pivot(Selection.Pivot.ACTIVE)
	selection.configure_orientation(Selection.Orientation.FACE)
	check(Frame.from_selection(selection).world.is_equal_approx(face_a.world), "selection-state adapter uses active pivot and face orientation")
	check(SolidGizmo.line_material(SolidGizmo.HOT, false) == SolidGizmo.HOT, "visible-only selection keeps depth-tested material")
	check(SolidGizmo.line_material(SolidGizmo.HOT, true) == SolidGizmo.HOT_XRAY and SolidGizmo.line_material(SolidGizmo.WIRE, true) == SolidGizmo.WIRE_XRAY, "xray selection chooses translucent on-top line materials")
	var before: PackedByteArray = solid.get("data")
	var before_point: Vector3 = solid.call("vertex_position", vertices[0])
	var pivot := Vector3(0.25, -0.5, 0.75)
	var rotate_scale := Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3(1.1, 0.8, 1.25)), pivot)
	rotate_scale.origin -= rotate_scale.basis * pivot
	check(solid.call("transform_vertices", vertices, rotate_scale) == OK, "one native edit atomically rotates and scales a vertex set")
	var expected_point := rotate_scale * before_point
	check((solid.call("vertex_position", vertices[0]) as Vector3).distance_to(expected_point) < 0.002, "atomic transform uses the supplied local pivot mapping")
	var transformed: PackedByteArray = solid.get("data")
	check(transformed != before, "successful transform commits changed bytes")
	check(solid.call("transform_vertices", solid.call("get_vertices"), Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)) != OK, "collapsed transform is refused by the validity gate")
	check(solid.get("data") == transformed, "refused transform keeps the last valid bytes")

	solid.free()
	parent.free()
	print("selection_frame_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func _top_face(solid: Node3D) -> int:
	var best: int = 0
	var best_y := -INF
	for face in PackedInt64Array(solid.call("get_faces")):
		var world_normal := (solid.global_transform.basis.inverse().transposed() * (solid.call("face_normal", face) as Vector3)).normalized()
		if world_normal.y > best_y:
			best_y = world_normal.y
			best = face
	return best
