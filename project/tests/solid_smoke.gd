extends SceneTree

var _fails := 0


func _init() -> void:
	if not _expect(ClassDB.class_exists("SlabSolid"), "SlabSolid is registered"):
		_finish()
		return

	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)

	_expect(solid.call("make_box", Vector3(2, 3, 2)) == 0, "make_box succeeds")
	_expect(solid.call("face_count") == 6, "box has 6 faces")
	_expect(solid.call("edge_count") == 12, "box has 12 edges")
	_expect(solid.call("vertex_count") == 8, "box has 8 vertices")
	_expect(absf(float(solid.call("volume")) - 12.0) < 0.01, "box volume is 12")

	var faces: PackedInt64Array = solid.call("get_faces")
	var edges: PackedInt64Array = solid.call("get_edges")
	var verts: PackedInt64Array = solid.call("get_vertices")
	_expect(faces.size() == 6, "get_faces returns 6 ids")
	_expect(edges.size() == 12, "get_edges returns 12 ids")
	_expect(verts.size() == 8, "get_vertices returns 8 ids")
	_expect(_all_unique(faces), "face ids are unique")
	_expect(_all_unique(edges), "edge ids are unique")

	for id in faces:
		_expect(solid.call("is_alive", id), "face id is alive")
		_expect(PackedVector3Array(solid.call("face_corners", id)).size() == 4, "box face has 4 corners")
		_expect(PackedInt64Array(solid.call("face_edges", id)).size() == 4, "box face has 4 edges")
		_expect(PackedInt64Array(solid.call("face_vertices", id)).size() == 4, "box face has 4 vertex ids")
	for id in edges:
		_expect(PackedVector3Array(solid.call("edge_endpoints", id)).size() == 2, "edge has 2 endpoints")
		_expect(PackedInt64Array(solid.call("edge_faces", id)).size() == 2, "edge borders 2 faces")
		_expect(PackedInt64Array(solid.call("edge_vertices", id)).size() == 2, "edge has 2 vertex ids")

	var top: int = _top_face(solid)
	_expect(top != 0, "found a top face")
	var centroid: Vector3 = solid.call("face_centroid", top)
	_expect(absf(centroid.y - 3.0) < 0.001, "top face centroid sits at y=3")

	_expect(solid.call("set_face_uv", PackedInt64Array([top]), Vector2(2, 2), Vector2(0.5, 0), 0.4) == 0, "set_face_uv succeeds")
	_expect(solid.call("extrude_faces", PackedInt64Array([top]), 1.0) == 0, "extrude_faces succeeds")
	_expect(solid.call("is_alive", top), "extrude keeps the cap id")
	_expect(solid.call("face_count") == 10, "extrude yields 10 faces")
	_expect(absf(float(solid.call("volume")) - 16.0) < 0.01, "extrude yields volume 16")
	var uv: Dictionary = solid.call("face_uv", top)
	_expect(absf(float(uv.get("scale", Vector2()).x) - 2.0) < 0.001, "uv scale survives extrude")
	_expect(absf(float(uv.get("rotation", 0.0)) - 0.4) < 0.001, "uv rotation survives extrude")

	var blob: PackedByteArray = solid.get("data")
	_expect(blob.size() > 0, "data serializes to bytes")

	var clone: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(clone)
	clone.set("data", blob)
	_expect(clone.call("face_count") == 10, "data round-trip keeps face count")
	_expect(absf(float(clone.call("volume")) - 16.0) < 0.01, "data round-trip keeps volume")
	_expect(clone.call("is_alive", top), "data round-trip keeps ids resolvable")
	var uv_reload: Dictionary = clone.call("face_uv", top)
	_expect(absf(float(uv_reload.get("scale", Vector2()).x) - 2.0) < 0.001, "uv scale survives reload")
	_expect(absf(float(uv_reload.get("rotation", 0.0)) - 0.4) < 0.001, "uv rotation survives reload")

	var junk := PackedByteArray()
	junk.resize(24)
	var wrecked: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(wrecked)
	wrecked.set("data", junk)
	_expect(wrecked.call("face_count") == 0, "a corrupt blob leaves the solid empty")

	var mesh_node: MeshInstance3D = solid.get_node_or_null("Mesh")
	_expect(mesh_node != null, "solid owns a Mesh child")
	if mesh_node != null:
		_expect(mesh_node.mesh != null, "solid emits an ArrayMesh")
		if mesh_node.mesh != null:
			_expect(mesh_node.mesh.get_surface_count() >= 1, "emitted mesh has a surface")

	_expect(solid.call("inset_faces", PackedInt64Array([top]), 0.25) == 0, "inset_faces succeeds")
	_expect(solid.call("is_alive", top), "inset keeps the center face id")

	var stale := PackedInt64Array([9123456789])
	_expect(solid.call("extrude_faces", stale, 1.0) != 0, "a stale id is rejected, not crashed on")

	var mover: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(mover)
	_expect(mover.call("make_box", Vector3(2, 2, 2)) == 0, "move probe box is built")
	var cap: int = _top_face(mover)
	var cap_verts: PackedInt64Array = mover.call("face_vertices", cap)
	var before_y: float = mover.call("face_centroid", cap).y
	_expect(mover.call("move_vertices", cap_verts, Vector3(0, 1, 0)) == 0, "move_vertices lifts the cap")
	_expect(absf(float(mover.call("face_centroid", cap).y) - (before_y + 1.0)) < 0.01, "a face move is a vertex delta")

	_finish()


func _top_face(solid: Node3D) -> int:
	var best: int = 0
	var up := -2.0
	for id in PackedInt64Array(solid.call("get_faces")):
		var n: Vector3 = solid.call("face_normal", id)
		if n.y > up:
			up = n.y
			best = id
	return best


func _all_unique(ids: PackedInt64Array) -> bool:
	var seen := {}
	for id in ids:
		if seen.has(id):
			return false
		seen[id] = true
	return true


func _expect(ok: bool, what: String) -> bool:
	if not ok:
		push_error("FAIL " + what)
		_fails += 1
	else:
		print("ok ", what)
	return ok


func _finish() -> void:
	if _fails != 0:
		push_error(str(_fails) + " failures")
		quit(1)
	else:
		print("solid_smoke ok")
		quit(0)
