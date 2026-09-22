extends SceneTree

const Bake = preload("res://addons/slab/slab_export_mesh.gd")
const Import = preload("res://addons/slab/slab_import_mesh.gd")
const Obj = preload("res://addons/slab/slab_export_obj.gd")
const Fbx = preload("res://addons/slab/slab_export_fbx.gd")
const Stl = preload("res://addons/slab/slab_export_stl.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var path := "user://exchange_indices.obj"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("v\t1 0 0\nv 0 1 0\nv 0 0 1\nf -3 -2 -1\n")
	file.close()
	var result := Import.load_from_file(path)
	check(result.error == OK, "negative/tab OBJ loads")
	if result.has("mesh"):
		var external = result.mesh
		check(external.mesh.get_aabb().size.is_equal_approx(Vector3.ONE), "negative OBJ indices preserve coordinates")
		var arrays: Array = external.mesh.surface_get_arrays(0)
		var p: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		check((p[ix[1]] - p[ix[0]]).cross(p[ix[2]] - p[ix[0]]).dot(n[ix[0]]) < 0, "OBJ converts CCW to Godot clockwise")
		external.free()
	DirAccess.remove_absolute(path)
	path = "user://exchange_truncated.stl"
	file = FileAccess.open(path, FileAccess.WRITE)
	var header := PackedByteArray()
	header.resize(80)
	file.store_buffer(header)
	file.store_32(2)
	file.store_float(1.0)
	file.close()
	result = Import.load_from_file(path)
	check(result.error != OK, "truncated STL refuses instead of importing partial geometry")
	if result.has("mesh"):
		result.mesh.free()
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("solid test\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\n")
	file.close()
	result = Import.load_from_file(path)
	check(result.error != OK, "truncated ASCII STL refuses")
	if result.has("mesh"):
		result.mesh.free()
	DirAccess.remove_absolute(path)
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 3, 4))
	var mats: Array[Material] = []
	for i in 3:
		var mat := StandardMaterial3D.new()
		mat.resource_name = "slot_%d" % i
		mats.append(mat)
	solid.set("materials", mats)
	solid.call("set_face_material", solid.call("get_faces"), 2)
	solid.position = Vector3(5, 6, 7)
	solid.call("set_face_uv", solid.call("get_faces"), Vector2.ZERO, Vector2(0.13, 0.27), 0.0)
	for reflected in [false, true]:
		solid.scale = Vector3(-2, 3, 0.5) if reflected else Vector3.ONE
		var baked := Bake.new()
		check(baked.bake([solid]) == OK, "box bakes")
		check(baked.material_names == PackedStringArray(["slot_2"]), "export uses face material slot, not surface ordinal")
		for t in baked.triangle_count():
			var a: int = baked.indices[t * 3]
			var b: int = baked.indices[t * 3 + 1]
			var c: int = baked.indices[t * 3 + 2]
			check((baked.positions[b] - baked.positions[a]).cross(baked.positions[c] - baked.positions[a]).dot(baked.normals[a]) > 0, "export winding is outward, reflected=%s" % reflected)
		if not reflected:
			Fbx.write("user://exchange_units.fbx", baked)
			Obj.write("user://exchange_units.obj", baked)
			Stl.write("user://exchange_units.stl", baked)
	solid.free()
	_check_fbx_roundtrip()
	_check_obj_polygons()
	_check_material_names()
	for extension in ["obj", "stl"]:
		var imported := Import.load_from_file("user://exchange_units." + extension)
		check(imported.error == OK, "%s roundtrip loads" % extension)
		if imported.has("mesh"):
			check(imported.mesh.mesh.get_aabb().get_center().is_equal_approx(Vector3(6, 7.5, 9)), "%s preserves world position: %s" % [extension, imported.mesh.mesh.get_aabb().get_center()])
			_check_mesh_winding(imported.mesh.mesh, extension)
			imported.mesh.free()
	for extension in ["obj", "mtl", "stl", "fbx"]:
		DirAccess.remove_absolute("user://exchange_units." + extension)
	print("Exchange regressions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_fbx_roundtrip() -> void:
	var document := FBXDocument.new()
	var state := FBXState.new()
	var error: int = document.append_from_file("user://exchange_units.fbx", state)
	check(error == OK, "Godot's independent FBX importer accepts export")
	if error != OK:
		return
	var imported: Node3D = document.generate_scene(state)
	root.add_child(imported)
	var bounds := AABB()
	var first := true
	for node in imported.find_children("*", "MeshInstance3D", true, false):
		_check_mesh_winding(node.mesh, "FBX")
		var box: AABB = node.global_transform * node.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for uv in arrays[Mesh.ARRAY_TEX_UV]:
				check(uv.is_equal_approx(Vector2(0.13, 0.27)), "FBX preserves UV orientation")
	check(not first and bounds.size.is_equal_approx(Vector3(2, 3, 4)), "FBX preserves dimensions in metres")
	check(bounds.get_center().is_equal_approx(Vector3(6, 7.5, 9)), "FBX preserves world position and axes: %s" % bounds.get_center())
	imported.free()


func _check_obj_polygons() -> void:
	# This concave face needs ear clipping; a fan from its first vertex overlaps.
	var path := "user://exchange_concave.obj"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("v 0 0 0\nv 3 0 0\nv 3 3 0\nv 2 3 0\nv 2 1 0\nv 1 1 0\nv 1 3 0\nv 0 3 0\nf 1 2 3 4 5 6 7 8 # notch\n")
	file.close()
	var result := Import.load_from_file(path)
	check(result.error == OK, "concave OBJ face imports")
	if result.has("mesh"):
		var arrays: Array = result.mesh.mesh.surface_get_arrays(0)
		var p: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var area := 0.0
		for i in range(0, ix.size(), 3):
			area += (p[ix[i + 1]] - p[ix[i]]).cross(p[ix[i + 2]] - p[ix[i]]).length() * 0.5
		check(is_equal_approx(area, 7.0), "concave triangulation preserves area without overlap")
		for normal in arrays[Mesh.ARRAY_NORMAL]:
			check(normal.z > 0.99, "concave OBJ preserves source front orientation")
		result.mesh.free()
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 99\n")
	file.close()
	result = Import.load_from_file(path)
	check(result.error != OK, "out-of-range OBJ index refuses")
	if result.has("mesh"):
		result.mesh.free()
	DirAccess.remove_absolute(path)


func _check_material_names() -> void:
	var nodes: Array[Node3D] = []
	for name in ["Paint-1", "Paint 1"]:
		var solid: Node3D = ClassDB.instantiate("SlabSolid")
		root.add_child(solid)
		solid.call("make_box", Vector3.ONE)
		var material := StandardMaterial3D.new()
		material.resource_name = name
		solid.set("materials", [material])
		nodes.append(solid)
	var baked := Bake.new()
	check(baked.bake(nodes) == OK, "distinct materials bake")
	check(baked.material_names == PackedStringArray(["Paint_1", "Paint_1_2"]), "distinct materials keep separate assignments after name sanitization")
	var external = preload("res://addons/slab/slab_external_mesh.gd").from_mesh(nodes[0].call("build_mesh"))
	root.add_child(external)
	var override_material := StandardMaterial3D.new()
	override_material.resource_name = "instance_override"
	external.material_override = override_material
	check(baked.bake([external]) == OK and baked.material_names == PackedStringArray(["instance_override"]), "External export uses the visible instance material")
	external.free()
	for node in nodes:
		node.free()


func _check_mesh_winding(mesh: Mesh, format: String) -> void:
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			var a: int = indices[i]
			var b: int = indices[i + 1]
			var c: int = indices[i + 2]
			check((positions[b] - positions[a]).cross(positions[c] - positions[a]).dot(normals[a]) < 0, "%s reimports with outward clockwise fronts" % format)
