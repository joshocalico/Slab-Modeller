extends SceneTree

const Edit := preload("res://addons/slab/slab_uv_edit.gd")
const Selection := preload("res://addons/slab/slab_selection.gd")
const History := preload("res://tests/slab_test_undo.gd")
const PaintUv := preload("res://addons/slab/slab_paint_uv.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
	else:
		print("PASS ", label)

func _fixture() -> Dictionary:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.make_box(Vector3(2, 2, 2))
	var selection := Selection.new()
	selection.solid = solid
	return {"solid": solid, "selection": selection, "undo": History.new()}

func _run() -> void:
	_transform()
	_stitch_align()
	_relax()
	print("uv_edit_smoke failures=", failures)
	quit(1 if failures else 0)

func _transform() -> void:
	var f := _fixture()
	var solid: Node3D = f.solid
	var selection: RefCounted = f.selection
	var face: int = solid.get_faces()[0]
	var original: PackedByteArray = solid.data
	var points: PackedVector2Array = solid.face_uv(face)["points"]
	selection.set_uv_mode(Selection.UVMode.UV_VERT)
	selection.set_uv_selection(PackedInt64Array([solid.face_uv(face)["ids"][1]]))
	var edit := Edit.new()
	check(edit.begin(selection, f.undo), "vertex drag begins")
	edit.drag(Vector2(.25, -.1), 0)
	var after: PackedVector2Array = solid.face_uv(face)["points"]
	check(after[1].distance_to(points[1] + Vector2(.25, -.1)) < .00001 and after[0] == points[0] and after[2] == points[2], "only selected UV corner moves")
	edit.finish()
	check(f.undo.actions.size() == 1, "drag commits one Undo action")
	var moved: PackedByteArray = solid.data
	f.undo.undo()
	check(solid.data == original, "Undo restores exact pre-drag bytes")
	f.undo.redo()
	check(solid.data == moved, "Redo restores exact edited UVs")
	check(Edit.pin(selection, f.undo, true).is_empty(), "pin selected UV vertex")
	check(solid.face_uv(face)["pins"][1] == 1, "pin stored on selected corner")
	var reload: Node3D = ClassDB.instantiate("SlabSolid")
	reload.data = solid.data
	check(reload.face_uv(face)["pins"][1] == 1 and reload.face_uv(face)["points"] == after, "pin and edited UV survive reload")
	reload.free()
	var before_cancel: PackedByteArray = solid.data
	edit.begin(selection, f.undo)
	edit.drag(Vector2(1, 2), 0)
	edit.cancel()
	check(solid.data == before_cancel and f.undo.actions.size() == 2, "Escape restores UVs without a new Undo action")
	selection.set_uv_mode(Selection.UVMode.UV_EDGE)
	selection.set_uv_selection(PackedInt64Array([solid.face_uv(face)["ids"][2]]))
	var corners := Edit.selected_corners(solid, selection.uv_mode, selection.get_uv_selection())
	check(corners[face] == PackedInt32Array([2, 3]), "edge selection edits both endpoints")
	selection.set_uv_mode(Selection.UVMode.UV_FACE)
	selection.set_uv_selection(PackedInt64Array([face]))
	edit.begin(selection, f.undo)
	edit.drag(Vector2(.5, 0), 2)
	edit.finish()
	var rotated: PackedVector2Array = solid.face_uv(face)["points"]
	check(absf(rotated[0].distance_to(rotated[1]) - after[0].distance_to(after[1])) < .00001, "UV face rotation preserves edge lengths")
	solid.free()

func _stitch_align() -> void:
	var f := _fixture()
	var solid: Node3D = f.solid
	var selection: RefCounted = f.selection
	var edge: int = solid.get_edges()[0]
	var faces: PackedInt64Array = solid.edge_faces(edge)
	# Separate every face so this test has two unambiguous moving islands.
	solid.mark_uv_seams(solid.get_edges(), true)
	for k in faces.size():
		var points := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		for i in points.size(): points[i] += Vector2(k * 3, k * 2)
		solid.set_face_uv_points(faces[k], points)
	var ai: int = solid.face_edges(faces[0]).find(edge)
	var bi: int = solid.face_edges(faces[1]).find(edge)
	selection.set_uv_mode(Selection.UVMode.UV_EDGE)
	selection.set_uv_selection(PackedInt64Array([solid.face_uv(faces[0])["ids"][ai], solid.face_uv(faces[1])["ids"][bi]]))
	var before: PackedByteArray = solid.data
	check(Edit.stitch(selection, f.undo).is_empty(), "stitch separated sides of mesh edge")
	check(not solid.get_uv_seams().has(edge), "successful stitch clears shared seam")
	for endpoint in solid.edge_endpoints(edge):
		check(PaintUv.point_uv(solid, faces[0], endpoint).distance_to(PaintUv.point_uv(solid, faces[1], endpoint)) < .00001, "stitched edge endpoints coincide")
	check(PaintUv.island_faces(solid, PackedInt64Array([faces[0]])).has(faces[1]), "stitched faces form one UV island")
	f.undo.undo()
	check(solid.data == before, "stitch Undo restores UVs and seam atomically")
	solid.pin_uv_corners(faces[1], PackedInt32Array([0]), true)
	var pinned: PackedByteArray = solid.data
	check(not Edit.stitch(selection, f.undo).is_empty() and solid.data == pinned, "stitch refuses to move pinned island without mutation")
	solid.pin_uv_corners(faces[1], PackedInt32Array([0]), false)
	selection.set_uv_mode(Selection.UVMode.UV_FACE)
	selection.set_uv_selection(faces)
	check(Edit.align(selection, f.undo, 0, -1).is_empty(), "align two islands to left extent")
	var a: PackedVector2Array = solid.face_uv(faces[0])["points"]
	var b: PackedVector2Array = solid.face_uv(faces[1])["points"]
	check(is_equal_approx(a[0].x, b[0].x) and b[1].distance_to(b[0]) == 1.0, "alignment translates entire island without collapsing it")
	solid.free()

func _relax() -> void:
	var f := _fixture()
	var solid: Node3D = f.solid
	var selection: RefCounted = f.selection
	var face: int = solid.get_faces()[0]
	var normal: Vector3 = solid.face_normal(face)
	check(solid.subdivide_faces(PackedInt64Array([face])) == 0, "subdivide creates a UV patch with an interior vertex")
	var faces := PackedInt64Array()
	var distorted := {}
	var occurrences := {}
	for candidate in solid.get_faces():
		if solid.face_normal(candidate).dot(normal) > .999:
			faces.append(candidate)
			for vertex in solid.face_vertices(candidate):
				occurrences[vertex] = occurrences.get(vertex, 0) + 1
	for candidate in faces:
		var vertices: PackedInt64Array = solid.face_vertices(candidate)
		var points: PackedVector2Array = solid.face_uv(candidate)["points"]
		for i in vertices.size():
			if occurrences[vertices[i]] == 4:
				points[i] += Vector2(.35, .2)
				distorted[candidate] = i
		solid.set_face_uv_points(candidate, points)
	check(distorted.size() == 4, "distorted interior UV vertex is shared by four quads")
	selection.set_uv_mode(Selection.UVMode.UV_FACE)
	selection.set_uv_selection(faces)
	var boundary := {}
	for candidate in faces:
		boundary[candidate] = solid.face_uv(candidate)["points"]
	var message := Edit.relax(selection, f.undo)
	check(message.is_empty(), "relax operates on interior UV patch: " + message)
	for candidate in faces:
		var points: PackedVector2Array = solid.face_uv(candidate)["points"]
		for i in points.size():
			if distorted.get(candidate, -1) == i:
				check(points[i].distance_to(boundary[candidate][i]) > .05, "relax moves distorted interior vertex")
			else:
				check(points[i].distance_to(boundary[candidate][i]) < .00001, "relax preserves patch boundary")
	solid.free()
