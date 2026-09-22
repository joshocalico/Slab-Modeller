@tool
extends MeshInstance3D
class_name SlabExternalMesh

signal topology_changed

@export_storage var _source_path: String = ""
var _is_manifold: bool = false
var _vertex_count: int = 0
var _face_count: int = 0

const EXTERNAL_MESH_CLASS := "SlabExternalMesh"


func _init() -> void:
	set_meta("slab_external_mesh", true)


func _ready() -> void:
	_update_stats()


static func is_external_mesh(node: Object) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node is SlabExternalMesh:
		return true
	if node is Node and node.has_meta("slab_external_mesh"):
		return true
	return false


func source_path() -> String:
	return _source_path


func set_source_path(path: String) -> void:
	_source_path = path


func is_manifold() -> bool:
	return _is_manifold


func vertex_count() -> int:
	return _vertex_count


func face_count() -> int:
	return _face_count


func description() -> String:
	var parts: PackedStringArray = []
	parts.append("External mesh")
	if _vertex_count > 0:
		parts.append("%d vertices" % _vertex_count)
	if _face_count > 0:
		parts.append("%d triangles" % _face_count)
	if not _is_manifold:
		parts.append("non-manifold")
	return ", ".join(parts)


func _update_stats() -> void:
	_vertex_count = 0
	_face_count = 0
	_is_manifold = false
	var m: Mesh = mesh
	if m == null:
		return
	for surface_idx in m.get_surface_count():
		var arrays: Array = m.surface_get_arrays(surface_idx)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX else PackedVector3Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else PackedInt32Array()
		_vertex_count += verts.size()
		if indices.is_empty():
			_face_count += verts.size() / 3
		else:
			_face_count += indices.size() / 3


func build_mesh() -> ArrayMesh:
	if mesh is ArrayMesh:
		return mesh as ArrayMesh
	if mesh == null:
		return null
	var array_mesh := ArrayMesh.new()
	for surface_idx in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_idx)
		if arrays.is_empty():
			continue
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: Material = mesh.surface_get_material(surface_idx)
		if mat != null:
			array_mesh.surface_set_material(surface_idx, mat)
	return array_mesh


func get_materials() -> Array:
	var mats: Array = []
	if mesh == null:
		return mats
	for surface_idx in mesh.get_surface_count():
		mats.append(get_active_material(surface_idx))
	return mats


static func from_mesh(m: Mesh, path: String = "") -> SlabExternalMesh:
	var node := SlabExternalMesh.new()
	node.mesh = m
	node._source_path = path
	node._update_stats()
	return node
