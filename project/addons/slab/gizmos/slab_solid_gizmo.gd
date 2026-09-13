@tool
extends EditorNode3DGizmoPlugin

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabXform := preload("res://addons/slab/slab_element_xform.gd")
const SlabSelectionFrame := preload("res://addons/slab/slab_selection_frame.gd")

const PREVIEW := "loop_preview"
const ARRAY_PREVIEW := "array_preview"
const ALIGN_PREVIEW := "align_preview"
const SNAP_ANCHOR := "snap_anchor"
const UV_SEAM := "uv_seam"
const OP_EXTRUDE := "operation_extrude"
const OP_INSET := "operation_inset"
const OP_BEVEL := "operation_bevel"
const REFUSED := "refused_edit"
const HOT := "hot"
const HOVER := "hover"
const FILL := "fill"
const FILL_HOVER := "fill_hover"
const PAINT_EDGE := "paint_edge"
const WIRE := "wire"
const WIRE_XRAY := "wire_xray"
const HOT_XRAY := "hot_xray"
const HOVER_XRAY := "hover_xray"
const SELECTION_SUBGIZMO := 0

var _selection: RefCounted
var _undo: Object
var _paint: RefCounted
var _rest_data := PackedByteArray()
var _rest_frame := Transform3D.IDENTITY


func _init() -> void:
	add_material(PREVIEW, overlay_material(Color(0.2, 0.95, 0.85), false, true))
	create_material(ARRAY_PREVIEW, Color(0.2, 0.95, 0.85, 0.28), false, true)
	create_material(ALIGN_PREVIEW, Color(0.25, 0.9, 1.0, 0.25), false, true)
	create_material(SNAP_ANCHOR, Color(0.25, 0.95, 1.0), false, true)
	create_material(UV_SEAM, Color(0.95, 0.2, 0.85), false, true)
	add_material(OP_EXTRUDE, overlay_material(Color(0.2, 0.95, 0.85), false, true))
	add_material(OP_INSET, overlay_material(Color(0.95, 0.72, 0.18), false, true))
	add_material(OP_BEVEL, overlay_material(Color(0.8, 0.45, 1.0), false, true))
	add_material(REFUSED, overlay_material(Color(1.0, 0.2, 0.3), false, true))
	create_material(WIRE, Color(0.22, 0.24, 0.28, 0.85))
	create_material(WIRE_XRAY, Color(0.22, 0.24, 0.28, 0.52), false, true)
	create_material(HOT, Color(1.0, 0.62, 0.18))
	create_material(HOT_XRAY, Color(1.0, 0.62, 0.18, 0.88), false, true)
	create_material(HOVER, Color(0.92, 0.97, 1.0, 1.0))
	create_material(HOVER_XRAY, Color(0.92, 0.97, 1.0, 0.82), false, true)
	add_material(FILL, overlay_material(Color(1.0, 0.62, 0.18, 0.14), true, false))
	add_material(FILL_HOVER, overlay_material(Color(0.92, 0.97, 1.0, 0.08), true, false))
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
	var solid: Node3D = gizmo.get_node_3d()
	if solid == null or _selection == null or _selection.solid != solid:
		return Transform3D.IDENTITY
	var frame := SlabSelectionFrame.from_selection(_selection)
	var result: Transform3D = frame.get("local", Transform3D.IDENTITY) if frame.get("valid", false) else Transform3D.IDENTITY
	return result


func _set_subgizmo_transform(gizmo: EditorNode3DGizmo, _subgizmo_id: int, xform: Transform3D) -> void:
	var solid: Node3D = gizmo.get_node_3d()
	if solid == null or _selection == null or _selection.ids.is_empty():
		return
	if _rest_data.is_empty():
		_rest_data = solid.get("data")
		var frame := SlabSelectionFrame.from_selection(_selection)
		if not frame.get("valid", false):
			_rest_data = PackedByteArray()
			return
		_rest_frame = frame["local"]
	solid.set("data", _rest_data)
	SlabXform.transform(solid, _selection.mode, _selection.ids, xform * _rest_frame.affine_inverse())


func _commit_subgizmos(gizmo: EditorNode3DGizmo, _ids: PackedInt32Array, _restores: Array, cancel: bool) -> void:
	var solid: Node3D = gizmo.get_node_3d()
	if solid == null:
		_rest_data = PackedByteArray()
		_rest_frame = Transform3D.IDENTITY
		return
	if cancel and not _rest_data.is_empty():
		solid.set("data", _rest_data)
	elif _undo != null and not _rest_data.is_empty():
		var after: PackedByteArray = solid.get("data")
		if after != _rest_data:
			_undo.create_action("Slab Transform Elements", UndoRedo.MERGE_DISABLE, solid)
			_undo.add_do_property(solid, "data", after)
			_undo.add_undo_property(solid, "data", _rest_data)
			_undo.commit_action(false)
	_rest_data = PackedByteArray()
	_rest_frame = Transform3D.IDENTITY


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var solid := gizmo.get_node_3d()
	if solid == null or not is_instance_valid(solid) or not solid.has_method("get_edges"):
		return
	var wire := PackedVector3Array()
	for edge in solid.get_edges():
		wire.append_array(solid.edge_endpoints(edge))
	if not wire.is_empty():
		gizmo.add_lines(wire, get_material(_line_material(WIRE), gizmo), false)
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
		_draw_operation_preview(gizmo, solid)
		return
	_draw_idle_elements(gizmo, solid, mode)
	if selected:
		for id in _selection.ids:
			_draw_element(gizmo, solid, mode, id, false)
	if hovered:
		_draw_element(gizmo, solid, mode, _selection.hover_id, true)
	# Keep operation handles above face fills, hover outlines, and selection wire.
	_draw_operation_preview(gizmo, solid)


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


func _draw_operation_preview(gizmo: EditorNode3DGizmo, solid: Node3D) -> void:
	var preview: Dictionary = _selection.operation_preview
	if preview.is_empty() or preview.get("solid") != solid:
		return
	var world_lines := operation_handle_lines(preview)
	var local_lines := PackedVector3Array()
	for point in world_lines:
		local_lines.append(solid.to_local(point))
	if not local_lines.is_empty():
		var kind := int(preview.get("kind", 0))
		var material := OP_EXTRUDE if kind == 0 else (OP_INSET if kind == 1 else OP_BEVEL)
		gizmo.add_lines(local_lines, get_material(material, gizmo), false)
	var result_lines: PackedVector3Array = preview.get("preview_lines", PackedVector3Array())
	if not result_lines.is_empty():
		gizmo.add_lines(result_lines, get_material(REFUSED if int(preview.get("error", OK)) != OK else PREVIEW, gizmo), false)


static func operation_handle_lines(preview: Dictionary) -> PackedVector3Array:
	var source: PackedVector3Array = preview.get("segments", PackedVector3Array())
	var out := PackedVector3Array(source)
	var anchor: Vector3 = preview.get("anchor", Vector3.ZERO)
	var tip: Vector3 = preview.get("tip", anchor)
	var axis: Vector3 = preview.get("axis", Vector3.UP).normalized()
	var side: Vector3 = preview.get("tangent", Vector3.ZERO)
	if side.length_squared() < 0.001 or absf(side.normalized().dot(axis)) > 0.98:
		side = axis.cross(Vector3.FORWARD)
	if side.length_squared() < 0.001:
		side = axis.cross(Vector3.RIGHT)
	side = (side - axis * side.dot(axis)).normalized()
	var size := maxf(0.16, anchor.distance_to(tip) * 0.2)
	match int(preview.get("kind", 0)):
		0:
			out.append_array(PackedVector3Array([tip, tip - axis * size + side * size * 0.55,
				tip, tip - axis * size - side * size * 0.55]))
		1:
			var start := source[0] if source.size() >= 2 else anchor - axis * size
			var finish := source[1] if source.size() >= 2 else tip
			var rail := side * size * 0.32
			out.append_array(PackedVector3Array([start - rail, finish - rail, start + rail, finish + rail,
				start - side * size, start + side * size, finish - side * size, finish + side * size]))
		2:
			var radius := maxf(size, absf(float(preview.get("amount", 0.0))))
			var previous := anchor + side * radius
			for i in range(1, 9):
				var angle := float(i) * PI * 0.5 / 8.0
				var point := anchor + (side * cos(angle) + axis * sin(angle)) * radius
				out.append_array(PackedVector3Array([previous, point]))
				previous = point
			for angle in [0.0, PI * 0.25, PI * 0.5]:
				var radial := side * cos(angle) + axis * sin(angle)
				out.append_array(PackedVector3Array([anchor + radial * (radius - size * 0.35),
					anchor + radial * (radius + size * 0.35)]))
	return out


static func operation_overlay_label(preview: Dictionary, camera: Camera3D) -> Dictionary:
	if preview.is_empty() or camera == null:
		return {}
	var point: Vector3 = preview.get("tip", preview.get("anchor", Vector3.ZERO))
	if camera.is_position_behind(point):
		return {}
	return { "text": str(preview.get("label", "")), "screen": camera.unproject_position(point) + Vector2(12, -12) }


# A single explicit material avoids Godot's selected/instanced variants replacing
# the tint or enabling an on-top pass with different transparency settings.
static func overlay_material(color: Color, transparent: bool, on_top: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	configure_overlay_material(material, transparent, on_top)
	return material


static func configure_overlay_material(material: StandardMaterial3D, transparent: bool, on_top: bool) -> void:
	if material == null:
		return
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = on_top
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if transparent else BaseMaterial3D.TRANSPARENCY_DISABLED


func _draw_idle_elements(gizmo: EditorNode3DGizmo, solid: Node3D, mode: int) -> void:
	if mode != SlabSelection.Mode.VERTEX:
		return
	var ticks := PackedVector3Array()
	for id in solid.get_vertices():
		ticks.append_array(_vertex_ticks(solid.vertex_position(id)))
	if not ticks.is_empty():
		gizmo.add_lines(ticks, get_material(_line_material(WIRE), gizmo), false)


func _draw_element(gizmo: EditorNode3DGizmo, solid: Node3D, mode: int, id: int, hovered: bool) -> void:
	if id == 0 and mode != SlabSelection.Mode.OBJECT:
		return
	var line_mat: String = _line_material(HOVER if hovered else HOT)
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


func _line_material(base: String) -> String:
	return line_material(base, _selection != null and bool(_selection.xray))


static func line_material(base: String, xray: bool) -> String:
	if not xray:
		return base
	if base == HOT:
		return HOT_XRAY
	if base == HOVER:
		return HOVER_XRAY
	return WIRE_XRAY if base == WIRE else base


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
	for i in face_fill_indices(corners):
		st.set_normal(normal)
		st.add_vertex(corners[i])
	gizmo.add_mesh(st.commit(), get_material(material_name, gizmo))


static func face_fill_indices(corners: PackedVector3Array) -> PackedInt32Array:
	if corners.size() < 3:
		return PackedInt32Array()
	var normal := Vector3.ZERO
	for i in corners.size():
		normal += corners[i].cross(corners[(i + 1) % corners.size()])
	if normal.length_squared() < 1e-12:
		return PackedInt32Array()
	var axis: int = normal.abs().max_axis_index()
	var polygon := PackedVector2Array()
	for point in corners:
		match axis:
			0: polygon.append(Vector2(point.y, point.z))
			1: polygon.append(Vector2(point.z, point.x))
			2: polygon.append(Vector2(point.x, point.y))
	return Geometry2D.triangulate_polygon(polygon)


func _vertex_ticks(point: Vector3) -> PackedVector3Array:
	var size := 0.035
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
