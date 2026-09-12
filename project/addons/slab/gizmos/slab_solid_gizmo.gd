@tool
extends EditorNode3DGizmoPlugin

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabXform := preload("res://addons/slab/slab_element_xform.gd")

const PREVIEW := "loop_preview"
const ARRAY_PREVIEW := "array_preview"
const ALIGN_PREVIEW := "align_preview"
const SNAP_ANCHOR := "snap_anchor"
const UV_SEAM := "uv_seam"
const REFUSED := "refused_edit"
const HOT := "hot"
const HOVER := "hover"
const FILL := "fill"
const FILL_HOVER := "fill_hover"
const PAINT_EDGE := "paint_edge"
const WIRE := "wire"
const SELECTION_SUBGIZMO := 0

var _selection: RefCounted
var _undo: Object
var _paint: RefCounted
var _rest_data := PackedByteArray()
var _rest_origin := Vector3.ZERO


func _init() -> void:
	create_material(PREVIEW, Color(0.2, 0.95, 0.85), false, true)
	create_material(ARRAY_PREVIEW, Color(0.2, 0.95, 0.85, 0.28), false, true)
	create_material(ALIGN_PREVIEW, Color(0.25, 0.9, 1.0, 0.25), false, true)
	create_material(SNAP_ANCHOR, Color(0.25, 0.95, 1.0), false, true)
	create_material(UV_SEAM, Color(0.95, 0.2, 0.85), false, true)
	create_material(REFUSED, Color(1.0, 0.2, 0.3), false, true)
	create_material(WIRE, Color(0.22, 0.24, 0.28, 0.85))
	create_material(HOT, Color(1.0, 0.62, 0.18))
	create_material(HOVER, Color(1.0, 0.82, 0.48, 0.9))
	create_material(FILL, Color(1.0, 0.62, 0.18, 0.42), false, true)
	create_material(FILL_HOVER, Color(1.0, 0.82, 0.48, 0.28), false, true)
	create_material(PAINT_EDGE, Color(1.0, 0.88, 0.28, 1.0), false, true)


func setup(selection: RefCounted, undo: Object = null, paint: RefCounted = null) -> void:
	_selection = selection
	_undo = undo
	_paint = paint


func _get_gizmo_name() -> String:
	return "SlabSolid"


func _has_gizmo(for_node_3d: Node3D) -> bool:
	return SlabSelection.is_solid(for_node_3d)


func _subgizmos_intersect_ray(_gizmo: EditorNode3DGizmo, _camera: Camera3D, _screen_pos: Vector2) -> int:
	return -1


func _get_subgizmo_transform(gizmo: EditorNode3DGizmo, _subgizmo_id: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, _selection_origin(gizmo.get_node_3d()))


func _set_subgizmo_transform(gizmo: EditorNode3DGizmo, _subgizmo_id: int, xform: Transform3D) -> void:
	var solid: Node3D = gizmo.get_node_3d()
	if solid == null or _selection == null or _selection.ids.is_empty():
		return
	if _rest_data.is_empty():
		_rest_data = solid.get("data")
		_rest_origin = SlabXform.centroid(solid, _selection.mode, _selection.ids)
	solid.set("data", _rest_data)
	SlabXform.translate(solid, _selection.mode, _selection.ids, xform.origin - _rest_origin)


func _commit_subgizmos(gizmo: EditorNode3DGizmo, _ids: PackedInt32Array, _restores: Array, cancel: bool) -> void:
	var solid: Node3D = gizmo.get_node_3d()
	if solid == null:
		_rest_data = PackedByteArray()
		_rest_origin = Vector3.ZERO
		return
	if cancel and not _rest_data.is_empty():
		solid.set("data", _rest_data)
	elif _undo != null and not _rest_data.is_empty():
		var after: PackedByteArray = solid.get("data")
		if after != _rest_data:
			_undo.create_action("Slab Move Elements", UndoRedo.MERGE_DISABLE, solid)
			_undo.add_do_property(solid, "data", after)
			_undo.add_undo_property(solid, "data", _rest_data)
			_undo.commit_action(false)
	_rest_data = PackedByteArray()
	_rest_origin = Vector3.ZERO


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var solid := gizmo.get_node_3d()
	if solid == null or not is_instance_valid(solid) or not solid.has_method("get_edges"):
		return
	var wire := PackedVector3Array()
	for edge in solid.get_edges():
		wire.append_array(solid.edge_endpoints(edge))
	if not wire.is_empty():
		gizmo.add_lines(wire, get_material(WIRE, gizmo), false)
	var seams := PackedVector3Array()
	for edge in PackedInt64Array(solid.call("get_uv_seams")):
		seams.append_array(solid.call("edge_endpoints", edge))
	if not seams.is_empty():
		gizmo.add_lines(seams, get_material(UV_SEAM, gizmo), false)
	if _selection == null:
		return
	if _selection.objects.has(solid) and solid.has_method("get_edit_diagnostic"):
		var diagnostic: Dictionary = solid.get_edit_diagnostic()
		var refused_lines: PackedVector3Array = diagnostic.get("segments", PackedVector3Array())
		if not refused_lines.is_empty():
			gizmo.add_lines(refused_lines, get_material(REFUSED, gizmo), false)
	if _selection.preview_solid == solid and not _selection.preview_lines.is_empty():
		gizmo.add_lines(_selection.preview_lines, get_material(PREVIEW, gizmo), false)
	if _selection.array_preview_solid == solid and not _selection.array_preview_transforms.is_empty():
		var preview_mesh: ArrayMesh = solid.call("build_mesh")
		if preview_mesh != null:
			var parent_xform := Transform3D.IDENTITY
			if solid.get_parent() is Node3D:
				parent_xform = (solid.get_parent() as Node3D).global_transform
			for preview_transform in _selection.array_preview_transforms:
				var local_preview: Transform3D = solid.global_transform.affine_inverse() * parent_xform * preview_transform
				gizmo.add_mesh(preview_mesh, get_material(ARRAY_PREVIEW, gizmo), local_preview)
	_draw_snap_align_preview(gizmo, solid)
	var mode: int = _selection.mode
	var hovered: bool = _selection.hover_solid == solid
	var selected: bool = _selection.objects.has(solid)
	if mode == SlabSelection.Mode.OBJECT:
		if selected or hovered:
			_draw_element(gizmo, solid, mode, 0, hovered and not selected)
		return
	_draw_idle_elements(gizmo, solid, mode)
	if hovered:
		_draw_element(gizmo, solid, mode, _selection.hover_id, true)
	if selected:
		for id in _selection.ids:
			_draw_element(gizmo, solid, mode, id, false)


func _draw_snap_align_preview(gizmo: EditorNode3DGizmo, solid: Node3D) -> void:
	var preview: Dictionary = _selection.snap_align_preview
	if preview.is_empty() or preview.get("source") != solid:
		return
	var lines: PackedVector3Array = preview.get("lines", PackedVector3Array())
	if int(preview.get("mode", 0)) == 1 and lines.size() >= 2:
		var ticks := PackedVector3Array()
		ticks.append_array(_vertex_ticks(lines[0]))
		ticks.append_array(_vertex_ticks(lines[1]))
		gizmo.add_lines(ticks, get_material(SNAP_ANCHOR, gizmo), false)
		return
	if int(preview.get("mode", 0)) == 2:
		var preview_mesh: ArrayMesh = solid.call("build_mesh")
		if preview_mesh != null:
			var desired_global: Transform3D = preview.get("global_transform", solid.global_transform)
			var local_preview := solid.global_transform.affine_inverse() * desired_global
			gizmo.add_mesh(preview_mesh, get_material(ALIGN_PREVIEW, gizmo), local_preview)


func _draw_idle_elements(gizmo: EditorNode3DGizmo, solid: Node3D, mode: int) -> void:
	if mode != SlabSelection.Mode.VERTEX:
		return
	var ticks := PackedVector3Array()
	for id in solid.get_vertices():
		ticks.append_array(_vertex_ticks(solid.vertex_position(id)))
	if not ticks.is_empty():
		gizmo.add_lines(ticks, get_material(WIRE, gizmo), false)


func _draw_element(gizmo: EditorNode3DGizmo, solid: Node3D, mode: int, id: int, hovered: bool) -> void:
	if id == 0 and mode != SlabSelection.Mode.OBJECT:
		return
	var line_mat: String = HOVER if hovered else HOT
	if mode == SlabSelection.Mode.OBJECT:
		var wire := PackedVector3Array()
		for edge in solid.get_edges():
			wire.append_array(solid.edge_endpoints(edge))
		if not wire.is_empty():
			gizmo.add_lines(wire, get_material(line_mat, gizmo), false)
		return
	if mode == SlabSelection.Mode.VERTEX:
		gizmo.add_lines(_vertex_ticks(solid.vertex_position(id)), get_material(line_mat, gizmo), false)
		return
	if mode == SlabSelection.Mode.EDGE:
		gizmo.add_lines(solid.edge_endpoints(id), get_material(line_mat, gizmo), false)
		return
	if _paint_hides_albedo():
		gizmo.add_lines(_outline(solid.face_corners(id)), get_material(PAINT_EDGE, gizmo), false)
		return
	_draw_face_fill(gizmo, solid.face_corners(id), FILL_HOVER if hovered else FILL)
	gizmo.add_lines(_outline(solid.face_corners(id)), get_material(line_mat, gizmo), false)


func _paint_hides_albedo() -> bool:
	return _paint != null and bool(_paint.active)


func _draw_face_fill(gizmo: EditorNode3DGizmo, corners: PackedVector3Array, material_name: String) -> void:
	if corners.size() < 3:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0])
	if normal.length_squared() < 0.0001:
		normal = Vector3.UP
	else:
		normal = normal.normalized()
	for i in range(1, corners.size() - 1):
		st.set_normal(normal)
		st.add_vertex(corners[0])
		st.add_vertex(corners[i])
		st.add_vertex(corners[i + 1])
	gizmo.add_mesh(st.commit(), get_material(material_name, gizmo))


func _vertex_ticks(point: Vector3) -> PackedVector3Array:
	var size := 0.08
	return PackedVector3Array([
		point + Vector3(size, 0.0, 0.0), point - Vector3(size, 0.0, 0.0),
		point + Vector3(0.0, size, 0.0), point - Vector3(0.0, size, 0.0),
		point + Vector3(0.0, 0.0, size), point - Vector3(0.0, 0.0, size),
	])


func _outline(corners: PackedVector3Array) -> PackedVector3Array:
	var lines := PackedVector3Array()
	for i in corners.size():
		lines.append(corners[i])
		lines.append(corners[(i + 1) % corners.size()])
	return lines


func _selection_origin(solid: Node3D) -> Vector3:
	if solid == null or _selection == null or _selection.ids.is_empty():
		return Vector3.ZERO
	return SlabXform.centroid(solid, _selection.mode, _selection.ids)
