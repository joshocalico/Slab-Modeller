@tool
extends HBoxContainer

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")

const MODE_ICONS: Dictionary = {
	SlabSelection.Mode.OBJECT: "MeshInstance3D",
	SlabSelection.Mode.VERTEX: "EditorHandle",
	SlabSelection.Mode.EDGE: "CurveEdit",
	SlabSelection.Mode.FACE: "MaterialPreviewCube",
}

const MODE_KEYS: Dictionary = {
	SlabSelection.Mode.OBJECT: KEY_1,
	SlabSelection.Mode.VERTEX: KEY_2,
	SlabSelection.Mode.EDGE: KEY_3,
	SlabSelection.Mode.FACE: KEY_4,
}

const MODE_HINTS: Dictionary = {
	SlabSelection.Mode.OBJECT: "Select whole solids. Create and combine them.",
	SlabSelection.Mode.VERTEX: "Select corners. Weld, collapse and connect them.",
	SlabSelection.Mode.EDGE: "Select edges. Bevel, connect and insert loops.",
	SlabSelection.Mode.FACE: "Select faces. Extrude, inset and texture them.",
}

const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")

var _selection: RefCounted
var _metrics: RefCounted
var _buttons: Dictionary = {}


static func keycode_for(mode: int) -> int:
	return MODE_KEYS.get(mode, 0)


static func mode_for_keycode(keycode: int) -> int:
	for mode in MODE_KEYS:
		if MODE_KEYS[mode] == keycode:
			return mode
	return -1


func setup(selection: RefCounted, with_labels: bool, metrics: RefCounted = null) -> void:
	_selection = selection
	_metrics = metrics if metrics != null else SlabMetrics.at_scale(1.0)
	add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for mode in SlabSelection.MODE_LABELS:
		add_child(_make_button(mode, group, with_labels))
	_selection.changed.connect(refresh)
	refresh()


func refresh() -> void:
	for mode in _buttons:
		var button: Button = _buttons[mode]
		button.set_pressed_no_signal(mode == _selection.mode)


func _make_button(mode: int, group: ButtonGroup, with_label: bool) -> Button:
	var button := Button.new()
	button.icon = SlabIcons.texture(MODE_ICONS[mode], _metrics.scale())
	button.text = SlabSelection.MODE_LABELS[mode] if with_label else ""
	var lines := PackedStringArray()
	if not with_label:
		lines.append(SlabSelection.MODE_LABELS[mode])
	lines.append(MODE_HINTS[mode])
	lines.append("Shortcut %s." % OS.get_keycode_string(MODE_KEYS[mode]))
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
	button.accessibility_name = SlabSelection.MODE_LABELS[mode] + " mode"
	button.accessibility_description = MODE_HINTS[mode]
	button.set_meta("slab_mode", mode)
	button.custom_minimum_size = Vector2(_metrics.px(100.0 if with_label else 40.0), _metrics.px(36.0))
	button.add_theme_font_size_override("font_size", _metrics.font(15))
	button.pressed.connect(func() -> void: _selection.request_mode(mode))
	_buttons[mode] = button
	return button
