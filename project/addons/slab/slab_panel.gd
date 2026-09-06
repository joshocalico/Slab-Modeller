@tool
extends VBoxContainer

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")

const BUTTON_SIZE := Vector2(156.0, 36.0)
const SPIN_WIDTH := 104.0
const PANEL_HEIGHT := 440.0
const GRID_SEPARATION := 4.0
const DEFAULT_COLUMNS := 6
const ACCENT := Color(0.86, 0.72, 0.34)

var _selection: RefCounted
var _actions: RefCounted
var _metrics: RefCounted
var _status: Label
var _command_column: VBoxContainer
var _buttons: Dictionary = {}
var _grids: Array[GridContainer] = []
# Mode.OBJECT is 0, so -1 means the command column has never been built.
var _built_mode: int = -1


func setup(selection: RefCounted, actions: RefCounted, metrics: RefCounted = null) -> void:
	_selection = selection
	_actions = actions
	_metrics = metrics if metrics != null else preload("res://addons/slab/slab_metrics.gd").at_scale(1.0)
	name = "Slab"
	custom_minimum_size = Vector2(0.0, _scaled(PANEL_HEIGHT))
	add_theme_constant_override("separation", 6)

	_status = _status_label()
	add_child(_header())
	add_child(_fields())
	add_child(_command_scroll())

	_selection.changed.connect(refresh)
	_actions.reported.connect(set_status)
	resized.connect(_fit_columns)
	refresh()


func _scaled(value: float) -> float:
	return _metrics.px(value)


func _font(px: int) -> int:
	return _metrics.font(px)


func _fit_columns() -> void:
	# Before the first layout the panel has no width, and one column would drag its minimum width down.
	if size.x <= 0.0:
		return
	var stride: float = _scaled(BUTTON_SIZE.x + GRID_SEPARATION)
	var columns: int = maxi(1, int(size.x / stride))
	for grid in _grids:
		grid.columns = columns


func refresh() -> void:
	var mode: int = _selection.mode
	if _built_mode != mode:
		_rebuild_commands(_actions.command_sections_for(mode))
		_built_mode = mode
	_refresh_buttons()
	set_status(_selection.describe())


func _rebuild_commands(sections: Array[Dictionary]) -> void:
	# A number typed into a Create field but not yet entered would otherwise leave with its widget.
	for spin in _spins_under(_command_column):
		spin.apply()
	_buttons.clear()
	_grids.clear()
	# Nothing in the command column can change the mode, so no freed control is mid-signal here,
	# and freeing now rather than at idle keeps the outgoing buttons out of the tree at once.
	for child in _command_column.get_children():
		_command_column.remove_child(child)
		child.free()
	for section in sections:
		_command_column.add_child(_section_label(section["heading"]))
		if not section["fields"].is_empty():
			_command_column.add_child(_create_fields(section["fields"]))
		_command_column.add_child(_section_grid(section["rows"]))
	_fit_columns()


func _refresh_buttons() -> void:
	for id in _buttons:
		var button: Button = _buttons[id]
		var row: Dictionary = _actions.find(id)
		var reason: String = _actions.disabled_reason(row)
		button.disabled = reason != ""
		button.tooltip_text = reason if reason != "" else _tooltip_of(row)


func set_status(text: String) -> void:
	if _status:
		_status.text = text


func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "SLAB"
	title.add_theme_font_size_override("font_size", _font(20))
	title.add_theme_color_override("font_color", ACCENT)
	row.add_child(title)
	var strip := SlabModeStrip.new()
	row.add_child(strip)
	strip.setup(_selection, true, _metrics)
	row.add_child(_status)
	return row


func _fields() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_spin("Amount", 0.05, 64.0, 0.05, _actions.amount, func(v: float) -> void:
		_actions.amount = v
	))
	row.add_child(_spin("UV scale X", 0.05, 64.0, 0.05, _actions.uv_scale.x, func(v: float) -> void:
		_actions.uv_scale = Vector2(v, _actions.uv_scale.y)
	))
	row.add_child(_spin("UV scale Y", 0.05, 64.0, 0.05, _actions.uv_scale.y, func(v: float) -> void:
		_actions.uv_scale = Vector2(_actions.uv_scale.x, v)
	))
	row.add_child(_spin("UV offset X", -64.0, 64.0, 0.05, _actions.uv_offset.x, func(v: float) -> void:
		_actions.uv_offset = Vector2(v, _actions.uv_offset.y)
	))
	row.add_child(_spin("UV offset Y", -64.0, 64.0, 0.05, _actions.uv_offset.y, func(v: float) -> void:
		_actions.uv_offset = Vector2(_actions.uv_offset.x, v)
	))
	row.add_child(_spin("UV rotation", -360.0, 360.0, 1.0, _actions.uv_rotation_degrees, func(v: float) -> void:
		_actions.uv_rotation_degrees = v
	))
	row.add_child(_spin("Material slot", 0.0, 31.0, 1.0, float(_actions.material_slot), func(v: float) -> void:
		_actions.material_slot = int(v)
	))
	return row


func _spin(label_text: String, min_v: float, max_v: float, step: float, value: float, on_change: Callable, tooltip: String = "", key: StringName = &"") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	if key != &"":
		box.name = key
	var label := Label.new()
	label.text = label_text
	if tooltip != "":
		label.tooltip_text = tooltip
		label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.add_theme_font_size_override("font_size", _font(15))
	label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.74))
	box.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = value
	spin.tooltip_text = tooltip
	spin.custom_minimum_size.x = _scaled(SPIN_WIDTH)
	spin.add_theme_font_size_override("font_size", _font(15))
	spin.get_line_edit().add_theme_font_size_override("font_size", _font(15))
	spin.value_changed.connect(on_change)
	box.add_child(spin)
	return box


func _status_label() -> Label:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", _font(16))
	label.add_theme_color_override("font_color", ACCENT)
	label.text = "No solid selected."
	return label


func _command_scroll() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_command_column = VBoxContainer.new()
	_command_column.name = "Commands"
	_command_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_column.add_theme_constant_override("separation", 8)
	scroll.add_child(_command_column)
	return scroll


func _create_fields(fields: Array[Dictionary]) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	for field in fields:
		var key: StringName = field["key"]
		flow.add_child(_spin(field["label"], field["min"], field["max"], field["step"], field["value"], func(v: float) -> void:
			_actions.shapes.set_value(key, v)
			_refresh_buttons()
		, field["tooltip"], key))
	return flow


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", _font(16))
	label.add_theme_color_override("font_color", ACCENT)
	return label


func _section_grid(rows: Array[Dictionary]) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = DEFAULT_COLUMNS
	for row in rows:
		grid.add_child(_action_button(row))
	_grids.append(grid)
	return grid


func _action_button(row: Dictionary) -> Button:
	var id: String = row["id"]
	var button := Button.new()
	button.icon = SlabIcons.texture(row["icon"])
	button.text = row["label"]
	button.custom_minimum_size = Vector2(_scaled(BUTTON_SIZE.x), _scaled(BUTTON_SIZE.y))
	button.add_theme_font_size_override("font_size", _font(15))
	button.clip_text = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = _tooltip_of(row)
	button.pressed.connect(func() -> void: _actions.run(id))
	_buttons[id] = button
	return button


func _tooltip_of(row: Dictionary) -> String:
	var text: String = _actions.tooltip_of(row)
	var shortcut: int = row["shortcut"]
	if shortcut != 0:
		text += "\nShortcut %s." % OS.get_keycode_string(shortcut)
	return text


func _spins_under(node: Node) -> Array[SpinBox]:
	var out: Array[SpinBox] = []
	if node is SpinBox:
		out.append(node)
	for child in node.get_children():
		out.append_array(_spins_under(child))
	return out
