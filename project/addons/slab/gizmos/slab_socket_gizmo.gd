@tool
extends EditorNode3DGizmoPlugin


func _init() -> void:
	create_material("door", Color(0.95, 0.78, 0.22))
	create_material("sill", Color(0.2, 0.2, 0.22))


func _get_gizmo_name() -> String:
	return "SlabSocket"


func _has_gizmo(for_node_3d: Node3D) -> bool:
	return for_node_3d != null and for_node_3d.is_class("SlabSocket")


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var socket := gizmo.get_node_3d()
	if socket == null:
		return
	var hw: float = maxf(socket.opening.x, 0.2) * 0.5
	var h: float = maxf(socket.opening.y, 0.2)
	var z := 0.02
	var bl := Vector3(-hw, 0.0, z)
	var br := Vector3(hw, 0.0, z)
	var tr := Vector3(hw, h, z)
	var tl := Vector3(-hw, h, z)
	var frame := PackedVector3Array([bl, br, br, tr, tr, tl, tl, bl])
	var arch := PackedVector3Array([
		Vector3(-hw * 0.35, h * 0.45, z), Vector3(-hw * 0.15, h * 0.45, z),
		Vector3(-hw * 0.15, h * 0.45, z), Vector3(-hw * 0.15, h * 0.72, z),
	])
	gizmo.add_lines(frame, get_material("door", gizmo), false)
	gizmo.add_lines(arch, get_material("sill", gizmo), false)
