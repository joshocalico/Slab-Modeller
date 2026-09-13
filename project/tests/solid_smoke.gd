extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")

var _fails := 0
var _frames := 0


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

	var body: StaticBody3D = solid.get_node_or_null("__body")
	_expect(body != null, "solid owns a StaticBody3D")
	var shape_node: CollisionShape3D = null
	if body != null:
		shape_node = body.get_node_or_null("__shape")
	_expect(shape_node != null, "body owns a CollisionShape3D")
	_expect(solid.get("collision_enabled") == true, "collision is on by default")
	if shape_node != null:
		_expect(shape_node.shape is ConcavePolygonShape3D, "collision is a triangle soup")
		if shape_node.shape is ConcavePolygonShape3D:
			_expect(shape_node.shape.get_faces().size() >= 3, "soup has triangles")
		_expect(shape_node.disabled == false, "collider is enabled")
		var before_mesh: Mesh = null
		if mesh_node != null:
			before_mesh = mesh_node.mesh
		solid.set("collision_enabled", false)
		_expect(shape_node.disabled == true, "toggle disables the collider")
		_expect(mesh_node != null and mesh_node.mesh == before_mesh, "toggle does not replace the Mesh")
		solid.set("collision_enabled", true)
		_expect(shape_node.disabled == false, "re-enable restores the collider")
		_expect(mesh_node != null and mesh_node.mesh == before_mesh, "re-enable still keeps the Mesh")

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

	_check_arch()
	_check_shapes_stay_off_the_solid()
	_check_two_materials()
	_check_material_undo()
	_check_fallback_lighting()
	_check_signed_extrude_after_inset()


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_check_boolean_uses_node_transforms()
	_finish()
	return true


func _check_arch() -> void:
	var by_default: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(by_default)
	_expect(by_default.call("make_arch", 2, 2, 8, 0.25) == 0, "make_arch builds with the arc left to its default")
	var explicit: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(explicit)
	_expect(explicit.call("make_arch", 2, 2, 8, 0.25, PI) == 0, "make_arch builds at an explicit PI")
	_expect(by_default.get("data") == explicit.get("data"), "the default arc is PI, byte for byte")
	_expect(by_default.call("face_count") == 20, "an 8 segment arch has 20 faces")

	var band: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(band)
	_expect(band.call("make_arch", 4, 1, 8, 0.5, PI / 2.0) == 0, "a 90 degree arch builds")
	var bounds: AABB = band.call("get_local_aabb")
	_expect(absf(bounds.position.y) < 0.001, "the 90 degree arch sits on the floor, y origin %s" % bounds.position.y)
	_expect(absf(bounds.position.x) < 0.001, "the 90 degree arch starts at x zero, got %s" % bounds.position.x)
	_expect(bounds.size.x < 4.0, "a 90 degree arch is narrower than its span, got %s" % bounds.size.x)
	_expect(float(band.call("volume")) > 0.0, "the 90 degree arch has positive volume")
	_expect(band.get("data") != explicit.get("data"), "the arc changes the mesh")

	var ring: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(ring)
	_expect(ring.call("make_arch", 4, 1, 8, 0.5, TAU) == 0, "a 360 degree arch builds")
	_expect(ring.call("face_count") == 32, "an 8 segment full arch has 32 faces")
	_expect(float(ring.call("volume")) > 0.0, "the 360 degree arch has positive volume")

	_expect(band.call("make_arch", 2, 2, 8, 1.0) != 0, "thickness at half the span is refused")


func _check_shapes_stay_off_the_solid() -> void:
	var actions := SlabActions.new(SlabSelection.new())
	var shapes: RefCounted = actions.shapes
	var plan: Dictionary = shapes.plan(&"make_stair")
	var stair: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(stair)
	_expect(stair.callv(plan["method"], plan["args"]) == 0, "the stair plan builds a solid")
	var cap: int = _top_face(stair)
	_expect(stair.call("extrude_faces", PackedInt64Array([cap]), 0.5) == 0, "the stair takes an extrude")
	var edited: PackedByteArray = stair.get("data")

	shapes.set_value(&"stair_steps", 20.0)
	_expect(shapes.plan(&"make_stair")["args"][1] == 20, "the next stair plan reads 20 steps")
	_expect(stair.get("data") == edited, "changing the Steps field leaves the built solid alone")
	for prop in ["steps", "segments", "arc", "thickness", "sides", "size"]:
		_expect(not _has_property(stair, prop), "the solid stores no %s property" % prop)


func _check_two_materials() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	_expect(solid.call("make_box", Vector3(2, 3, 2)) == 0, "paint box builds")
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.55, 0.38, 0.22)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.82, 0.8, 0.74)
	var mats: Array = []
	mats.append(floor_mat)
	mats.append(wall_mat)
	solid.set("materials", mats)
	var top: int = _top_face(solid)
	_expect(solid.call("set_face_material", PackedInt64Array([top]), 1) == 0, "the cap takes material 1")
	_expect(solid.call("set_face_material", PackedInt64Array([top]), 400) == 0, "slot 400 is legal")
	var painted: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(painted)
	_expect(painted.call("make_box", Vector3(2, 3, 2)) == 0, "two-surface box builds")
	painted.set("materials", mats)
	_expect(painted.call("set_face_material", PackedInt64Array([_top_face(painted)]), 1) == 0, "paint one face")
	var mesh_node: MeshInstance3D = painted.get_node_or_null("Mesh")
	_expect(mesh_node != null and mesh_node.mesh != null, "painted solid still emits")
	if mesh_node != null and mesh_node.mesh != null:
		_expect(mesh_node.mesh.get_surface_count() == 2, "two used slots emit two surfaces, got %d" % mesh_node.mesh.get_surface_count())


func _check_material_undo() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	_expect(solid.call("make_box", Vector3(2, 2, 2)) == 0, "material undo box builds")
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	var undo := preload("res://tests/slab_test_undo.gd").new()
	var actions := SlabActions.new(selection, undo)
	var before_n: int = (solid.get("materials") as Array).size()
	actions.add_material()
	var after_n: int = (solid.get("materials") as Array).size()
	_expect(after_n == before_n + 1, "Add Material appends a slot, %d then %d" % [before_n, after_n])
	_expect(undo.actions.size() == 1, "Add Material records one undo action, got %d" % undo.actions.size())
	if undo.actions.is_empty():
		return
	_expect(undo.actions[0]["name"] == "Slab Add Material", "the action is named for materials")
	_expect(undo.actions[0]["execute"] == false, "the live array is already mutated")
	actions.add_material()
	_expect((solid.get("materials") as Array).size() == before_n + 2, "a second add appends another slot")
	_expect(actions.material_slot == before_n + 1, "the second add selects the new slot")
	undo.undo()
	_expect((solid.get("materials") as Array).size() == before_n + 1, "undo restores one added slot")
	_expect(actions.material_slot == before_n, "undo restores the previous slot")
	undo.redo()
	_expect((solid.get("materials") as Array).size() == before_n + 2, "redo restores both added slots")
	_expect(actions.material_slot == before_n + 1, "redo restores the new slot")


func _check_fallback_lighting() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	_expect(solid.call("make_box", Vector3(2, 2, 2)) == 0, "fallback box builds")
	var proto_color: Color = solid.get("prototype_color")
	var mesh_node: MeshInstance3D = solid.get_node_or_null("Mesh")
	_expect(mesh_node != null, "fallback box owns a Mesh child")
	if mesh_node == null:
		return
	var fallback: Material = mesh_node.get_surface_override_material(0)
	_expect(fallback is StandardMaterial3D, "empty slots use a StandardMaterial3D prototype")
	if fallback is StandardMaterial3D:
		_expect(fallback.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL,
			"the prototype is lit per-pixel, got %s" % fallback.shading_mode)
		_expect(absf(fallback.roughness - 0.7) < 0.001, "prototype roughness is 0.7, got %s" % fallback.roughness)
		_expect(fallback.albedo_color.is_equal_approx(proto_color),
			"prototype albedo keeps the graybox color, got %s" % fallback.albedo_color)
	solid.set("prototype_color", Color(0.2, 0.35, 0.55))
	var retinted: Material = mesh_node.get_surface_override_material(0)
	_expect(retinted == fallback, "rebuilding keeps one stable fallback material")
	_expect(retinted is StandardMaterial3D and (retinted as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL,
		"retinting the prototype keeps per-pixel lighting")
	_expect(retinted is StandardMaterial3D and (retinted as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.2, 0.35, 0.55)),
		"retinting still writes the prototype color")

	var custom := StandardMaterial3D.new()
	custom.albedo_color = Color(0.91, 0.22, 0.18)
	custom.roughness = 0.15
	custom.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	solid.set("materials", [custom])
	var applied: Material = mesh_node.get_surface_override_material(0)
	_expect(applied == custom, "a supplied material is the surface override, not a prototype copy")
	_expect(custom.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"a supplied unshaded material stays unshaded")
	_expect(absf(custom.roughness - 0.15) < 0.001, "supplied roughness is left alone, got %s" % custom.roughness)
	_expect(custom.albedo_color.is_equal_approx(Color(0.91, 0.22, 0.18)),
		"supplied albedo is left alone")


func _check_signed_extrude_after_inset() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	_expect(solid.call("make_box", Vector3(4, 3, 4)) == 0, "room box builds")
	var top: int = _top_face(solid)
	_expect(solid.call("inset_faces", PackedInt64Array([top]), 0.45) == 0, "room inset succeeds")
	var session := preload("res://addons/slab/slab_viewport.gd").new(preload("res://tests/slab_test_host.gd").over(root))
	var selection: RefCounted = session.state()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	var actions := SlabActions.new(selection)
	session.bind_actions(actions)
	var said: Array[String] = []
	actions.reported.connect(func(text: String) -> void: said.append(text))
	actions.extrude_amount = -1.0
	actions.run("extrude_faces")
	actions.operation_apply_requested.emit()
	_expect(said.is_empty() or not said[0].contains("failed"), "a signed inward extrude after inset commits, got %s" % [said])
	_expect(solid.call("face_count") > 10, "the room extrusion added faces, got %d" % solid.call("face_count"))
	var stabbed: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(stabbed)
	_expect(stabbed.call("make_box", Vector3(2, 3, 2)) == 0, "stab box builds")
	var cap: int = _top_face(stabbed)
	selection.set_objects([stabbed])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([cap]))
	actions.extrude_amount = -4.0
	said.clear()
	actions.run("extrude_faces")
	actions.operation_apply_requested.emit()
	_expect(not said.is_empty() and said[0].contains("cross another face") and said[0].contains("opposite wall"),
		"a numeric stab still refuses at commit with the embedding copy, got %s" % [said])


func _check_boolean_uses_node_transforms() -> void:
	var hall: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(hall)
	hall.name = "TurbineHall"
	_expect(hall.call("make_box", Vector3(12, 9, 14)) == 0, "hall box builds")
	var top: int = _top_face(hall)
	_expect(hall.call("inset_faces", PackedInt64Array([top]), 0.45) == 0, "hall inset")
	_expect(hall.call("extrude_faces", PackedInt64Array([top]), -8.55) == 0, "hall inward extrude")
	hall.position = Vector3(6.5, 0, -3.5)
	_expect(hall.call("face_count") == 14, "hollow hall has 14 faces, got %d" % hall.call("face_count"))
	var cutter: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(cutter)
	cutter.name = "Box"
	_expect(cutter.call("make_box", Vector3(1.6, 3, 2)) == 0, "door cutter builds")
	cutter.position = Vector3(6, 0.45, 2.5)
	var selection := SlabSelection.new()
	selection.set_objects([hall, cutter])
	_expect(selection.describe() == "2 solids selected.", "Hall then Box is two solids, got %s" % selection.describe())
	var actions := SlabActions.new(selection)
	_expect(actions.disabled_reason(actions.find("boolean_subtract")) == "", "Subtract is enabled for two solids")
	var said: Array[String] = []
	actions.reported.connect(func(text: String) -> void: said.append(text))
	var faces_before: int = hall.call("face_count")
	actions.run("boolean_subtract")
	_expect(not said.is_empty() and said[0].begins_with("Subtract applied."),
		"Subtract reports that it cut, got %s" % [said])
	_expect(hall.call("face_count") == 40,
		"the doorway adds faces with node transforms, got %d from %d" % [hall.call("face_count"), faces_before])
	_expect(cutter.is_inside_tree(), "Subtract retains the cutter solid")

	var left: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(left)
	left.name = "Left"
	left.call("make_box", Vector3(2, 2, 2))
	var right: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(right)
	right.name = "Right"
	right.call("make_box", Vector3(2, 2, 2))
	right.position.x = 1.0
	var left_before: PackedByteArray = left.get("data")
	var right_before: PackedByteArray = right.get("data")
	selection.set_objects([left, right])
	actions.swap_boolean_operands()
	actions.run("boolean_subtract")
	_expect(left.get("data") == left_before and right.get("data") != right_before,
		"swapped Subtract edits the displayed target and retains the displayed cutter")

	var host: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(host)
	_expect(host.call("make_box", Vector3(2, 2, 2)) == 0, "disjoint host builds")
	var far: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(far)
	_expect(far.call("make_box", Vector3(1, 1, 1)) == 0, "disjoint cutter builds")
	far.position = Vector3(80, 0, 80)
	selection.set_objects([host, far])
	said.clear()
	var disjoint_faces: int = host.call("face_count")
	actions.run("boolean_subtract")
	_expect(not said.is_empty() and said[0].contains("do not meet"),
		"disjoint Subtract is refused, got %s" % [said])
	_expect(host.call("face_count") == disjoint_faces, "disjoint Subtract leaves the host, got %d" % host.call("face_count"))


func _has_property(node: Object, prop: String) -> bool:
	for info in node.get_property_list():
		if info["name"] == prop:
			return true
	return false


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
