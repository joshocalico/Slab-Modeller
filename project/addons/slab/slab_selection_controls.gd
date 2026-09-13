@tool
extends HFlowContainer

const FONT_SIZE := 15

var _selection: RefCounted
var _custom: HBoxContainer
var _metrics: RefCounted

func setup(selection: RefCounted, metrics: RefCounted = null) -> void:
	_selection = selection
	_metrics = metrics if metrics != null else preload("res://addons/slab/slab_metrics.gd").at_scale(1.0)
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


func _style_text(control: Control) -> void:
	control.add_theme_font_size_override("font_size", _metrics.font(FONT_SIZE))
