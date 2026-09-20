extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabExternalMesh := preload("res://addons/slab/slab_external_mesh.gd")
const SlabImportMesh := preload("res://addons/slab/slab_import_mesh.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")

var _fails := 0


func _init() -> void:
	if not _expect(ClassDB.class_exists("SlabSolid"), "SlabSolid is registered"):
		_finish()
		return
	_check_action_catalog()
	_check_import_never_promotes()
	_check_success_and_undo()
	_check_refuse_open()
	_check_refuse_empty()
	_check_refuse_non_manifold()
	_check_kernel_direct()
	_finish()


func _check_action_catalog() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var row := actions.find("promote_to_solid")
	_expect(not row.is_empty(), "promote_to_solid action exists")
	_expect(row.get("label", "") == SlabActions.PROMOTE_LABEL, "label is Promote to Slab Solid")
	_expect(SlabActions.PROMOTE_LABEL == "Promote to Slab Solid", "Promote label has no ellipsis")
	_expect(not str(row.get("label", "")).ends_with("…") and not str(row.get("label", "")).ends_with("..."), "Promote label has no trailing ellipsis")
	_expect(actions.find("import_mesh").get("label", "") == "Import Mesh...", "Import Mesh keeps its ellipsis")
	_expect(actions.find("export_solids").get("label", "") == "Export...", "Export keeps its ellipsis")
	_expect(actions.section_of(row) == "Object", "Promote sits in the Object section")
	_expect(row.get("min_count", 0) == 1, "Promote needs a selection")
	_expect(not actions.promote_visible(), "Promote is hidden with no selection")

	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	_expect(_button_for(panel, SlabActions.PROMOTE_LABEL) == null, "Promote is absent with no selection")
	_expect(_button_for(panel, "Import Mesh...") != null, "Import Mesh… stays visible with no selection")

	var reason := actions.disabled_reason(row)
	_expect(reason == "Select an External mesh to promote.", "Promote run is refused with no selection, got: %s" % reason)

	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3.ONE)
	selection.set_objects([solid])
	_expect(not actions.promote_visible(), "Promote is hidden on a SlabSolid")
	_expect(actions.disabled_reason(row) == "Select an External mesh to promote.", "Promote run is refused on a SlabSolid")
	_expect(_button_for(panel, SlabActions.PROMOTE_LABEL) == null, "Promote is absent on a SlabSolid")
	_expect(_button_for(panel, "Export...") != null, "Export… stays visible on a SlabSolid")

	var mesh: ArrayMesh = solid.call("build_mesh")
	var external := SlabExternalMesh.from_mesh(mesh, "box.obj")
	root.add_child(external)
	selection.set_objects([external])
	_expect(actions.promote_visible(), "Promote is visible on one External mesh")
	_expect(actions.disabled_reason(row) == "", "Promote is enabled on one External mesh")
	var button := _button_for(panel, SlabActions.PROMOTE_LABEL)
	_expect(button != null, "Promote to Slab Solid button exists for one External mesh")
	if button != null:
		_expect(button.text == "Promote to Slab Solid", "Promote button text has no ellipsis")
		_expect(not button.disabled, "Promote is enabled for one External mesh")
		_expect(not button.clip_text, "Promote button does not clip text")
	_expect(_button_for(panel, "Import Mesh...") != null, "Import Mesh… stays visible with an External selected")
	_expect(_button_for(panel, "Export...") != null, "Export… stays visible with an External selected")

	var extra := SlabExternalMesh.from_mesh(mesh, "box-b.obj")
	root.add_child(extra)
	selection.set_objects([external, extra])
	_expect(not actions.promote_visible(), "Promote is hidden for two External meshes")
	_expect(_button_for(panel, SlabActions.PROMOTE_LABEL) == null, "Promote is absent for two External meshes")

	panel.free()
	extra.free()
	external.free()
	solid.free()


func _check_import_never_promotes() -> void:
	var obj := """
v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
v 0 0 1
v 1 0 1
v 1 1 1
v 0 1 1
f 1 2 3 4
f 5 8 7 6
f 1 5 6 2
f 2 6 7 3
f 3 7 8 4
f 5 1 4 8
"""
	var path := "user://promote_import_box.obj"
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "import sample writes")
	if file == null:
		return
	file.store_string(obj)
	file.close()
	var result := SlabImportMesh.load_from_file(path)
	_expect(result.get("error", -1) == OK, "closed box OBJ still imports")
	var imported: Node3D = result.get("mesh")
	_expect(imported != null, "import returns a node")
	if imported != null:
		_expect(SlabExternalMesh.is_external_mesh(imported), "import stays External, never auto-promotes")
		_expect(not SlabSelection.is_solid(imported), "import is not a SlabSolid")
		_expect("External mesh" in str(result.get("status", "")), "import status stays External")
		imported.free()
	DirAccess.remove_absolute(path)


func _check_success_and_undo() -> void:
	var source: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(source)
	_expect(source.call("make_box", Vector3(2, 2, 2)) == 0, "source box builds")
	var mesh: ArrayMesh = source.call("build_mesh")
	_expect(mesh != null, "source box emits a mesh")
	var external := SlabExternalMesh.from_mesh(mesh, "box.obj")
	external.name = "RoofMesh"
	root.add_child(external)
	source.free()

	var selection := SlabSelection.new()
	selection.set_objects([external])
	_expect("(External mesh)" in selection.describe(), "idle badge names External mesh")

	var undo := SlabTestUndo.new()
	var actions := SlabActions.new(selection, undo)
	var row := actions.find("promote_to_solid")
	_expect(actions.disabled_reason(row) == "", "Promote enabled on one External mesh")

	var strip := SlabModeStrip.new()
	root.add_child(strip)
	strip.setup(selection, false, SlabMetrics.at_scale(1.0))
	var vertex_button := _mode_button(strip, SlabSelection.Mode.VERTEX)
	if vertex_button != null:
		_expect(vertex_button.disabled, "Vertex stays disabled before Promote")
		_expect(vertex_button.tooltip_text == SlabActions.PROMOTE_FIRST_TOOLTIP, "idle tooltip is locked copy, got: %s" % vertex_button.tooltip_text)

	var statuses: Array[String] = []
	actions.reported.connect(func(text: String) -> void: statuses.append(text))
	actions.run("promote_to_solid")

	_expect(statuses.size() == 1, "Promote reports one status")
	if not statuses.is_empty():
		_expect(statuses[0] == SlabActions.PROMOTE_SUCCESS, "success status is locked copy, got: %s" % statuses[0])

	var promoted: Node3D = selection.solid
	_expect(promoted != null and SlabSelection.is_solid(promoted), "selection is a SlabSolid after success")
	_expect(not SlabSelection.is_external_mesh(promoted), "promoted node is not External")
	_expect(is_instance_valid(promoted) and promoted.get_parent() == root, "promoted solid is in the scene")
	_expect(not is_instance_valid(external) or external.get_parent() == null, "External left the tree")
	_expect("(External mesh)" not in selection.describe(), "badge clears after success, got: %s" % selection.describe())
	_expect(int(promoted.call("face_count")) > 0, "promoted solid has faces")
	_expect(float(promoted.call("volume")) > 0.0, "promoted solid has volume")

	strip.refresh()
	if vertex_button != null:
		_expect(not vertex_button.disabled, "Vertex unlocks after Promote")

	var extrude := actions.find("extrude_faces")
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(promoted.call("get_faces"))
	_expect(actions.disabled_reason(extrude) == "", "topology tools unlock after Promote, got: %s" % actions.disabled_reason(extrude))
	selection.mode = SlabSelection.Mode.OBJECT

	undo.undo()
	_expect(is_instance_valid(external) and external.get_parent() == root, "Undo restores the External mesh")
	_expect(selection.solid == external, "Undo selects the External mesh")
	_expect(SlabExternalMesh.is_external_mesh(external), "restored node is still External")
	_expect("(External mesh)" in selection.describe(), "Undo restores the External badge")
	if is_instance_valid(promoted):
		_expect(promoted.get_parent() == null, "Undo removes the SlabSolid")

	strip.free()
	if is_instance_valid(external):
		external.free()
	if is_instance_valid(promoted) and promoted.get_parent() == null:
		promoted.free()


func _check_refuse_open() -> void:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var external := SlabExternalMesh.from_mesh(mesh, "open.obj")
	root.add_child(external)
	var before_id: int = external.get_instance_id()
	var before_faces: int = external.face_count()

	var selection := SlabSelection.new()
	selection.set_objects([external])
	var actions := SlabActions.new(selection)
	var statuses: Array[String] = []
	actions.reported.connect(func(text: String) -> void: statuses.append(text))
	actions.run("promote_to_solid")

	_expect(is_instance_valid(external) and external.get_parent() == root, "open refuse leaves External in the scene")
	_expect(external.get_instance_id() == before_id, "open refuse does not replace the node")
	_expect(external.face_count() == before_faces, "open refuse does not mutate the mesh")
	_expect(SlabExternalMesh.is_external_mesh(external), "open refuse stays External")
	_expect(not statuses.is_empty(), "open refuse reports status")
	if not statuses.is_empty():
		_expect("Could not promote" in statuses[0], "open refuse names promote")
		_expect("open" in statuses[0], "open refuse names open, got: %s" % statuses[0])
		_expect("unchanged" in statuses[0], "open refuse says unchanged")
		_expect("partial" not in statuses[0].to_lower(), "refuse never says partial convert")
	external.free()


func _check_refuse_empty() -> void:
	var external := SlabExternalMesh.from_mesh(ArrayMesh.new(), "")
	root.add_child(external)
	var selection := SlabSelection.new()
	selection.set_objects([external])
	var actions := SlabActions.new(selection)
	var statuses: Array[String] = []
	actions.reported.connect(func(text: String) -> void: statuses.append(text))
	actions.run("promote_to_solid")
	_expect(is_instance_valid(external) and SlabExternalMesh.is_external_mesh(external), "empty refuse leaves External")
	_expect(not statuses.is_empty() and "empty" in statuses[0], "empty refuse names empty, got: %s" % (statuses[0] if not statuses.is_empty() else ""))
	external.free()


func _check_refuse_non_manifold() -> void:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 1, 0),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 1, 3, 0, 1, 4])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var external := SlabExternalMesh.from_mesh(mesh, "fan.obj")
	root.add_child(external)
	var selection := SlabSelection.new()
	selection.set_objects([external])
	var actions := SlabActions.new(selection)
	var statuses: Array[String] = []
	actions.reported.connect(func(text: String) -> void: statuses.append(text))
	actions.run("promote_to_solid")
	_expect(is_instance_valid(external) and external.get_parent() == root, "non-manifold refuse leaves External")
	_expect(not statuses.is_empty() and "non-manifold" in statuses[0], "non-manifold refuse names the reason, got: %s" % (statuses[0] if not statuses.is_empty() else ""))
	external.free()


func _check_kernel_direct() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var mesh: ArrayMesh = solid.call("build_mesh")
	var flat := _flatten(mesh)
	var other: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(other)
	var imported: Dictionary = other.call("import_from_mesh", flat["vertices"], flat["indices"])
	_expect(int(imported.get("error", -1)) == 0, "import_from_mesh accepts a closed box")
	_expect(int(other.call("face_count")) > 0, "imported solid has faces")

	var open: Dictionary = other.call("import_from_mesh", PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP]), PackedInt32Array([0, 1, 2]))
	_expect(int(open.get("error", 0)) != 0, "import_from_mesh refuses an open triangle")
	_expect(str(open.get("refuse_reason", "")) == "open", "direct refuse reason is open")
	_expect(int(other.call("face_count")) > 0, "refused import_from_mesh leaves the previous solid intact")
	solid.free()
	other.free()


func _flatten(mesh: Mesh) -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	if mesh == null:
		return { "vertices": vertices, "indices": indices }
	for surface_idx in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_idx)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX else PackedVector3Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else PackedInt32Array()
		var base: int = vertices.size()
		vertices.append_array(verts)
		if idx.is_empty():
			for i in verts.size():
				indices.append(base + i)
		else:
			for i in idx:
				indices.append(base + i)
	return { "vertices": vertices, "indices": indices }


func _mode_button(strip: Node, mode: int) -> Button:
	for child in strip.get_children():
		if child is Button and int(child.get_meta("slab_mode", -1)) == mode:
			return child
	return null


func _button_for(node: Node, label: String) -> Button:
	if node is Button and (node as Button).text == label:
		return node
	for child in node.get_children():
		var found := _button_for(child, label)
		if found != null:
			return found
	return null


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
		print("promote_smoke ok")
		quit(0)
