extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabPaint := preload("res://addons/slab/slab_paint.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")
const SlabUVModeStrip := preload("res://addons/slab/slab_uv_mode_strip.gd")
const SlabUVPick := preload("res://addons/slab/slab_uv_pick.gd")
const SlabPaintUv := preload("res://addons/slab/slab_paint_uv.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")

var _fails := 0
var _ran := 0


func case_uv_mode_enum_defines_all_modes() -> void:
	expect(SlabSelection.UVMode.UV_FACE == 0, "UV_FACE is the default mode value 0")
	expect(SlabSelection.UVMode.UV_EDGE == 1, "UV_EDGE is mode value 1")
	expect(SlabSelection.UVMode.UV_VERT == 2, "UV_VERT is mode value 2")
	expect(SlabSelection.UV_MODE_LABELS.size() == 3, "UV_MODE_LABELS has all three modes")
	expect(SlabSelection.UV_MODE_HINTS.size() == 3, "UV_MODE_HINTS has all three modes")


func case_uv_mode_switching_clears_selection() -> void:
	var selection := SlabSelection.new()
	expect(selection.uv_mode == SlabSelection.UVMode.UV_FACE, "default uv_mode is UV_FACE")
	selection.uv_selected_faces = PackedInt64Array([1, 2, 3])
	expect(selection.uv_selection_count() == 3, "face selection has 3 elements")
	selection.set_uv_mode(SlabSelection.UVMode.UV_EDGE)
	expect(selection.uv_mode == SlabSelection.UVMode.UV_EDGE, "uv_mode changed to UV_EDGE")
	expect(selection.uv_selection_count() == 0, "switching mode clears selection")
	selection.uv_selected_edges = PackedInt64Array([4, 5])
	expect(selection.uv_selection_count() == 2, "edge selection has 2 elements")
	selection.set_uv_mode(SlabSelection.UVMode.UV_VERT)
	expect(selection.uv_selection_count() == 0, "switching to vert mode clears edges")


func case_uv_selection_toggle_works() -> void:
	var selection := SlabSelection.new()
	selection.set_uv_mode(SlabSelection.UVMode.UV_FACE)
	selection.toggle_uv_element(5, false)
	expect(selection.get_uv_selection() == PackedInt64Array([5]), "first toggle sets the element")
	selection.toggle_uv_element(7, true)
	expect(selection.get_uv_selection().size() == 2, "additive toggle adds element")
	expect(selection.get_uv_selection().has(5) and selection.get_uv_selection().has(7), "both elements present")
	selection.toggle_uv_element(5, true)
	expect(selection.get_uv_selection() == PackedInt64Array([7]), "toggling existing removes it")
	selection.toggle_uv_element(3, false)
	expect(selection.get_uv_selection() == PackedInt64Array([3]), "non-additive replaces selection")


func case_uv_related_3d_faces_returns_correct_faces() -> void:
	var selection := SlabSelection.new()
	selection.set_uv_mode(SlabSelection.UVMode.UV_FACE)
	selection.set_uv_selection(PackedInt64Array([10, 20, 30]))
	var faces := selection.uv_related_3d_faces()
	expect(faces == PackedInt64Array([10, 20, 30]), "UV face mode returns face IDs directly")
	selection.set_uv_mode(SlabSelection.UVMode.UV_VERT)
	var vert_id := (15 << 16) | 2
	selection.set_uv_selection(PackedInt64Array([vert_id]))
	faces = selection.uv_related_3d_faces()
	expect(faces.size() == 1 and faces[0] == 15, "UV vert mode extracts face from encoded ID")
	selection.set_uv_mode(SlabSelection.UVMode.UV_EDGE)
	var edge_id := (25 << 16) | 1
	selection.set_uv_selection(PackedInt64Array([edge_id]))
	faces = selection.uv_related_3d_faces()
	expect(faces.size() == 1 and faces[0] == 25, "UV edge mode extracts face from encoded ID")


func case_uv_mode_strip_creates_three_buttons() -> void:
	var selection := SlabSelection.new()
	var strip := SlabUVModeStrip.new()
	strip.setup(selection, SlabMetrics.at_scale(1.0))
	var buttons: Array[Button] = []
	for child in strip.get_children():
		if child is Button:
			buttons.append(child)
	expect(buttons.size() == 3, "UV mode strip has three buttons")
	var labels := PackedStringArray()
	for button in buttons:
		labels.append(button.text)
	expect(labels.has("UV Vert"), "strip has UV Vert button")
	expect(labels.has("UV Edge"), "strip has UV Edge button")
	expect(labels.has("UV Face"), "strip has UV Face button")
	strip.free()


func case_uv_mode_strip_updates_on_mode_change() -> void:
	var selection := SlabSelection.new()
	var strip := SlabUVModeStrip.new()
	strip.setup(selection, SlabMetrics.at_scale(1.0))
	root.add_child(strip)
	var face_button: Button = null
	var edge_button: Button = null
	for child in strip.get_children():
		if child is Button:
			if child.text == "UV Face":
				face_button = child
			elif child.text == "UV Edge":
				edge_button = child
	expect(face_button != null and face_button.button_pressed, "UV Face starts pressed")
	expect(edge_button != null and not edge_button.button_pressed, "UV Edge starts unpressed")
	selection.set_uv_mode(SlabSelection.UVMode.UV_EDGE)
	expect(not face_button.button_pressed, "UV Face unpressed after mode change")
	expect(edge_button.button_pressed, "UV Edge pressed after mode change")
	strip.free()


func case_uv_mode_strip_visible_only_in_uv_workspace() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, SlabTestUndo.new())
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	panel.bind_paint(paint)
	root.add_child(panel)
	var strip: Control = panel.find_child("UVModeStrip", true, false)
	expect(strip != null, "UVModeStrip exists in panel")
	expect(not strip.visible, "UVModeStrip hidden outside UV workspace")
	paint.enter()
	await process_frame
	await process_frame
	expect(strip.visible, "UVModeStrip visible in UV workspace")
	paint.tool = SlabPaint.Tool.PIXEL
	panel.call("_on_paint_changed")
	await process_frame
	expect(not strip.visible, "UVModeStrip hidden in Paint workspace")
	paint.exit()
	await process_frame
	expect(not strip.visible, "UVModeStrip hidden after exiting workspace")
	panel.free()


func case_uv_pick_encoding_roundtrips() -> void:
	var vert_id := SlabUVPick._encode_uv_vert(1234, 3)
	var vert_decoded := SlabUVPick._decode_uv_vert(vert_id)
	expect(vert_decoded["face"] == 1234, "vert decode extracts face")
	expect(vert_decoded["corner"] == 3, "vert decode extracts corner")
	var edge_id := SlabUVPick._encode_uv_edge(5678, 2)
	var edge_decoded := SlabUVPick._decode_uv_edge(edge_id)
	expect(edge_decoded["face"] == 5678, "edge decode extracts face")
	expect(edge_decoded["edge_index"] == 2, "edge decode extracts edge_index")


func case_uv_pick_face_detects_point_in_polygon() -> void:
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		expect(false, "SlabSolid is built")
		return
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var faces := PackedInt64Array(solid.call("get_faces"))
	expect(faces.size() > 0, "box has faces")
	var face := faces[0]
	var uvs := SlabPaintUv.face_uvs(solid, face)
	expect(uvs.size() >= 3, "face has at least 3 UV coordinates")
	var centroid := Vector2.ZERO
	for uv in uvs:
		centroid += uv
	centroid /= uvs.size()
	var canvas_centroid := centroid * 100.0
	var uv_to_canvas := func(uv: Vector2) -> Vector2: return uv * 100.0
	var result := SlabUVPick.pick_uv_element(solid, faces, SlabSelection.UVMode.UV_FACE, canvas_centroid, uv_to_canvas)
	expect(not result.is_empty(), "pick at centroid finds a face")
	expect(result.get("type") == "face", "picked element is a face")
	solid.free()


func case_unwrap_pack_fit_workflow() -> void:
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		expect(false, "SlabSolid is built")
		return
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var faces := PackedInt64Array(solid.call("get_faces"))
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(faces)
	var undo := SlabTestUndo.new()
	var actions := SlabActions.new(selection, undo)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	panel.bind_paint(paint)
	root.add_child(panel)
	paint.enter()
	await process_frame
	await process_frame
	var unwrap: Button = panel.find_child("PaintUnwrap", true, false)
	expect(unwrap != null, "Unwrap button exists in UV workspace")
	var pack: Button = panel.find_child("PaintPack", true, false)
	expect(pack != null, "Pack button exists in UV workspace")
	expect(pack.visible, "Pack button visible in UV workspace")
	expect(pack.tooltip_text == "Repack islands without re-unwrapping.",
		"Pack tooltip is exactly the locked copy")
	var fit: Button = panel.find_child("PaintFitUv", true, false)
	expect(fit != null, "Fit UV button exists in UV workspace")
	expect(fit.visible, "Fit UV button visible in UV workspace")
	var reports: Array[String] = []
	actions.reported.connect(func(text: String) -> void: reports.append(text))
	actions.uv_pixels_per_meter = 64.0
	actions.uv_texture_resolution = 1024
	actions.run("uv_unwrap")
	expect(not reports.is_empty() and (reports[0].contains("Unwrapped") or reports[0].contains("island")),
		"Unwrap reports success, got %s" % [reports])
	for face in faces:
		var attrs: Dictionary = solid.call("face_uv", face)
		expect(bool(attrs.get("unwrapped", false)), "face %d is marked unwrapped after Unwrap" % face)
	var after_unwrap: PackedByteArray = solid.get("data")
	actions.uv_offset = Vector2(0.35, 0.35)
	actions.run("uv_apply")
	var after_offset: PackedByteArray = solid.get("data")
	expect(after_offset != after_unwrap, "Placement offset changes UV data")
	actions.run("uv_pack")
	expect(not reports.is_empty() and reports.back().begins_with("Packed "),
		"Pack reports success, got %s" % [reports.back() if not reports.is_empty() else ""])
	var after_pack: PackedByteArray = solid.get("data")
	expect(after_pack != after_offset, "Pack rearranges islands")
	solid.set("data", after_offset)
	actions.uv_pixels_per_meter = 128.0
	actions.uv_texture_resolution = 1024
	actions.run("uv_unwrap")
	expect(solid.get("data") != after_pack, "Unwrap at a new density is not Pack")
	var data_before_fit: PackedByteArray = solid.get("data")
	fit.pressed.emit()
	expect(solid.get("data") == data_before_fit, "Fit UV frames the canvas only")
	paint.tool = SlabPaint.Tool.PIXEL
	panel.call("_on_paint_changed")
	await process_frame
	expect(not pack.visible, "Paint workspace hides Pack")
	expect(not unwrap.visible, "Paint workspace hides Unwrap")
	var strip: Control = panel.find_child("UVModeStrip", true, false)
	expect(strip != null and not strip.visible, "Paint workspace hides the UV element strip")
	expect(paint.active, "workspace stays active after Pack")
	expect(panel.current_workspace() == SlabPanel.Workspace.PAINT, "switched to Paint after the hide check")
	panel.free()
	solid.free()


func case_fit_uv_frames_islands() -> void:
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		expect(false, "SlabSolid is built")
		return
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var faces := PackedInt64Array(solid.call("get_faces"))
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(faces)
	var undo := SlabTestUndo.new()
	var actions := SlabActions.new(selection, undo)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	panel.bind_paint(paint)
	root.add_child(panel)
	paint.enter()
	await process_frame
	await process_frame
	var canvas: Control = panel.find_child("PaintCanvas", true, false)
	expect(canvas != null, "PaintCanvas exists in UV workspace")
	actions.uv_pixels_per_meter = 64.0
	actions.uv_texture_resolution = 1024
	actions.run("uv_unwrap")
	await process_frame
	canvas.set("_uv_pixels_per_unit", 1.0)
	canvas.set("_uv_pan", Vector2(999.0, 999.0))
	canvas.set("_uv_center", Vector2(999.0, 999.0))
	var before_scale: float = canvas.get("_uv_pixels_per_unit")
	var before_pan: Vector2 = canvas.get("_uv_pan")
	expect(before_scale == 1.0, "pre-fit scale is 1.0 (forced baseline)")
	expect(before_pan == Vector2(999.0, 999.0), "pre-fit pan is (999, 999) (forced baseline)")
	var fit: Button = panel.find_child("PaintFitUv", true, false)
	expect(fit != null, "Fit UV button exists")
	fit.pressed.emit()
	await process_frame
	var after_scale: float = canvas.get("_uv_pixels_per_unit")
	var after_pan: Vector2 = canvas.get("_uv_pan")
	var after_center: Vector2 = canvas.get("_uv_center")
	expect(after_scale != before_scale, "Fit UV changes _uv_pixels_per_unit (was %s, now %s)" % [before_scale, after_scale])
	expect(after_pan != before_pan, "Fit UV changes _uv_pan (was %s, now %s)" % [before_pan, after_pan])
	expect(is_finite(after_scale) and after_scale > 0.0, "Fit UV scale is finite and positive: %s" % after_scale)
	expect(is_finite(after_center.x) and is_finite(after_center.y), "Fit UV center is finite: %s" % after_center)
	var loops: Array = paint.selected_uv_loops()
	expect(loops.size() > 0, "selected_uv_loops returns at least one loop after unwrap")
	var all_visible := true
	for loop: PackedVector2Array in loops:
		for uv: Vector2 in loop:
			var canvas_pt: Vector2 = canvas.call("_uv_to_canvas", uv)
			if not Rect2(Vector2.ZERO, canvas.size).grow(2.0).has_point(canvas_pt):
				all_visible = false
				break
		if not all_visible:
			break
	expect(all_visible, "Fit UV frames all UV loop corners inside canvas bounds")
	expect(paint.active, "UV workspace remains active after Fit UV")
	expect(panel.current_workspace() == SlabPanel.Workspace.UV, "still in UV workspace after Fit UV")
	panel.free()
	solid.free()


func case_3d_face_selection_frames_uv_canvas() -> void:
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		expect(false, "SlabSolid is built")
		return
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var faces := PackedInt64Array(solid.call("get_faces"))
	expect(faces.size() >= 2, "box has at least 2 faces for selection change test")
	var selection := SlabSelection.new()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([faces[0]]))
	var undo := SlabTestUndo.new()
	var actions := SlabActions.new(selection, undo)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, undo)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	panel.bind_paint(paint)
	root.add_child(panel)
	paint.enter()
	await process_frame
	await process_frame
	var canvas: Control = panel.find_child("PaintCanvas", true, false)
	expect(canvas != null, "PaintCanvas exists")
	canvas.set("_uv_pixels_per_unit", 1.0)
	canvas.set("_uv_pan", Vector2(999.0, 999.0))
	var before_scale: float = canvas.get("_uv_pixels_per_unit")
	var before_pan: Vector2 = canvas.get("_uv_pan")
	selection.set_ids(PackedInt64Array([faces[1]]))
	await process_frame
	await process_frame
	await process_frame
	var after_scale: float = canvas.get("_uv_pixels_per_unit")
	var after_pan: Vector2 = canvas.get("_uv_pan")
	var scale_changed: bool = not is_equal_approx(after_scale, before_scale)
	var pan_changed: bool = not after_pan.is_equal_approx(before_pan)
	expect(scale_changed or pan_changed, "3D face selection change triggers UV canvas reframe (scale %s->%s, pan %s->%s)" % [before_scale, after_scale, before_pan, after_pan])
	expect(paint.active, "UV workspace remains active after 3D face selection change")
	expect(panel.current_workspace() == SlabPanel.Workspace.UV, "still in UV workspace after 3D selection")
	panel.free()
	solid.free()


func case_paint_canvas_has_uv_element_mode_methods() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, SlabTestUndo.new())
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	panel.bind_paint(paint)
	root.add_child(panel)
	var canvas: Control = panel.find_child("PaintCanvas", true, false)
	expect(canvas != null, "PaintCanvas exists")
	expect(canvas.has_method("set_uv_element_mode"), "canvas has set_uv_element_mode method")
	expect(canvas.has_method("is_uv_element_mode"), "canvas has is_uv_element_mode method")
	expect(not canvas.is_uv_element_mode(), "UV element mode off by default")
	canvas.set_uv_element_mode(true)
	expect(canvas.is_uv_element_mode(), "UV element mode enabled after set")
	canvas.set_uv_element_mode(false)
	expect(not canvas.is_uv_element_mode(), "UV element mode disabled after set false")
	panel.free()


func case_box_select_uv_elements() -> void:
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		expect(false, "SlabSolid is built")
		return
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	root.add_child(solid)
	solid.call("make_box", Vector3(2, 2, 2))
	var faces := PackedInt64Array(solid.call("get_faces"))
	var large_rect := Rect2(Vector2(-1000, -1000), Vector2(2000, 2000))
	var uv_to_canvas := func(uv: Vector2) -> Vector2: return uv * 100.0
	var selected_faces := SlabUVPick.box_select_uv_elements(solid, faces, SlabSelection.UVMode.UV_FACE, large_rect, uv_to_canvas)
	expect(selected_faces.size() > 0, "box select finds faces in large rect")
	var selected_verts := SlabUVPick.box_select_uv_elements(solid, faces, SlabSelection.UVMode.UV_VERT, large_rect, uv_to_canvas)
	expect(selected_verts.size() > 0, "box select finds verts in large rect")
	var selected_edges := SlabUVPick.box_select_uv_elements(solid, faces, SlabSelection.UVMode.UV_EDGE, large_rect, uv_to_canvas)
	expect(selected_edges.size() > 0, "box select finds edges in large rect")
	var tiny_rect := Rect2(Vector2(-10000, -10000), Vector2(1, 1))
	var empty := SlabUVPick.box_select_uv_elements(solid, faces, SlabSelection.UVMode.UV_FACE, tiny_rect, uv_to_canvas)
	expect(empty.is_empty(), "box select returns empty for rect outside UVs")
	solid.free()


func case_uv_workspace_preserves_modelling_mode_on_exit() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var paint := SlabPaint.new()
	paint.bind(selection, actions, SlabTestUndo.new())
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	panel.bind_paint(paint)
	root.add_child(panel)
	selection.mode = SlabSelection.Mode.FACE
	expect(selection.mode == SlabSelection.Mode.FACE, "started in Face mode")
	paint.enter()
	await process_frame
	expect(panel.current_workspace() == SlabPanel.Workspace.UV, "entered UV workspace")
	paint.exit()
	await process_frame
	expect(panel.current_workspace() == SlabPanel.Workspace.MODELLING, "returned to modelling")
	expect(selection.mode == SlabSelection.Mode.FACE, "Face mode preserved after UV exit")
	panel.free()


func _init() -> void:
	call_deferred("_boot")


func _boot() -> void:
	await _run()


func _run() -> void:
	for case_name in _case_names():
		await Callable(self, case_name).call()
		_ran += 1
	if _fails != 0:
		push_error(str(_fails) + " failures")
		quit(1)
	else:
		print("uv_element_modes_smoke ok cases=%d" % _ran)
		quit(0)


func _case_names() -> PackedStringArray:
	var names := PackedStringArray()
	var filter: String = OS.get_environment("SLAB_CASE")
	for method in get_method_list():
		var method_name: String = method.name
		if not method_name.begins_with("case_"):
			continue
		if filter != "" and method_name != filter and method_name != "case_" + filter:
			continue
		names.append(method_name)
	return names


func expect(ok: bool, what: String) -> void:
	if ok:
		print("ok ", what)
		return
	push_error("FAIL " + what)
	print("FAIL ", what)
	_fails += 1
