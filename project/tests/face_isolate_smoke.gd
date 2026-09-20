extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Controls := preload("res://addons/slab/slab_selection_controls.gd")
const SoftSelect := preload("res://addons/slab/slab_soft_select.gd")
const ElementXform := preload("res://addons/slab/slab_element_xform.gd")
const SlabExternalMesh := preload("res://addons/slab/slab_external_mesh.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_refuse_paths()
	_test_face_hide_and_restore()
	_test_other_solids_stay_visible()
	_test_independence_from_solid_isolate()
	_test_esc_preserves_soft_select()
	_test_soft_select_falloff_while_isolated()
	_test_external_unchanged()
	_test_chrome_segments()
	_test_preview_cancel_restores_mask()
	print("face_isolate_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("ok " if ok else "FAIL ", message)


func _top_face(solid: Node3D) -> int:
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9:
			return face
	return 0


func _index_count(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for i in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else PackedInt32Array()
		total += indices.size()
	return total


func _make_box(name: String, origin: Vector3 = Vector3.ZERO) -> Node3D:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.name = name
	solid.call("make_box", Vector3(2, 2, 2))
	solid.position = origin
	root.add_child(solid)
	return solid


func _test_refuse_paths() -> void:
	var selection := Selection.new()
	var reports: Array[String] = []
	selection.isolation_reported.connect(func(text: String) -> void: reports.append(text))
	var result: Dictionary = selection.enter_face_isolation()
	check(not bool(result.get("ok", true)), "refuse with no solid")
	check(result.get("status", "") == Selection.FACE_ISOLATE_NEED_SOLID, "status names missing solid")
	if not ClassDB.class_exists("SlabSolid"):
		return
	var solid := _make_box("RefuseBox")
	selection.set_objects([solid])
	result = selection.enter_face_isolation()
	check(not bool(result.get("ok", true)), "refuse in Object mode")
	check(result.get("status", "") == Selection.FACE_ISOLATE_NEED_FACE_MODE, "status names Face mode")
	selection.mode = Selection.Mode.FACE
	result = selection.enter_face_isolation()
	check(not bool(result.get("ok", true)), "refuse with no faces")
	check(result.get("status", "") == Selection.FACE_ISOLATE_NEED_FACES, "status names missing faces")
	check(not selection.face_isolated, "refuse leaves isolation off")
	check(not bool(solid.call("has_display_face_mask")), "refuse does not mask the solid")
	solid.free()


func _test_face_hide_and_restore() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		print("SlabSolid class not available; skipping hide tests")
		return
	var solid := _make_box("HideBox")
	var top: int = _top_face(solid)
	check(top != 0, "found top face")
	var data_before: PackedByteArray = solid.get("data")
	var committed_before: ArrayMesh = solid.call("build_mesh")
	var display: MeshInstance3D = solid.get_node("Mesh")
	var full_indices: int = _index_count(display.mesh)
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	var result: Dictionary = selection.enter_face_isolation()
	check(bool(result.get("ok", false)), "enter face isolation")
	check(selection.face_isolated, "face_isolated is true")
	check(result.get("status", "") == Selection.FACE_ISOLATE_ON, "enter status copy")
	check(bool(solid.call("has_display_face_mask")), "display face mask is set")
	check(bool(solid.call("is_display_face_visible", top)), "selected face stays visible")
	var hidden := 0
	for face in solid.call("get_faces"):
		if face != top and not bool(solid.call("is_display_face_visible", face)):
			hidden += 1
	check(hidden >= 5, "unselected faces are hidden from display")
	var masked_indices: int = _index_count(display.mesh)
	check(masked_indices > 0 and masked_indices < full_indices, "display mesh drops hidden faces")
	check(solid.get("data") == data_before, "face isolate does not mutate solid data")
	check(solid.call("build_mesh") == committed_before, "export mesh stays the committed resource")
	check(_index_count(solid.call("build_mesh")) == full_indices, "committed mesh keeps every face")
	result = selection.exit_face_isolation()
	check(not selection.face_isolated, "exit clears face_isolated")
	check(result.get("status", "") == Selection.FACE_ISOLATE_OFF, "exit status copy")
	check(not bool(solid.call("has_display_face_mask")), "display mask cleared")
	check(_index_count(display.mesh) == full_indices, "exit restores full face display")
	check(solid.get("data") == data_before, "exit leaves data unchanged")
	check(selection.ids == PackedInt64Array([top]), "exit keeps the face selection")
	solid.free()


func _test_other_solids_stay_visible() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		return
	var scene := Node3D.new()
	root.add_child(scene)
	var a: Node3D = ClassDB.instantiate("SlabSolid")
	a.name = "KeepA"
	a.call("make_box", Vector3.ONE)
	scene.add_child(a)
	var b: Node3D = ClassDB.instantiate("SlabSolid")
	b.name = "KeepB"
	b.call("make_box", Vector3.ONE)
	b.position.x = 4.0
	scene.add_child(b)
	var selection := Selection.new()
	selection.set_objects([a])
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([_top_face(a)]))
	selection.enter_face_isolation()
	check(a.visible and b.visible, "other solids stay visible during face isolation")
	check(not selection.isolated, "face isolate does not enter solid Isolate")
	selection.exit_face_isolation()
	scene.free()


func _test_independence_from_solid_isolate() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		return
	var scene := Node3D.new()
	root.add_child(scene)
	var a: Node3D = ClassDB.instantiate("SlabSolid")
	a.name = "BothA"
	a.call("make_box", Vector3.ONE)
	scene.add_child(a)
	var b: Node3D = ClassDB.instantiate("SlabSolid")
	b.name = "BothB"
	b.call("make_box", Vector3.ONE)
	b.position.x = 4.0
	scene.add_child(b)
	var selection := Selection.new()
	selection.set_objects([a])
	selection.enter_isolation(scene)
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([_top_face(a)]))
	selection.set_soft_select(true)
	selection.enter_face_isolation()
	check(selection.isolated and selection.face_isolated, "solid and face isolation coexist")
	check(a.visible and not b.visible, "solid Isolate still hides other solids")
	check(bool(a.call("has_display_face_mask")), "face mask applies while solid-isolated")
	selection.exit_face_isolation()
	check(not selection.face_isolated, "Esc/exit leaves Faces")
	check(selection.isolated, "exit Faces does not toggle solid Isolate")
	check(not b.visible, "other solids stay hidden after leaving Faces")
	check(selection.soft_select, "Soft Select stays on after leaving Faces")
	selection.exit_isolation()
	check(a.visible and b.visible, "solid Isolate exit restores other solids")
	scene.free()


func _test_esc_preserves_soft_select() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		return
	var solid := _make_box("EscBox")
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([_top_face(solid)]))
	selection.set_soft_select(true)
	selection.set_soft_radius(1.25)
	selection.enter_face_isolation()
	check(selection.soft_select, "Soft Select stays on while face-isolated")
	selection.exit_face_isolation()
	check(selection.soft_select, "exit Faces does not clear Soft Select")
	check(is_equal_approx(selection.soft_radius, 1.25), "Soft Select radius is preserved")
	check(selection.mode == Selection.Mode.FACE, "exit Faces keeps Face mode")
	check(not selection.ids.is_empty(), "exit Faces keeps the face selection")
	solid.free()


func _test_soft_select_falloff_while_isolated() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		return
	var solid := _make_box("FalloffBox")
	var top: int = _top_face(solid)
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	selection.set_soft_select(true)
	selection.set_soft_radius(2.5)
	selection.enter_face_isolation()
	var hard_verts: PackedInt64Array = ElementXform.vertices(solid, Selection.Mode.FACE, PackedInt64Array([top]))
	var neighbor_verts := PackedInt64Array()
	for face in solid.call("get_faces"):
		if face == top:
			continue
		for v in solid.call("face_vertices", face):
			if not hard_verts.has(v) and neighbor_verts.find(v) == -1:
				neighbor_verts.append(v)
	var weights: Dictionary = SoftSelect.compute_weights(solid, Selection.Mode.FACE,
		PackedInt64Array([top]), selection.soft_radius, selection.soft_falloff)
	check(not weights.is_empty(), "weights compute while face-isolated")
	var has_partial := false
	for v in neighbor_verts:
		if weights.has(v) and weights[v] > 0.0 and weights[v] < 1.0:
			has_partial = true
			break
	check(has_partial, "Soft Select falloff still reaches neighbors of hidden faces")
	var neighbor_before := Vector3.ZERO
	for v in neighbor_verts:
		neighbor_before += solid.vertex_position(v)
	neighbor_before /= float(neighbor_verts.size())
	var err: int = ElementXform.transform_weighted(solid, Transform3D.IDENTITY.translated(Vector3(0, 0.4, 0)), weights)
	check(err == OK, "weighted transform works while face-isolated")
	var neighbor_after := Vector3.ZERO
	for v in neighbor_verts:
		neighbor_after += solid.vertex_position(v)
	neighbor_after /= float(neighbor_verts.size())
	check(neighbor_after.y > neighbor_before.y, "neighbors still move under Soft Select while face-isolated")
	solid.free()


func _test_external_unchanged() -> void:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var external := SlabExternalMesh.from_mesh(mesh, "face-isolate.obj")
	root.add_child(external)
	var before_verts: int = external.vertex_count()
	var before_faces: int = external.face_count()
	var before_mesh: Mesh = external.mesh
	var selection := Selection.new()
	selection.set_objects([external])
	selection.mode = Selection.Mode.OBJECT
	var result: Dictionary = selection.enter_face_isolation()
	check(not bool(result.get("ok", true)), "External mesh refuses Face Isolate")
	check(result.get("status", "") == Selection.FACE_ISOLATE_EXTERNAL, "refuse copy names Promote first")
	check(selection.face_isolate_refuse_reason() == Selection.FACE_ISOLATE_EXTERNAL, "refuse reason is External")
	check(not selection.face_isolated, "External stay un-isolated")
	check(external.vertex_count() == before_verts, "External vertex count unchanged")
	check(external.face_count() == before_faces, "External face count unchanged")
	check(external.mesh == before_mesh, "External mesh resource unchanged")
	var controls := Controls.new()
	controls.setup(selection)
	root.add_child(controls)
	var faces_btn: Button = controls.get_node("IsolateSelection/IsolateFaces")
	check(faces_btn != null, "Faces segment exists for External")
	check(faces_btn.tooltip_text == SlabActions.PROMOTE_FIRST_TOOLTIP, "Faces tooltip is Promote first")
	controls.free()
	external.free()


func _test_chrome_segments() -> void:
	var selection := Selection.new()
	var controls := Controls.new()
	controls.setup(selection)
	root.add_child(controls)
	var row: HBoxContainer = controls.get_node("IsolateSelection")
	var solids_btn: Button = row.get_node("IsolateSolids")
	var faces_btn: Button = row.get_node("IsolateFaces")
	check(row != null and solids_btn != null and faces_btn != null, "Isolate is Solids | Faces, not two toolbars")
	check(solids_btn.text == "Solids" and faces_btn.text == "Faces", "segment labels are Solids and Faces")
	check(solids_btn.button_group == null and faces_btn.button_group == null,
		"Solids and Faces are independent toggles, not a radio group")
	if ClassDB.class_exists("SlabSolid"):
		var solid := _make_box("ChromeBox")
		selection.set_objects([solid])
		selection.mode = Selection.Mode.FACE
		selection.set_ids(PackedInt64Array([_top_face(solid)]))
		selection.settings_changed.emit()
		faces_btn.pressed.emit()
		check(selection.face_isolated, "Faces segment enters face isolation")
		check(faces_btn.button_pressed, "Faces segment shows pressed")
		faces_btn.pressed.emit()
		check(not selection.face_isolated, "Faces segment exits face isolation")
		solid.free()
	controls.free()


func _test_preview_cancel_restores_mask() -> void:
	if not ClassDB.class_exists("SlabSolid"):
		return
	var solid := _make_box("PreviewBox")
	var top: int = _top_face(solid)
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	selection.enter_face_isolation()
	var display: MeshInstance3D = solid.get_node("Mesh")
	var masked_indices: int = _index_count(display.mesh)
	var scratch: Node3D = ClassDB.instantiate("SlabSolid")
	scratch.set("data", solid.get("data"))
	check(scratch.call("extrude_faces", PackedInt64Array([top]), 0.4) == OK, "scratch extrude for preview")
	check(bool(solid.call("set_display_preview", scratch.get("data"))), "preview displays while face-isolated")
	check(_index_count(display.mesh) != masked_indices, "operation preview replaces the isolated display")
	solid.call("clear_display_preview")
	check(bool(solid.call("has_display_face_mask")), "mask remains after preview cancel")
	check(_index_count(display.mesh) == masked_indices, "cancel restores the isolated face display")
	selection.exit_face_isolation()
	scratch.free()
	solid.free()
