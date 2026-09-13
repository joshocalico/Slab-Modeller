extends SceneTree

const Gizmo := preload("res://addons/slab/gizmos/slab_solid_gizmo.gd")

func _initialize() -> void:
	# L-shaped face: a vertex-zero fan covers the missing upper-right square.
	var points := PackedVector3Array([
		Vector3(3, 0, 0), Vector3(3, 0, 1), Vector3(1, 0, 1),
		Vector3(1, 0, 3), Vector3(0, 0, 3), Vector3(0, 0, 0)])
	var indices := Gizmo.face_fill_indices(points)
	var area := 0.0
	for i in range(0, indices.size(), 3):
		var a := points[indices[i]]
		var b := points[indices[i + 1]]
		var c := points[indices[i + 2]]
		area += (b - a).cross(c - a).length() * 0.5
	var passed := indices.size() == 12 and is_equal_approx(area, 5.0)
	points.reverse()
	passed = passed and Gizmo.face_fill_indices(points).size() == 12
	passed = passed and Gizmo.face_fill_indices(PackedVector3Array()).is_empty()
	print("gizmo_fill_smoke: ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
