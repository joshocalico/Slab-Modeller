extends SceneTree

const Gizmo := preload("res://addons/slab/gizmos/slab_solid_gizmo.gd")

func _initialize() -> void:
	# L-shaped face with a collinear prefix. The authoritative normal remains usable
	# even though the first three corners cannot define it.
	var points := PackedVector3Array([
		Vector3(3, 0, 0), Vector3(3, 0, 0.5), Vector3(3, 0, 1), Vector3(1, 0, 1),
		Vector3(1, 0, 3), Vector3(0, 0, 3), Vector3(0, 0, 0)])
	var tilt := Basis.from_euler(Vector3(0.6, 0.0, 0.4))
	for i in points.size():
		points[i] = tilt * points[i]
	var normal := tilt * Vector3.DOWN
	var indices := Gizmo.face_fill_indices(points, normal)
	var area := 0.0
	var winding_matches := true
	for i in range(0, indices.size(), 3):
		var a := points[indices[i]]
		var b := points[indices[i + 1]]
		var c := points[indices[i + 2]]
		var triangle_normal := (b - a).cross(c - a)
		area += triangle_normal.length() * 0.5
		winding_matches = winding_matches and triangle_normal.dot(normal) < 0.0
	var passed := indices.size() == 15 and is_equal_approx(area, 5.0) and winding_matches
	points.reverse()
	indices = Gizmo.face_fill_indices(points, -normal)
	winding_matches = true
	for i in range(0, indices.size(), 3):
		var triangle_normal := (points[indices[i + 1]] - points[indices[i]]).cross(points[indices[i + 2]] - points[indices[i]])
		winding_matches = winding_matches and triangle_normal.dot(-normal) < 0.0
	passed = passed and indices.size() == 15 and winding_matches
	passed = passed and Gizmo.face_fill_indices(PackedVector3Array(), normal).is_empty()
	passed = passed and Gizmo.face_fill_indices(points, Vector3.ZERO).is_empty()
	var mesh := Gizmo.face_fill_mesh(points, -normal)
	var arrays := mesh.surface_get_arrays(0) if mesh != null else []
	var mesh_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if not arrays.is_empty() else PackedVector3Array()
	var mesh_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if not arrays.is_empty() else PackedVector3Array()
	passed = passed and mesh_vertices.size() == indices.size() and mesh_normals.size() == indices.size()
	for i in mesh_vertices.size():
		passed = passed and mesh_vertices[i].is_equal_approx(points[indices[i]] - normal * Gizmo.FACE_FILL_BIAS)
	for mesh_normal in mesh_normals:
		passed = passed and mesh_normal.is_equal_approx(-normal)
	passed = passed and Gizmo.face_fill_mesh(points, Vector3.ZERO) == null
	print("gizmo_fill_smoke: ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
