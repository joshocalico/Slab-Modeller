@tool
extends EditorNode3DGizmoPlugin

const Sweep = preload("res://addons/slab/slab_sweep.gd")
var _undo: Object


func setup(undo: Object) -> void:
	_undo = undo


func _init() -> void:
	create_material("path", Color(0.95, 0.62, 0.2))
	create_material("mark", Color(0.15, 0.15, 0.16))
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "SlabSweep"


func _has_gizmo(for_node_3d: Node3D) -> bool:
	return for_node_3d.get_script() == Sweep


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var sweep := gizmo.get_node_3d() as SlabSweep
	if sweep == null or sweep.points.size() < 1:
		return
	var pts: PackedVector3Array = sweep.points
	if pts.size() >= 2:
		var lines := PackedVector3Array()
		for i in range(pts.size() - 1):
			lines.append(pts[i])
			lines.append(pts[i + 1])
		if sweep.closed and pts.size() > 2:
			lines.append(pts[pts.size() - 1])
			lines.append(pts[0])
		gizmo.add_lines(lines, get_material("path", gizmo), false)
	var handles := PackedVector3Array()
	var ids := PackedInt32Array()
	for i in pts.size():
		handles.append(pts[i])
		ids.append(i)
		var mark := 0.08
		gizmo.add_lines(PackedVector3Array([
			pts[i] + Vector3(-mark, 0.02, 0), pts[i] + Vector3(mark, 0.02, 0),
			pts[i] + Vector3(0, 0.02, -mark), pts[i] + Vector3(0, 0.02, mark),
		]), get_material("mark", gizmo), false)
	gizmo.add_handles(handles, get_material("handles", gizmo), ids)


func _get_handle_name(_gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	return "Path corner %s" % (handle_id + 1)


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var sweep := gizmo.get_node_3d() as SlabSweep
	if sweep == null or handle_id < 0 or handle_id >= sweep.points.size():
		return
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var normal := (sweep.global_transform.basis.inverse().transposed() * Vector3.UP).normalized()
	var plane := Plane(normal, sweep.to_global(sweep.points[handle_id]))
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return
	var local: Vector3 = sweep.to_local(hit)
	var pts := PackedVector3Array(sweep.points)
	pts[handle_id] = Vector3(snappedf(local.x, 0.5), pts[handle_id].y, snappedf(local.z, 0.5))
	sweep.points = pts


func _get_handle_value(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool) -> Variant:
	var sweep := gizmo.get_node_3d() as SlabSweep
	return PackedVector3Array(sweep.points) if sweep else PackedVector3Array()


func _commit_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var sweep := gizmo.get_node_3d() as SlabSweep
	if sweep == null:
		return
	if cancel:
		sweep.points = restore
		return
	var changed := PackedVector3Array(sweep.points)
	if changed == restore:
		return
	_undo.create_action("Move sweep path point")
	_undo.add_do_property(sweep, "points", changed)
	_undo.add_undo_property(sweep, "points", restore)
	_undo.commit_action(false)
