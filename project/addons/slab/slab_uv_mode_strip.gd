@tool
extends HBoxContainer

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")

const MODE_ICONS: Dictionary = {
	SlabSelection.UVMode.UV_VERT: "EditorHandle",
	SlabSelection.UVMode.UV_EDGE: "CurveEdit",
	SlabSelection.UVMode.UV_FACE: "MaterialPreviewCube",
}

const MODE_ORDER: Array = [
	SlabSelection.UVMode.UV_VERT,
	SlabSelection.UVMode.UV_EDGE,
	SlabSelection.UVMode.UV_FACE,
]

const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")

var _selection: RefCounted
var _metrics: RefCounted
var _buttons: Dictionary = {}
var active: bool = true:
	set(value):
		active = value
		refresh()


func setup(selection: RefCounted, metrics: RefCounted = null) -> void:
	_selection = selection
	_metrics = metrics if metrics != null else SlabMetrics.at_scale(1.0)
	add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for mode in MODE_ORDER:
		add_child(_make_button(mode, group))
	if _selection.has_signal("uv_mode_changed"):
		_selection.uv_mode_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for mode in _buttons:
		var button: Button = _buttons[mode]
		button.set_pressed_no_signal(active and mode == _selection.uv_mode)


func _make_button(mode: int, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.icon = SlabIcons.texture(MODE_ICONS[mode], _metrics.scale())
	button.add_theme_constant_override("icon_max_width", int(_metrics.px(16.0)))
	button.text = SlabSelection.UV_MODE_LABELS[mode]
	var lines := PackedStringArray()
	lines.append(SlabSelection.UV_MODE_LABELS[mode])
	lines.append(SlabSelection.UV_MODE_HINTS[mode])
	button.tooltip_text = "\n".join(lines)
	button.toggle_mode = true
	var active := StyleBoxFlat.new()
	active.bg_color = Color(0.86, 0.72, 0.34)
	active.set_corner_radius_all(3)
	active.content_margin_left = _metrics.px(6)
	active.content_margin_right = _metrics.px(6)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("hover_pressed", active)
	button.add_theme_color_override("font_pressed_color", Color(0.12, 0.1, 0.06))
	button.add_theme_color_override("font_hover_pressed_color", Color(0.12, 0.1, 0.06))
	button.add_theme_color_override("icon_pressed_color", Color(0.12, 0.1, 0.06))
	button.add_theme_color_override("icon_hover_pressed_color", Color(0.12, 0.1, 0.06))
	button.button_group = group
	button.focus_mode = Control.FOCUS_ALL
	button.accessibility_name = SlabSelection.UV_MODE_LABELS[mode] + " mode"
	button.accessibility_description = SlabSelection.UV_MODE_HINTS[mode]
	button.set_meta("slab_uv_mode", mode)
	button.custom_minimum_size = Vector2(_metrics.px(80.0), _metrics.px(28.0))
	button.add_theme_font_size_override("font_size", _metrics.font(13))
	button.pressed.connect(func() -> void: _selection.set_uv_mode(mode))
	_buttons[mode] = button
	return button
