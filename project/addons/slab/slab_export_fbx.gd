@tool
extends RefCounted

const SlabExportMesh := preload("res://addons/slab/slab_export_mesh.gd")


static func write(path: String, export_mesh: SlabExportMesh) -> int:
	if export_mesh == null or export_mesh.vertex_count() == 0:
		return ERR_INVALID_PARAMETER
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	var model_name: String = path.get_file().get_basename()
	var geometry_id: int = 1000000
	var model_id: int = 2000000
	var material_ids: PackedInt64Array = PackedInt64Array()
	for i in export_mesh.material_names.size():
		material_ids.append(3000000 + i)

	_write_header(file)
	_write_global_settings(file)
	_write_documents(file)
	_write_definitions(file, export_mesh.material_names.size())
	_write_objects(file, export_mesh, model_name, geometry_id, model_id, material_ids)
	_write_connections(file, geometry_id, model_id, material_ids)

	file.close()
	return OK


static func _write_header(file: FileAccess) -> void:
	file.store_line("; FBX 7.4.0 project file")
	file.store_line("; Slab FBX Export (mesh, UVs, material names)")
	file.store_line("; ----------------------------------------------------")
	file.store_line("")
	file.store_line("FBXHeaderExtension:  {")
	file.store_line("\tFBXHeaderVersion: 1003")
	file.store_line("\tFBXVersion: 7400")
	file.store_line("\tCreator: \"Slab Modeller\"")
	file.store_line("}")
	file.store_line("")


static func _write_global_settings(file: FileAccess) -> void:
	file.store_line("GlobalSettings:  {")
	file.store_line("\tVersion: 1000")
	file.store_line("\tProperties70:  {")
	file.store_line("\t\tP: \"UpAxis\", \"int\", \"Integer\", \"\", 1")
	file.store_line("\t\tP: \"UpAxisSign\", \"int\", \"Integer\", \"\", 1")
	file.store_line("\t\tP: \"FrontAxis\", \"int\", \"Integer\", \"\", 2")
	file.store_line("\t\tP: \"FrontAxisSign\", \"int\", \"Integer\", \"\", 1")
	file.store_line("\t\tP: \"CoordAxis\", \"int\", \"Integer\", \"\", 0")
	file.store_line("\t\tP: \"CoordAxisSign\", \"int\", \"Integer\", \"\", 1")
	file.store_line("\t\tP: \"UnitScaleFactor\", \"double\", \"Number\", \"\", 1")
	file.store_line("\t}")
	file.store_line("}")
	file.store_line("")


static func _write_documents(file: FileAccess) -> void:
	file.store_line("Documents:  {")
	file.store_line("\tCount: 1")
	file.store_line("\tDocument: 100000000, \"\", \"Scene\" {")
	file.store_line("\t\tProperties70:  {")
	file.store_line("\t\t\tP: \"SourceObject\", \"object\", \"\", \"\"")
	file.store_line("\t\t\tP: \"ActiveAnimStackName\", \"KString\", \"\", \"\", \"\"")
	file.store_line("\t\t}")
	file.store_line("\t\tRootNode: 0")
	file.store_line("\t}")
	file.store_line("}")
	file.store_line("")


static func _write_definitions(file: FileAccess, material_count: int) -> void:
	var total: int = 3 + material_count
	file.store_line("Definitions:  {")
	file.store_line("\tVersion: 100")
	file.store_line("\tCount: %d" % total)
	file.store_line("\tObjectType: \"GlobalSettings\" {")
	file.store_line("\t\tCount: 1")
	file.store_line("\t}")
	file.store_line("\tObjectType: \"Geometry\" {")
	file.store_line("\t\tCount: 1")
	file.store_line("\t}")
	file.store_line("\tObjectType: \"Model\" {")
	file.store_line("\t\tCount: 1")
	file.store_line("\t}")
	if material_count > 0:
		file.store_line("\tObjectType: \"Material\" {")
		file.store_line("\t\tCount: %d" % material_count)
		file.store_line("\t}")
	file.store_line("}")
	file.store_line("")


static func _write_objects(
	file: FileAccess,
	export_mesh: SlabExportMesh,
	model_name: String,
	geometry_id: int,
	model_id: int,
	material_ids: PackedInt64Array
) -> void:
	file.store_line("Objects:  {")
	_write_geometry(file, export_mesh, model_name, geometry_id)
	_write_model(file, model_name, model_id)
	for i in export_mesh.material_names.size():
		_write_material(file, export_mesh.material_names[i], material_ids[i])
	file.store_line("}")
	file.store_line("")


static func _write_geometry(
	file: FileAccess,
	export_mesh: SlabExportMesh,
	name: String,
	geometry_id: int
) -> void:
	file.store_line("\tGeometry: %d, \"Geometry::%s\", \"Mesh\" {" % [geometry_id, name])

	file.store_string("\t\tVertices: *%d {\n\t\t\ta: " % [export_mesh.positions.size() * 3])
	var pos_parts: PackedStringArray = PackedStringArray()
	for pos in export_mesh.positions:
		pos_parts.append("%.6f,%.6f,%.6f" % [pos.x, pos.y, pos.z])
	file.store_line(",".join(pos_parts))
	file.store_line("\t\t}")

	var poly_indices: PackedInt32Array = PackedInt32Array()
	var tri_count: int = export_mesh.triangle_count()
	for tri_idx in tri_count:
		var i0: int = export_mesh.indices[tri_idx * 3]
		var i1: int = export_mesh.indices[tri_idx * 3 + 1]
		var i2: int = export_mesh.indices[tri_idx * 3 + 2]
		poly_indices.append(i0)
		poly_indices.append(i1)
		poly_indices.append(-(i2 + 1))

	file.store_string("\t\tPolygonVertexIndex: *%d {\n\t\t\ta: " % poly_indices.size())
	var idx_parts: PackedStringArray = PackedStringArray()
	for idx in poly_indices:
		idx_parts.append(str(idx))
	file.store_line(",".join(idx_parts))
	file.store_line("\t\t}")

	if export_mesh.has_normals():
		_write_layer_element_normal(file, export_mesh)

	if export_mesh.has_uvs():
		_write_layer_element_uv(file, export_mesh)

	if not export_mesh.material_per_triangle.is_empty():
		_write_layer_element_material(file, export_mesh)

	file.store_line("\t\tLayer: 0 {")
	file.store_line("\t\t\tVersion: 100")
	if export_mesh.has_normals():
		file.store_line("\t\t\tLayerElement:  {")
		file.store_line("\t\t\t\tType: \"LayerElementNormal\"")
		file.store_line("\t\t\t\tTypedIndex: 0")
		file.store_line("\t\t\t}")
	if export_mesh.has_uvs():
		file.store_line("\t\t\tLayerElement:  {")
		file.store_line("\t\t\t\tType: \"LayerElementUV\"")
		file.store_line("\t\t\t\tTypedIndex: 0")
		file.store_line("\t\t\t}")
	if not export_mesh.material_per_triangle.is_empty():
		file.store_line("\t\t\tLayerElement:  {")
		file.store_line("\t\t\t\tType: \"LayerElementMaterial\"")
		file.store_line("\t\t\t\tTypedIndex: 0")
		file.store_line("\t\t\t}")
	file.store_line("\t\t}")

	file.store_line("\t}")


static func _write_layer_element_normal(file: FileAccess, export_mesh: SlabExportMesh) -> void:
	file.store_line("\t\tLayerElementNormal: 0 {")
	file.store_line("\t\t\tVersion: 102")
	file.store_line("\t\t\tName: \"\"")
	file.store_line("\t\t\tMappingInformationType: \"ByVertice\"")
	file.store_line("\t\t\tReferenceInformationType: \"Direct\"")

	file.store_string("\t\t\tNormals: *%d {\n\t\t\t\ta: " % [export_mesh.normals.size() * 3])
	var n_parts: PackedStringArray = PackedStringArray()
	for n in export_mesh.normals:
		n_parts.append("%.6f,%.6f,%.6f" % [n.x, n.y, n.z])
	file.store_line(",".join(n_parts))
	file.store_line("\t\t\t}")

	file.store_line("\t\t}")


static func _write_layer_element_uv(file: FileAccess, export_mesh: SlabExportMesh) -> void:
	file.store_line("\t\tLayerElementUV: 0 {")
	file.store_line("\t\t\tVersion: 101")
	file.store_line("\t\t\tName: \"UVMap\"")
	file.store_line("\t\t\tMappingInformationType: \"ByVertice\"")
	file.store_line("\t\t\tReferenceInformationType: \"Direct\"")

	file.store_string("\t\t\tUV: *%d {\n\t\t\t\ta: " % [export_mesh.uvs.size() * 2])
	var uv_parts: PackedStringArray = PackedStringArray()
	for uv in export_mesh.uvs:
		uv_parts.append("%.6f,%.6f" % [uv.x, uv.y])
	file.store_line(",".join(uv_parts))
	file.store_line("\t\t\t}")

	file.store_line("\t\t}")


static func _write_layer_element_material(file: FileAccess, export_mesh: SlabExportMesh) -> void:
	file.store_line("\t\tLayerElementMaterial: 0 {")
	file.store_line("\t\t\tVersion: 101")
	file.store_line("\t\t\tName: \"\"")
	file.store_line("\t\t\tMappingInformationType: \"ByPolygon\"")
	file.store_line("\t\t\tReferenceInformationType: \"IndexToDirect\"")

	file.store_string("\t\t\tMaterials: *%d {\n\t\t\t\ta: " % export_mesh.material_per_triangle.size())
	var mat_parts: PackedStringArray = PackedStringArray()
	for m in export_mesh.material_per_triangle:
		mat_parts.append(str(m))
	file.store_line(",".join(mat_parts))
	file.store_line("\t\t\t}")

	file.store_line("\t\t}")


static func _write_model(file: FileAccess, name: String, model_id: int) -> void:
	file.store_line("\tModel: %d, \"Model::%s\", \"Mesh\" {" % [model_id, name])
	file.store_line("\t\tVersion: 232")
	file.store_line("\t\tProperties70:  {")
	file.store_line("\t\t\tP: \"DefaultAttributeIndex\", \"int\", \"Integer\", \"\", 0")
	file.store_line("\t\t}")
	file.store_line("\t\tShading: T")
	file.store_line("\t\tCulling: \"CullingOff\"")
	file.store_line("\t}")


static func _write_material(file: FileAccess, name: String, material_id: int) -> void:
	file.store_line("\tMaterial: %d, \"Material::%s\", \"\" {" % [material_id, name])
	file.store_line("\t\tVersion: 102")
	file.store_line("\t\tShadingModel: \"lambert\"")
	file.store_line("\t\tMultiLayer: 0")
	file.store_line("\t\tProperties70:  {")
	file.store_line("\t\t\tP: \"DiffuseColor\", \"Color\", \"\", \"A\", 0.8, 0.8, 0.8")
	file.store_line("\t\t\tP: \"AmbientColor\", \"Color\", \"\", \"A\", 0.2, 0.2, 0.2")
	file.store_line("\t\t\tP: \"Emissive\", \"Vector3D\", \"Vector\", \"\", 0, 0, 0")
	file.store_line("\t\t\tP: \"Ambient\", \"Vector3D\", \"Vector\", \"\", 0.2, 0.2, 0.2")
	file.store_line("\t\t\tP: \"Diffuse\", \"Vector3D\", \"Vector\", \"\", 0.8, 0.8, 0.8")
	file.store_line("\t\t\tP: \"Opacity\", \"double\", \"Number\", \"\", 1")
	file.store_line("\t\t}")
	file.store_line("\t}")


static func _write_connections(
	file: FileAccess,
	geometry_id: int,
	model_id: int,
	material_ids: PackedInt64Array
) -> void:
	file.store_line("Connections:  {")
	file.store_line("\tC: \"OO\", %d, 0" % model_id)
	file.store_line("\tC: \"OO\", %d, %d" % [geometry_id, model_id])
	for mat_id in material_ids:
		file.store_line("\tC: \"OO\", %d, %d" % [mat_id, model_id])
	file.store_line("}")
