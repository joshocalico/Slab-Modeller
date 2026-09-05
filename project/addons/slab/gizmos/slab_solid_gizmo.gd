@tool
extends EditorNode3DGizmoPlugin

const SlabSelection := preload("res://addons/slab/slab_selection.gd")

const HOT := "hot"
const HOVER := "hover"
const FILL := "fill"
const FILL_HOVER := "fill_hover"
const WIRE := "wire"

var _selection: RefCounted


func _init() -> void:
	create_material(WIRE, Color(0.22, 0.24, 0.28, 0.85))
	create_material(HOT, Color(1.0, 0.62, 0.18))
	create_material(HOVER, Color(1.0, 0.82, 0.48, 0.9))
	create_material(FILL, Color(1.0, 0.62, 0.18, 0.42), false, true)
	create_material(FILL_HOVER, Color(1.0, 0.82, 0.48, 0.28), false, true)


func setup(selection: RefCounted) -> void:
	_selection = selection


func _get_gizmo_name() -> String:
	return "SlabSolid"


func _has_gizmo(for_node_3d: Node3D) -> bool:
	return SlabSelection.is_solid(for_node_3d)


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var solid := gizmo.get_node_3d()
	if solid == null or not solid.has_method("get_edges"):
		return
	var wire := PackedVector3Array()
	for edge in solid.get_edges():
		wire.append_array(solid.edge_endpoints(edge))
	if not wire.is_empty():
		gizmo.add_lines(wire, get_material(WIRE, gizmo), false)
	if _selection == null:
		return
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
	_draw_face_fill(gizmo, solid.face_corners(id), FILL_HOVER if hovered else FILL)
	gizmo.add_lines(_outline(solid.face_corners(id)), get_material(line_mat, gizmo), false)


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
