extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabExternalMesh := preload("res://addons/slab/slab_external_mesh.gd")
const SlabImportMesh := preload("res://addons/slab/slab_import_mesh.gd")
const SlabExportMesh := preload("res://addons/slab/slab_export_mesh.gd")
const SlabExportObj := preload("res://addons/slab/slab_export_obj.gd")
const SlabExportStl := preload("res://addons/slab/slab_export_stl.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")

var _fails := 0


func _init() -> void:
	_check_external_mesh_creation()
	_check_external_mesh_detection()
	_check_import_obj()
	_check_import_stl()
	_check_topology_disabled_for_external()
	_check_mode_strip_disabled_for_external()
	_check_export_external_mesh()
	_check_export_round_trip()
	_check_solid_ops_refuse_external()
	_check_promote_present()

	_finish()


func _check_external_mesh_creation() -> void:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var external := SlabExternalMesh.from_mesh(mesh, "test.obj")
	root.add_child(external)

	_expect(external != null, "external mesh created")
	_expect(SlabExternalMesh.is_external_mesh(external), "is_external_mesh returns true")
	_expect(SlabSelection.is_external_mesh(external), "SlabSelection.is_external_mesh returns true")
	_expect(not SlabSelection.is_solid(external), "is_solid returns false for external mesh")
	_expect(SlabSelection.is_slab_object(external), "is_slab_object returns true for external mesh")
	_expect(external.vertex_count() == 3, "vertex count is 3, got %d" % external.vertex_count())
	_expect(external.face_count() == 1, "face count is 1, got %d" % external.face_count())
	_expect(external.source_path() == "test.obj", "source path preserved")

	external.free()


func _check_external_mesh_detection() -> void:
	var selection := SlabSelection.new()

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var external := SlabExternalMesh.from_mesh(mesh, "")
	root.add_child(external)
	selection.set_objects([external])

	_expect(selection.has_only_external_meshes(), "has_only_external_meshes with one external")
	_expect(selection.has_any_external_mesh(), "has_any_external_mesh with one external")
	_expect(selection.first_external_mesh() == external, "first_external_mesh returns the external")

	var description := selection.describe()
	_expect("External mesh" in description, "describe() mentions External mesh, got: %s" % description)

	external.free()


func _check_import_obj() -> void:
	var obj_content := """
# Test OBJ
v 0.0 0.0 0.0
v 1.0 0.0 0.0
v 1.0 1.0 0.0
v 0.0 1.0 0.0
f 1 2 3
f 1 3 4
"""
	var path := "user://test_import.obj"
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "OBJ file created for writing")
	if file != null:
		file.store_string(obj_content)
		file.close()

	var result := SlabImportMesh.load_from_file(path)
	_expect(result.get("error", -1) == OK, "OBJ import succeeds")
	var imported: Node3D = result.get("mesh")
	_expect(imported != null, "OBJ import returns mesh node")
	if imported != null:
		_expect(SlabExternalMesh.is_external_mesh(imported), "imported OBJ is external mesh")
		_expect("External mesh" in str(result.get("status", "")), "status mentions External mesh")
		imported.free()

	DirAccess.remove_absolute(path)


func _check_import_stl() -> void:
	var stl_content := """solid test
facet normal 0 0 1
  outer loop
    vertex 0 0 0
    vertex 1 0 0
    vertex 0 1 0
  endloop
endfacet
endsolid test
"""
	var path := "user://test_import.stl"
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "STL file created for writing")
	if file != null:
		file.store_string(stl_content)
		file.close()

	var result := SlabImportMesh.load_from_file(path)
	_expect(result.get("error", -1) == OK, "ASCII STL import succeeds")
	var imported: Node3D = result.get("mesh")
	_expect(imported != null, "STL import returns mesh node")
	if imported != null:
		_expect(SlabExternalMesh.is_external_mesh(imported), "imported STL is external mesh")
		imported.free()

	DirAccess.remove_absolute(path)


func _check_topology_disabled_for_external() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var external := SlabExternalMesh.from_mesh(mesh, "")
	root.add_child(external)
	selection.set_objects([external])

	var topo_ops := ["boolean_union", "boolean_subtract", "plane_cut", "mirror_x", "center_pivot"]
	for op_id in topo_ops:
		var row := actions.find(op_id)
		if row.is_empty():
			continue
		var reason := actions.disabled_reason(row)
		_expect(reason != "", "%s is disabled for external mesh" % op_id)
		_expect(reason == SlabActions.PROMOTE_FIRST_TOOLTIP, "%s shows locked Promote-first tooltip, got: %s" % [op_id, reason])

	var export_row := actions.find("export_solids")
	_expect(not export_row.is_empty(), "export_solids row exists")
	var export_reason := actions.disabled_reason(export_row)
	_expect(export_reason == "", "export is enabled for external mesh, got: %s" % export_reason)

	var import_row := actions.find("import_mesh")
	_expect(not import_row.is_empty(), "import_mesh row exists")

	external.free()


func _check_mode_strip_disabled_for_external() -> void:
	var selection := SlabSelection.new()

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var external := SlabExternalMesh.from_mesh(mesh, "")
	root.add_child(external)
	selection.set_objects([external])

	var strip := SlabModeStrip.new()
	root.add_child(strip)
	strip.setup(selection, false, SlabMetrics.at_scale(1.0))
	strip.refresh()

	var vertex_button: Button = strip.get_node_or_null("SlabSelection.Mode.VERTEX") as Button
	if vertex_button == null:
		for child in strip.get_children():
			if child is Button and child.get_meta("slab_mode", -1) == SlabSelection.Mode.VERTEX:
				vertex_button = child
				break
	if vertex_button != null:
		_expect(vertex_button.disabled, "Vertex mode button is disabled for external mesh")
		_expect(vertex_button.tooltip_text == SlabActions.PROMOTE_FIRST_TOOLTIP, "Vertex button tooltip is locked copy, got: %s" % vertex_button.tooltip_text)

	strip.free()
	external.free()


func _check_export_external_mesh() -> void:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0.5, 1, 0),
		Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(1.5, 1, 0)
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var external := SlabExternalMesh.from_mesh(mesh, "")
	root.add_child(external)

	var export_mesh := SlabExportMesh.new()
	var err: int = export_mesh.bake([external])
	_expect(err == OK, "export bake succeeds for external mesh")
	_expect(export_mesh.vertex_count() == 6, "export has 6 vertices, got %d" % export_mesh.vertex_count())
	_expect(export_mesh.triangle_count() == 2, "export has 2 triangles, got %d" % export_mesh.triangle_count())
	_expect(export_mesh.solid_count == 1, "export reports 1 solid")

	var path := "user://test_external_export.obj"
	err = SlabExportObj.write(path, export_mesh)
	_expect(err == OK, "OBJ write succeeds for external mesh")

	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "exported OBJ opens")
	if file != null:
		var content := file.get_as_text()
		file.close()
		_expect("v " in content, "exported OBJ has vertex lines")
		_expect("f " in content, "exported OBJ has face lines")
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute("user://test_external_export.mtl")

	external.free()


func _check_export_round_trip() -> void:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0.5, 1, 0)
	])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var external := SlabExternalMesh.from_mesh(mesh, "")
	root.add_child(external)

	var export_mesh := SlabExportMesh.new()
	export_mesh.bake([external])

	var path := "user://round_trip.obj"
	SlabExportObj.write(path, export_mesh)

	var reimport := SlabImportMesh.load_from_file(path)
	_expect(reimport.get("error", -1) == OK, "round-trip reimport succeeds")
	var reimported: Node3D = reimport.get("mesh")
	_expect(reimported != null, "round-trip produces mesh")
	if reimported != null:
		var re_external := reimported as SlabExternalMesh
		_expect(re_external != null, "reimported is SlabExternalMesh")
		if re_external != null:
			_expect(re_external.vertex_count() == 3, "reimported has 3 vertices, got %d" % re_external.vertex_count())
			_expect(re_external.face_count() == 1, "reimported has 1 face, got %d" % re_external.face_count())
		reimported.free()

	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://round_trip.mtl")
	external.free()


func _check_solid_ops_refuse_external() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var external := SlabExternalMesh.from_mesh(mesh, "")
	root.add_child(external)
	selection.set_objects([external])

	var face_ops := ["extrude_faces", "inset_faces", "subdivide_faces"]
	for op_id in face_ops:
		var row := actions.find(op_id)
		if row.is_empty():
			continue
		var reason := actions.disabled_reason(row)
		_expect(reason != "", "%s is disabled for external mesh, reason: %s" % [op_id, reason])

	external.free()


func _check_promote_present() -> void:
	var actions := SlabActions.new(SlabSelection.new())
	var promote_row := actions.find("promote_to_solid")
	_expect(not promote_row.is_empty(), "promote_to_solid action exists")
	_expect(promote_row.get("label", "") == "Promote to Slab Solid…", "Promote label is locked")
	_expect("promote_to_solid" in SlabActions.EXTERNAL_MESH_ALLOWED_ACTIONS, "Promote is allowed on External meshes")


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
		print("external_mesh_smoke ok")
		quit(0)
