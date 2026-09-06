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
	SlabSelection.Mode.EDGE: "Select edges. Bevel, bridge and loop them.",
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
	button.tooltip_text = "%s\nShortcut %s." % [MODE_HINTS[mode], OS.get_keycode_string(MODE_KEYS[mode])]
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("slab_mode", mode)
	button.custom_minimum_size = Vector2(_metrics.px(100.0 if with_label else 40.0), _metrics.px(36.0))
	button.add_theme_font_size_override("font_size", _metrics.font(15))
	button.pressed.connect(func() -> void: _selection.mode = mode)
	_buttons[mode] = button
	return button
