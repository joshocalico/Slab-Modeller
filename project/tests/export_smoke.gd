extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabExportMesh := preload("res://addons/slab/slab_export_mesh.gd")
const SlabExportObj := preload("res://addons/slab/slab_export_obj.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")

var _fails := 0


func _init() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		_expect(false, "SlabSolid is registered")
		_finish()
		return

	_check_export_mesh_bake()
	_check_export_mesh_non_destructive()
	_check_empty_selection_refuses()
	_check_obj_produces_parseable_mesh()
	_check_export_chrome_exists()
	_check_obj_includes_uvs()
	_check_multi_solid_export()

	_finish()


func _check_export_mesh_bake() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	_expect(solid.call("make_box", Vector3(2, 3, 2)) == 0, "export box builds")

	var export_mesh := SlabExportMesh.new()
	var err: int = export_mesh.bake([solid])
	_expect(err == OK, "bake succeeds for valid solid")
	_expect(export_mesh.solid_count == 1, "bake reports one solid")
	_expect(export_mesh.vertex_count() > 0, "bake has vertices")
	_expect(export_mesh.triangle_count() > 0, "bake has triangles")
	_expect(export_mesh.has_normals(), "bake has normals")
	_expect(export_mesh.has_uvs(), "bake has uvs")
	_expect(not export_mesh.material_names.is_empty(), "bake has material names")

	solid.free()


func _check_export_mesh_non_destructive() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	_expect(solid.call("make_box", Vector3(2, 3, 2)) == 0, "non-destructive box builds")
	var before: PackedByteArray = solid.get("data")
	var face_count_before: int = solid.call("face_count")

	var export_mesh := SlabExportMesh.new()
	var err: int = export_mesh.bake([solid])
	_expect(err == OK, "bake succeeds")

	var after: PackedByteArray = solid.get("data")
	var face_count_after: int = solid.call("face_count")
	_expect(before == after, "bake does not modify solid data")
	_expect(face_count_before == face_count_after, "bake does not change face count")

	solid.free()


func _check_empty_selection_refuses() -> void:
	var export_mesh := SlabExportMesh.new()
	var err: int = export_mesh.bake([])
	_expect(err != OK, "bake refuses empty array")

	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var said: Array[String] = []
	actions.reported.connect(func(text: String) -> void: said.append(text))
	actions.run("export_solids")
	_expect(not said.is_empty() and said[0].contains("Select"), "empty selection reports refusal")


func _check_obj_produces_parseable_mesh() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	_expect(solid.call("make_box", Vector3(2, 3, 2)) == 0, "obj box builds")

	var export_mesh := SlabExportMesh.new()
	_expect(export_mesh.bake([solid]) == OK, "bake for obj succeeds")

	var path: String = "user://test_export.obj"
	var err: int = SlabExportObj.write(path, export_mesh)
	_expect(err == OK, "OBJ write succeeds")

	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "OBJ file opens")
	if file != null:
		var content: String = file.get_as_text()
		file.close()
		_expect(content.contains("v "), "OBJ has vertex lines")
		_expect(content.contains("f "), "OBJ has face lines")
		_expect(content.contains("mtllib"), "OBJ references material library")
		var vertex_count := 0
		var face_count := 0
		for line in content.split("\n"):
			if line.begins_with("v "):
				vertex_count += 1
			elif line.begins_with("f "):
				face_count += 1
		_expect(vertex_count == export_mesh.vertex_count(), "OBJ vertex count matches bake, got %d expected %d" % [vertex_count, export_mesh.vertex_count()])
		_expect(face_count == export_mesh.triangle_count(), "OBJ face count matches bake triangles, got %d expected %d" % [face_count, export_mesh.triangle_count()])

	var mtl_path: String = "user://test_export.mtl"
	var mtl_file := FileAccess.open(mtl_path, FileAccess.READ)
	_expect(mtl_file != null, "MTL file exists")
	if mtl_file != null:
		var mtl_content: String = mtl_file.get_as_text()
		mtl_file.close()
		_expect(mtl_content.contains("newmtl"), "MTL has material definitions")

	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(mtl_path)
	solid.free()


func _check_export_chrome_exists() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))

	var export_row := actions.find("export_solids")
	_expect(not export_row.is_empty(), "export_solids action exists")
	_expect(export_row.get("label", "") == "Export...", "export action label is Export...")
	_expect(export_row.get("tooltip", "").contains("Does not change the scene"), "export tooltip mentions non-destructive")

	var export_button: Button = _button_for(panel, "Export...")
	_expect(export_button != null, "Export... button exists in Object mode panel")
	if export_button != null:
		_expect(not export_button.clip_text, "Export... button does not clip text")

	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3.ONE)
	selection.set_objects([solid])
	var reason: String = actions.disabled_reason(export_row)
	_expect(reason == "", "export is enabled with a solid selected, got: %s" % reason)
	selection.set_objects([])
	reason = actions.disabled_reason(export_row)
	_expect(reason == "Select a solid to export.", "export disabled reason is canonical, got: %s" % reason)

	panel.free()
	solid.free()


func _check_obj_includes_uvs() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 3, 2))
	var top: int = _top_face(solid)
	solid.call("set_face_uv", PackedInt64Array([top]), Vector2(2, 2), Vector2(0.5, 0.25), 0.5)

	var export_mesh := SlabExportMesh.new()
	_expect(export_mesh.bake([solid]) == OK, "bake with UVs succeeds")
	_expect(export_mesh.has_uvs(), "bake captures UVs")

	var path: String = "user://test_uv_export.obj"
	var err: int = SlabExportObj.write(path, export_mesh)
	_expect(err == OK, "OBJ with UVs writes")

	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		var content: String = file.get_as_text()
		file.close()
		_expect(content.contains("vt "), "OBJ has texture coordinate lines")
		var uv_count := 0
		for line in content.split("\n"):
			if line.begins_with("vt "):
				uv_count += 1
		_expect(uv_count == export_mesh.vertex_count(), "OBJ UV count matches vertex count")
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute("user://test_uv_export.mtl")

	solid.free()


func _check_multi_solid_export() -> void:
	var solid_a: Node3D = ClassDB.instantiate("SlabSolid")
	var solid_b: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid_a)
	root.add_child(solid_b)
	solid_a.call("make_box", Vector3(2, 2, 2))
	solid_b.call("make_box", Vector3(1, 1, 1))
	solid_b.position = Vector3(5, 0, 0)

	var export_mesh := SlabExportMesh.new()
	var err: int = export_mesh.bake([solid_a, solid_b])
	_expect(err == OK, "multi-solid bake succeeds")
	_expect(export_mesh.solid_count == 2, "multi-solid bake reports two solids")

	var single_a := SlabExportMesh.new()
	single_a.bake([solid_a])
	var single_b := SlabExportMesh.new()
	single_b.bake([solid_b])
	_expect(export_mesh.vertex_count() == single_a.vertex_count() + single_b.vertex_count(),
		"combined vertex count equals sum of individuals")
	_expect(export_mesh.triangle_count() == single_a.triangle_count() + single_b.triangle_count(),
		"combined triangle count equals sum of individuals")

	solid_a.free()
	solid_b.free()


func _top_face(solid: Node3D) -> int:
	var best: int = 0
	var up := -2.0
	for id in PackedInt64Array(solid.call("get_faces")):
		var n: Vector3 = solid.call("face_normal", id)
		if n.y > up:
			up = n.y
			best = id
	return best


func _button_for(panel: Node, label: String) -> Button:
	for button in _buttons(panel):
		if String(button.get_meta("slab_label", "")) == label:
			return button
	return null


func _buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_buttons(child))
	return out


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
		print("export_smoke ok")
		quit(0)
