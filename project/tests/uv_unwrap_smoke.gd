extends SceneTree

const PaintUv := preload("res://addons/slab/slab_paint_uv.gd")
const Undo := preload("res://tests/slab_test_undo.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const Selection := preload("res://addons/slab/slab_selection.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("ok " if ok else "FAIL ", message)


func _run() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	check(solid.call("make_cylinder", 2.0, 3.0, 8) == OK, "UV cylinder builds")
	var sides := _side_faces(solid)
	check(sides.size() == 8, "curved patch contains eight hinged faces")
	var seam := _shared_edge(solid, sides[0], sides[1])
	var before_seam: PackedByteArray = solid.get("data")
	check(solid.call("mark_uv_seams", PackedInt64Array([seam]), true) == OK, "edge is marked as a UV seam")
	check(PackedInt64Array(solid.call("get_uv_seams")).has(seam), "seam query returns the marked edge")
	var after_seam: PackedByteArray = solid.get("data")
	check(after_seam != before_seam, "serialized data captures seam mutation")

	var overflow_before: PackedByteArray = solid.get("data")
	var overflow: Dictionary = solid.call("unwrap_uv", sides, 512.0, 1024)
	check(bool(overflow.get("atlas_overflow", false)), "oversized fixed-density atlas reports overflow")
	check(int(overflow.get("suggested_texture_resolution", 0)) > 1024, "overflow suggests a larger texture")
	check(solid.get("data") == overflow_before, "atlas overflow is atomic")
	var result: Dictionary = solid.call("unwrap_uv", sides, 128.0, 2048)
	check(int(result.get("error", -1)) == OK, "curved patch unwraps")
	check(int(result.get("islands", 0)) >= 1, "unwrap reports its island count")
	check(result.has("auto_seams"), "unwrap reports automatic cuts explicitly")
	var unwrapped_data: PackedByteArray = solid.get("data")
	check(unwrapped_data != after_seam, "serialized data captures unfolded mappings")
	var centre_pixels: Dictionary = {}
	for selected_face in sides:
		for uv in PaintUv.face_uvs(solid, selected_face):
			check(uv.x >= -0.0001 and uv.y >= -0.0001 and uv.x <= 1.0001 and uv.y <= 1.0001,
				"unmodified paint sample stays inside one texture tile")
		var centre_uv := PaintUv.point_uv(solid, selected_face, solid.call("face_centroid", selected_face))
		centre_pixels[PaintUv.uv_to_pixel(centre_uv, 2048, 2048)] = true
	check(centre_pixels.size() == sides.size(), "each cylinder face centre occupies a unique painter texel")

	var face: int = sides[3]
	check(solid.call("set_face_uv", PackedInt64Array([face]), Vector2(1.75, 0.8), Vector2(0.13, -0.27), 0.41) == OK,
		"numeric UV transform applies after unfolding")
	var corner: Vector3 = PackedVector3Array(solid.call("face_corners", face))[0]
	var painted_uv := PaintUv.point_uv(solid, face, corner)
	check(_uv_matches_emit(solid.call("build_mesh"), corner, painted_uv),
		"painter sample matches emitted triangle UV after unfold, rotation and offset")
	var final_data: PackedByteArray = solid.get("data")

	var clone: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(clone)
	clone.set("data", final_data)
	var reload_attrs: Dictionary = clone.call("face_uv", face)
	check(bool(reload_attrs.get("unwrapped", false)), "save and reload preserves unfolded mapping")
	check(PackedInt64Array(clone.call("get_uv_seams")).has(seam), "save and reload preserves authored seam")
	var reload_uv := PaintUv.point_uv(clone, face, corner)
	check(reload_uv.distance_to(painted_uv) < 0.0001, "save and reload preserves painter UV sample")
	check(_uv_matches_emit(clone.call("build_mesh"), corner, reload_uv), "reloaded painter UV still matches emit")
	var shared_selection := Selection.new()
	shared_selection.set_objects([clone])
	shared_selection.mode = Selection.Mode.EDGE
	shared_selection.set_ids(PackedInt64Array([seam]))
	var shared_undo := Undo.new()
	var shared_actions := Actions.new(shared_selection, shared_undo)
	shared_actions.run("clear_uv_seam")
	check(not PackedInt64Array(clone.call("get_uv_seams")).has(seam) and shared_undo.actions.size() == 1,
		"shared Clear Seam command edits serialized data as one undo action")
	shared_undo.undo()
	check(PackedInt64Array(clone.call("get_uv_seams")).has(seam), "shared seam undo restores the marked edge")
	shared_selection.mode = Selection.Mode.FACE
	shared_selection.set_ids(sides)
	var reports: Array[String] = []
	shared_actions.reported.connect(func(text: String) -> void: reports.append(text))
	shared_actions.uv_scale = Vector2(2.0, 3.0)
	shared_actions.uv_offset = Vector2(0.25, -0.5)
	shared_actions.uv_rotation_degrees = 15.0
	var before_shared_overflow: PackedByteArray = clone.get("data")
	var undo_count_before_overflow: int = shared_undo.actions.size()
	shared_actions.run("uv_unwrap")
	check(not reports.is_empty() and reports.back().contains("too small") and reports.back().contains("Pixels / metre") and reports.back().contains("Texture px"),
		"shared Unwrap turns atlas overflow into actionable density and resolution guidance")
	check(clone.get("data") == before_shared_overflow, "shared atlas overflow leaves UV data unchanged")
	check(shared_undo.actions.size() == undo_count_before_overflow
		and shared_actions.uv_scale == Vector2(2.0, 3.0)
		and shared_actions.uv_offset == Vector2(0.25, -0.5)
		and is_equal_approx(shared_actions.uv_rotation_degrees, 15.0),
		"shared atlas overflow preserves history and pending placement state")
	shared_actions.uv_pixels_per_meter = 128.0
	shared_actions.uv_texture_resolution = 2048
	shared_actions.run("uv_unwrap")
	check(not reports.is_empty() and reports.back().contains("island") and reports.back().contains("automatic cut"),
		"shared Unwrap recovery reports islands and automatic cuts")
	check(shared_actions.uv_scale == Vector2.ONE and shared_actions.uv_offset == Vector2.ZERO
		and is_zero_approx(shared_actions.uv_rotation_degrees),
		"successful Unwrap resets shared placement state to the kernel mapping")

	var undo := Undo.new()
	undo.create_action("Unwrap UV")
	undo.add_do_property(solid, "data", final_data)
	undo.add_undo_property(solid, "data", before_seam)
	undo.commit_action(false)
	undo.undo()
	check(solid.get("data") == before_seam and solid.call("get_uv_seams").is_empty(),
		"one stored-data undo restores seams and mapping together")
	undo.redo()
	check(solid.get("data") == final_data and PackedInt64Array(solid.call("get_uv_seams")).has(seam),
		"redo restores seams and mapping together")

	clone.free()
	solid.free()
	print("uv_unwrap_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func _side_faces(solid: Node3D) -> PackedInt64Array:
	var out := PackedInt64Array()
	for face in PackedInt64Array(solid.call("get_faces")):
		if absf((solid.call("face_normal", face) as Vector3).y) < 0.2:
			out.append(face)
	return out


func _shared_edge(solid: Node3D, face_a: int, face_b: int) -> int:
	for edge in PackedInt64Array(solid.call("face_edges", face_a)):
		var faces := PackedInt64Array(solid.call("edge_faces", edge))
		if faces.has(face_b):
			return edge
	return 0


func _uv_matches_emit(mesh: ArrayMesh, local: Vector3, mapped: Vector2) -> bool:
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i in verts.size():
			if verts[i].distance_to(local) < 0.002 and uvs[i].distance_to(mapped) < 0.002:
				return true
	return false
