@tool
extends HFlowContainer

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")

const FONT_SIZE := 15

var _selection: RefCounted
var _custom: HBoxContainer
var _metrics: RefCounted
var _isolate_solids: Button
var _isolate_faces: Button
var _soft_select: Button
var _soft_options: HBoxContainer
var _scene_root_getter: Callable
var _report: Callable

func setup(selection: RefCounted, metrics: RefCounted = null, scene_root_getter: Callable = Callable(),
		report: Callable = Callable()) -> void:
	_selection = selection
	_metrics = metrics if metrics != null else preload("res://addons/slab/slab_metrics.gd").at_scale(1.0)
	_scene_root_getter = scene_root_getter
	_report = report
	name = "SelectionControls"
	add_theme_constant_override("h_separation", 8)
	_choice("Pivot", ["Selection centre", "Active element", "Custom"], selection.pivot_mode,
		func(index: int) -> void:
			_selection.configure_pivot(index)
			_custom.visible = index == 2)
	_choice("Axes", ["World", "Object local", "Selected face"], selection.orientation,
		func(index: int) -> void: _selection.configure_orientation(index))
	var xray := CheckButton.new()
	xray.name = "XRaySelection"
	xray.text = "X-ray selection"
	xray.tooltip_text = "Off: pick visible elements. On: include occluded elements. Tab cycles candidates under the pointer."
	xray.button_pressed = selection.xray
	_style_text(xray)
	xray.toggled.connect(func(value: bool) -> void: _selection.set_xray(value))
	add_child(xray)
	var isolate_row := HBoxContainer.new()
	isolate_row.name = "IsolateSelection"
	isolate_row.add_theme_constant_override("separation", 2)
	add_child(isolate_row)
	var isolate_label := Label.new()
	isolate_label.name = "IsolateLabel"
	isolate_label.text = "Isolate"
	_style_text(isolate_label)
	isolate_row.add_child(isolate_label)
	_isolate_solids = _segment_button("IsolateSolids", "Solids",
		"Hide non-selected solids. Other solids leave the view. Toggle to exit.")
	_isolate_solids.button_pressed = selection.isolated
	_isolate_solids.pressed.connect(_on_isolate_solids_pressed)
	isolate_row.add_child(_isolate_solids)
	_isolate_faces = _segment_button("IsolateFaces", "Faces",
		"Hide unselected faces on the active solid. Other solids stay visible. Escape exits.")
	_isolate_faces.button_pressed = selection.face_isolated
	_isolate_faces.pressed.connect(_on_isolate_faces_pressed)
	isolate_row.add_child(_isolate_faces)
	_soft_select = Button.new()
	_soft_select.name = "SoftSelect"
	_soft_select.toggle_mode = true
	_soft_select.text = "Soft Select"
	_soft_select.button_pressed = selection.soft_select
	_soft_select.tooltip_text = "Apply a falloff influence to neighboring elements during transforms."
	_style_text(_soft_select)
	_soft_select.pressed.connect(_on_soft_select_pressed)
	add_child(_soft_select)
	_soft_options = HBoxContainer.new()
	_soft_options.name = "SoftSelectOptions"
	_soft_options.visible = selection.soft_select and selection.soft_select_allowed()
	add_child(_soft_options)
	var radius_label := Label.new()
	radius_label.text = "Radius"
	_style_text(radius_label)
	_soft_options.add_child(radius_label)
	var radius := SpinBox.new()
	radius.name = "SoftRadius"
	radius.min_value = 0.01
	radius.max_value = 100.0
	radius.step = 0.01
	radius.value = selection.soft_radius
	radius.custom_minimum_size.x = _metrics.px(72)
	radius.tooltip_text = "Falloff distance from the hard selection."
	_style_text(radius)
	_style_text(radius.get_line_edit())
	radius.value_changed.connect(func(value: float) -> void: _selection.set_soft_radius(value))
	_soft_options.add_child(radius)
	var falloff_label := Label.new()
	falloff_label.text = "Falloff"
	_style_text(falloff_label)
	_soft_options.add_child(falloff_label)
	var falloff := OptionButton.new()
	falloff.name = "SoftFalloff"
	falloff.add_item("Smooth")
	falloff.add_item("Linear")
	falloff.select(selection.soft_falloff)
	_style_text(falloff)
	falloff.item_selected.connect(func(index: int) -> void: _selection.set_soft_falloff(index))
	_soft_options.add_child(falloff)
	_custom = HBoxContainer.new()
	_custom.name = "CustomPivot"
	_custom.visible = selection.pivot_mode == 2
	add_child(_custom)
	var label := Label.new()
	label.text = "Pivot world XYZ"
	_style_text(label)
	_custom.add_child(label)
	for axis in 3:
		var field := SpinBox.new()
		field.name = "Pivot" + "XYZ"[axis]
		field.min_value = -1000000
		field.max_value = 1000000
		field.step = 0.001
		field.custom_minimum_size.x = _metrics.px(88)
		_style_text(field)
		_style_text(field.get_line_edit())
		field.value = selection.custom_pivot_world[axis]
		field.value_changed.connect(func(value: float) -> void:
			var point: Vector3 = _selection.custom_pivot_world
			point[axis] = value
			_selection.configure_pivot(2, point))
		_custom.add_child(field)
	_selection.changed.connect(_sync)
	_selection.settings_changed.connect(_sync)
	_sync()


func _sync() -> void:
	var axes: OptionButton = get_node("AxesChoice")
	axes.set_item_disabled(2, _selection.mode != 3 or _selection.ids.is_empty())
	axes.select(_selection.orientation)
	get_node("PivotChoice").select(_selection.pivot_mode)
	get_node("XRaySelection").set_pressed_no_signal(_selection.xray)
	_custom.visible = _selection.pivot_mode == 2
	for axis in 3:
		var field: SpinBox = _custom.get_node("Pivot" + "XYZ"[axis])
		if not is_equal_approx(field.value, _selection.custom_pivot_world[axis]):
			field.set_value_no_signal(_selection.custom_pivot_world[axis])
	_sync_isolate()
	_sync_soft_select()


func _sync_isolate() -> void:
	if _isolate_solids == null or _isolate_faces == null:
		return
	var empty: bool = _selection.objects.is_empty()
	_isolate_solids.set_pressed_no_signal(_selection.isolated)
	_isolate_solids.disabled = empty
	_isolate_solids.tooltip_text = "Hide non-selected solids. Other solids leave the view. Toggle to exit."
	_isolate_faces.set_pressed_no_signal(_selection.face_isolated)
	_isolate_faces.disabled = empty
	_isolate_faces.tooltip_text = _faces_tooltip()


func _faces_tooltip() -> String:
	if _selection.has_any_external_mesh():
		return SlabActions.PROMOTE_FIRST_TOOLTIP
	if _selection.face_isolated:
		return "Restore all faces. Escape exits Face isolation without clearing Soft Select."
	if _selection.mode != SlabSelection.Mode.FACE:
		return "Select faces in Face mode, then isolate them. Other solids stay visible."
	if _selection.ids.is_empty():
		return "Select faces, then isolate them. Unselected faces hide. Other solids stay visible."
	return "Hide unselected faces on the active solid. Other solids stay visible. Escape exits."


func _on_isolate_solids_pressed() -> void:
	var scene_root: Node = null
	if _scene_root_getter.is_valid():
		scene_root = _scene_root_getter.call()
	_selection.toggle_isolation(scene_root)
	_sync_isolate()


func _on_isolate_faces_pressed() -> void:
	var result: Dictionary = _selection.toggle_face_isolation()
	if _report.is_valid() and str(result.get("status", "")) != "":
		_report.call(str(result["status"]))
	_sync_isolate()


func _sync_soft_select() -> void:
	if _soft_select == null:
		return
	var allowed: bool = _selection.soft_select_allowed()
	_soft_select.disabled = not allowed
	_soft_select.tooltip_text = "Soft Select works in Vertex, Edge, or Face." if not allowed else "Apply a falloff influence to neighboring elements during transforms."
	_soft_select.set_pressed_no_signal(_selection.soft_select and allowed)
	_soft_options.visible = _selection.soft_select and allowed
	var radius: SpinBox = _soft_options.get_node("SoftRadius")
	if not is_equal_approx(radius.value, _selection.soft_radius):
		radius.set_value_no_signal(_selection.soft_radius)
	var falloff: OptionButton = _soft_options.get_node("SoftFalloff")
	falloff.select(_selection.soft_falloff)


func _on_soft_select_pressed() -> void:
	if not _selection.soft_select_allowed():
		_soft_select.set_pressed_no_signal(false)
		return
	_selection.set_soft_select(not _selection.soft_select)
	_sync_soft_select()

func _choice(label_text: String, choices: Array, selected: int, callback: Callable) -> void:
	var label := Label.new()
	label.text = label_text
	_style_text(label)
	add_child(label)
	var choice := OptionButton.new()
	choice.name = label_text + "Choice"
	_style_text(choice)
	for text in choices:
		choice.add_item(text)
	choice.select(selected)
	choice.item_selected.connect(callback)
	add_child(choice)


func _segment_button(node_name: String, text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.toggle_mode = true
	button.tooltip_text = tooltip
	_style_text(button)
	var active := StyleBoxFlat.new()
	active.bg_color = Color(0.86, 0.72, 0.34)
	active.set_corner_radius_all(3)
	active.content_margin_left = _metrics.px(8)
	active.content_margin_right = _metrics.px(8)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover_pressed", active)
	button.add_theme_color_override("font_pressed_color", Color(0.12, 0.1, 0.06))
	button.add_theme_color_override("font_hover_pressed_color", Color(0.12, 0.1, 0.06))
	return button


func _style_text(control: Control) -> void:
	control.add_theme_font_size_override("font_size", _metrics.font(FONT_SIZE))
