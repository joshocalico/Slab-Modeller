extends SceneTree

const Controller := preload("res://addons/slab/slab_snap_align.gd")
const Host := preload("res://tests/slab_test_host.gd")
const Selection := preload("res://addons/slab/slab_selection.gd")
const Undo := preload("res://tests/slab_test_undo.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
const Paint := preload("res://addons/slab/slab_paint.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("ok " if ok else "FAIL ", message)


func _box(parent: Node, name: String, transform: Transform3D) -> Node3D:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.name = name
	parent.add_child(solid)
	solid.transform = transform
	solid.call("make_box", Vector3(2, 2, 2))
	return solid


func _run() -> void:
	var source_parent := Node3D.new()
	source_parent.transform = Transform3D(Basis(Vector3.UP, 0.37), Vector3(3, 1, -2))
	root.add_child(source_parent)
	var target_parent := Node3D.new()
	target_parent.transform = Transform3D(Basis(Vector3.RIGHT, -0.23), Vector3(-4, 2, 5))
	root.add_child(target_parent)
	var source := _box(source_parent, "SnapSource", Transform3D(Basis.IDENTITY.scaled(Vector3(1.2, 0.8, 1.1)), Vector3(1, 0, 2)))
	var target := _box(target_parent, "SnapTarget", Transform3D(Basis(Vector3.UP, -0.41), Vector3(2, 1, -1)))
	var selection := Selection.new()
	selection.solid = source
	selection.mode = Selection.Mode.VERTEX
	var source_vertex: int = source.call("get_vertices")[0]
	var target_vertex: int = target.call("get_vertices")[-1]
	selection.set_ids(PackedInt64Array([source_vertex]))
	var undo := Undo.new()
	var tool := Controller.new(selection, Host.over(root).stub_undo(undo))
	var source_before: PackedByteArray = source.get("data")
	var target_world := target.to_global(target.call("vertex_position", target_vertex))
	check(tool.begin_vertex_snap(), "vertex snap starts from selected geometry")
	check(tool.target_vertex(target, target_vertex), "another solid supplies an exact target vertex")
	check(not tool.preview().is_empty() and not (tool.preview()["lines"] as PackedVector3Array).is_empty(), "vertex snap exposes a preview line")
	tool.cancel()
	check(source.get("data") == source_before and undo.actions.is_empty(), "cancel changes neither geometry nor undo")
	check(tool.begin_vertex_snap() and tool.target_vertex(target, target_vertex) and tool.confirm(), "vertex snap applies")
	check(source.to_global(source.call("vertex_position", source_vertex)).distance_to(target_world) < 0.002, "selected vertex lands on the nearest source-lattice point to the transformed target")
	check(undo.actions.size() == 1, "vertex snap is one undo action")
	var source_after: PackedByteArray = source.get("data")
	undo.undo()
	check(source.get("data") == source_before, "vertex snap undo restores geometry")
	undo.redo()
	check(source.get("data") == source_after, "vertex snap redo restores geometry")

	var align_parent := Node3D.new()
	align_parent.transform = Transform3D(Basis(Vector3.FORWARD, 0.19), Vector3(2, -1, 3))
	root.add_child(align_parent)
	var align_source := _box(align_parent, "AlignSource", Transform3D(Basis(Vector3.UP, 0.31), Vector3(-2, 2, 1)))
	selection.solid = align_source
	selection.mode = Selection.Mode.FACE
	var source_face := _face_along(align_source, Vector3.UP)
	var target_face := _face_along(target, Vector3.RIGHT)
	selection.set_ids(PackedInt64Array([source_face]))
	var align_undo := Undo.new()
	tool = Controller.new(selection, Host.over(root).stub_undo(align_undo))
	var align_before := align_source.transform
	check(tool.begin_face_align() and tool.target_face(target, target_face), "face alignment previews across transformed parents")
	var desired: Transform3D = tool.preview()["transform"]
	check(desired != align_before, "face alignment exposes a new rigid transform")
	check(tool.confirm(), "face alignment applies")
	var source_center := align_source.to_global(align_source.call("face_centroid", source_face))
	var target_center := target.to_global(target.call("face_centroid", target_face))
	var source_normal := (align_source.global_transform.basis * (align_source.call("face_normal", source_face) as Vector3)).normalized()
	var target_normal := (target.global_transform.basis * (target.call("face_normal", target_face) as Vector3)).normalized()
	check(source_center.is_equal_approx(target_center), "source face centre lands on target plane anchor")
	check(source_normal.dot(target_normal) < -0.9999, "aligned face normals oppose")
	check(align_undo.actions.size() == 1, "face alignment is one undo action")
	align_undo.undo()
	check(align_source.transform.is_equal_approx(align_before), "face alignment undo restores local transform")
	align_undo.redo()
	check(align_source.transform.is_equal_approx(desired), "face alignment redo restores target transform")

	var integrated := _box(root, "IntegratedSnapSource", Transform3D.IDENTITY)
	var integrated_host: RefCounted = Host.over(root).stub_undo(Undo.new())
	integrated_host.stub_host_selection([integrated])
	var viewport := SlabViewport.new(integrated_host)
	var integrated_selection = viewport.state()
	viewport.adopt_host_selection()
	var actions := Actions.new(integrated_selection)
	viewport.bind_actions(actions)
	var paint := Paint.new()
	paint.bind(integrated_selection, actions, integrated_host.undo())
	viewport.bind_paint(paint)
	integrated_selection.mode = Selection.Mode.VERTEX
	integrated_selection.set_ids(PackedInt64Array([integrated.call("get_vertices")[0]]))
	actions.run("snap_vertex")
	check(actions.snap_align_active and actions.snap_align_mode == Actions.SNAP_VERTEX, "shared viewport starts Snap to Vertex as a modal tool")
	paint.enter()
	check(paint.active and not actions.snap_align_active, "opening UV workspace cancels Snap to Vertex")
	integrated_selection.mode = Selection.Mode.FACE
	integrated_selection.set_ids(PackedInt64Array([integrated.call("get_faces")[0]]))
	actions.run("align_face")
	check(actions.snap_align_active and not paint.active, "starting Align Face closes UV workspace")
	integrated_selection.mode = Selection.Mode.OBJECT
	actions.run("plane_cut")
	check(not actions.snap_align_active and actions.plane_active, "changing to Object and starting Plane Cut leaves no Align Face modal")

	print("snap_align_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func _face_along(solid: Node3D, axis: Vector3) -> int:
	var best: int = 0
	var score := -2.0
	for face in PackedInt64Array(solid.call("get_faces")):
		var dot: float = (solid.call("face_normal", face) as Vector3).dot(axis)
		if dot > score:
			score = dot
			best = face
	return best
