@tool
extends EditorNode3DGizmoPlugin

const SlabSelection := preload("res://addons/slab/slab_selection.gd")

const HOT := "hot"
const WIRE := "wire"
const HANDLES := "handles"

var _selection: RefCounted


func _init() -> void:
	create_material(WIRE, Color(0.13, 0.14, 0.17, 0.7))
	create_material(HOT, Color(1.0, 0.62, 0.18))
	create_handle_material(HANDLES)


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
	if _selection == null or _selection.solid != solid or _selection.ids.is_empty():
		return
	_draw_selection(gizmo, solid)


func _draw_selection(gizmo: EditorNode3DGizmo, solid: Node3D) -> void:
	var mode: int = _selection.mode
	if mode == SlabSelection.Mode.VERTEX:
		var points := PackedVector3Array()
		for id in _selection.ids:
			points.append(solid.vertex_position(id))
		gizmo.add_handles(points, get_material(HANDLES, gizmo), PackedInt32Array())
		return
	var lines := PackedVector3Array()
	for id in _selection.ids:
		if mode == SlabSelection.Mode.EDGE:
			lines.append_array(solid.edge_endpoints(id))
		else:
			lines.append_array(_outline(solid.face_corners(id)))
	if not lines.is_empty():
		gizmo.add_lines(lines, get_material(HOT, gizmo), false)


func _outline(corners: PackedVector3Array) -> PackedVector3Array:
	var lines := PackedVector3Array()
	for i in corners.size():
		lines.append(corners[i])
		lines.append(corners[(i + 1) % corners.size()])
	return lines
