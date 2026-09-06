@tool
extends VBoxContainer

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")

const BUTTON_SIZE := Vector2(40.0, 36.0)
const SPIN_WIDTH := 104.0
const PANEL_HEIGHT := 320.0
const GRID_SEPARATION := 4.0
const DEFAULT_COLUMNS := 6
const ACCENT := Color(0.86, 0.72, 0.34)
const CHIP_SIZE := Vector2(28.0, 28.0)

var _selection: RefCounted
var _actions: RefCounted
var _metrics: RefCounted
var _status: Label
var _command_column: VBoxContainer
var _settings: VBoxContainer
var _settings_fields: HFlowContainer
var _settings_chips: HFlowContainer
var _buttons: Dictionary = {}
var _grids: Array[GridContainer] = []
var _create_group: ButtonGroup
var _create_focus: StringName = &"make_box"
# Mode.OBJECT is 0, so -1 means the command column has never been built.
var _built_mode: int = -1


func setup(selection: RefCounted, actions: RefCounted, metrics: RefCounted = null) -> void:
	_selection = selection
	_actions = actions
	_metrics = metrics if metrics != null else preload("res://addons/slab/slab_metrics.gd").at_scale(1.0)
	name = "Slab"
	custom_minimum_size = Vector2(0.0, _scaled(PANEL_HEIGHT))
	add_theme_constant_override("separation", 6)
	_create_group = ButtonGroup.new()

	_status = _status_label()
	add_child(_header())
	add_child(_command_scroll())
	add_child(_settings_block())

	_selection.changed.connect(refresh)
	_actions.reported.connect(_on_reported)
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
		_refresh_settings()
	_refresh_buttons()
	_refresh_material_chips()
	set_status(_selection.describe())


func focus_create(id: StringName) -> void:
	if not _actions.shapes.CATALOG.has(id):
		return
	if _create_focus == id:
		_sync_create_pressed()
		return
	_create_focus = id
	if _selection.mode == SlabSelection.Mode.OBJECT:
		_refresh_settings()
	_sync_create_pressed()


func _rebuild_commands(sections: Array[Dictionary]) -> void:
	for spin in _spins_under(_settings):
		spin.apply()
		if not spin.is_inside_tree():
			spin.value_changed.emit(spin.value)
	for id in _buttons:
		_buttons[id].set_block_signals(true)
	_buttons.clear()
	_grids.clear()
	for child in _command_column.get_children():
		_command_column.remove_child(child)
		child.free()
	for section in sections:
		_command_column.add_child(_section_label(section["heading"]))
		_command_column.add_child(_section_grid(section["rows"]))
	_fit_columns()
	_sync_create_pressed()


func _refresh_buttons() -> void:
	for id in _buttons:
		var button: Button = _buttons[id]
		var row: Dictionary = _actions.find(id)
		var reason: String = _actions.disabled_reason(row)
		button.disabled = reason != ""
		button.tooltip_text = reason if reason != "" else _tooltip_of(row)


func _refresh_settings() -> void:
	for spin in _spins_under(_settings_fields):
		spin.apply()
		if not spin.is_inside_tree():
			spin.value_changed.emit(spin.value)
	for child in _settings_fields.get_children():
		_settings_fields.remove_child(child)
		child.free()
	var mode: int = _selection.mode
	if mode == SlabSelection.Mode.OBJECT:
		for field in _actions.shapes.fields_for(_create_focus):
			_settings_fields.add_child(_shape_spin(field))
	else:
		_settings_fields.add_child(_spin("Amount", 0.05, 64.0, 0.05, _actions.amount, func(v: float) -> void:
			_actions.amount = v
		, "", &"amount"))
		if mode == SlabSelection.Mode.FACE:
			_settings_fields.add_child(_spin("UV scale X", 0.05, 64.0, 0.05, _actions.uv_scale.x, func(v: float) -> void:
				_actions.uv_scale = Vector2(v, _actions.uv_scale.y)
			, "", &"uv_scale_x"))
			_settings_fields.add_child(_spin("UV scale Y", 0.05, 64.0, 0.05, _actions.uv_scale.y, func(v: float) -> void:
				_actions.uv_scale = Vector2(_actions.uv_scale.x, v)
			, "", &"uv_scale_y"))
			_settings_fields.add_child(_spin("UV offset X", -64.0, 64.0, 0.05, _actions.uv_offset.x, func(v: float) -> void:
				_actions.uv_offset = Vector2(v, _actions.uv_offset.y)
			, "", &"uv_offset_x"))
			_settings_fields.add_child(_spin("UV offset Y", -64.0, 64.0, 0.05, _actions.uv_offset.y, func(v: float) -> void:
				_actions.uv_offset = Vector2(_actions.uv_offset.x, v)
			, "", &"uv_offset_y"))
			_settings_fields.add_child(_spin("UV rotation", -360.0, 360.0, 1.0, _actions.uv_rotation_degrees, func(v: float) -> void:
				_actions.uv_rotation_degrees = v
			, "", &"uv_rotation"))
	_refresh_material_chips()


func _refresh_material_chips() -> void:
	for child in _settings_chips.get_children():
		_settings_chips.remove_child(child)
		child.free()
	_settings_chips.visible = _selection.mode == SlabSelection.Mode.FACE
	if _selection.mode != SlabSelection.Mode.FACE:
		return
	var solid: Node = _selection.solid
	if solid == null:
		var hint := Label.new()
		hint.text = "Select a solid to paint materials."
		hint.add_theme_font_size_override("font_size", _font(15))
		hint.add_theme_color_override("font_color", Color(0.78, 0.78, 0.74))
		_settings_chips.add_child(hint)
		return
	var mats: Array = solid.materials
	for i in mats.size():
		_settings_chips.add_child(_material_chip(i, mats[i]))
	var add := Button.new()
	add.name = "add_material"
	add.icon = SlabIcons.texture("Add", _metrics.scale())
	add.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add.custom_minimum_size = Vector2(_scaled(CHIP_SIZE.x), _scaled(CHIP_SIZE.y))
	add.tooltip_text = "Add a material to this solid."
	add.focus_mode = Control.FOCUS_NONE
	add.add_theme_font_size_override("font_size", _font(15))
	add.pressed.connect(_add_material)
	_settings_chips.add_child(add)


func _material_chip(index: int, mat: Variant) -> Button:
	var chip := Button.new()
	chip.name = "material_%d" % index
	chip.toggle_mode = true
	chip.button_pressed = index == _actions.material_slot
	chip.custom_minimum_size = Vector2(_scaled(CHIP_SIZE.x), _scaled(CHIP_SIZE.y))
	chip.tooltip_text = "Paint with material %d." % index
	chip.focus_mode = Control.FOCUS_NONE
	chip.add_theme_font_size_override("font_size", _font(13))
	if mat is StandardMaterial3D:
		chip.self_modulate = mat.albedo_color
	chip.icon = SlabIcons.texture("StandardMaterial3D", _metrics.scale())
	chip.pressed.connect(func() -> void:
		_actions.material_slot = index
		_refresh_material_chips()
	)
	return chip


func _add_material() -> void:
	var solid: Node = _selection.solid
	if solid == null:
		return
	var mats: Array = solid.materials
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.55, 0.38)
	mat.roughness = 0.7
	mats.append(mat)
	solid.materials = mats
	_actions.material_slot = mats.size() - 1
	_refresh_material_chips()


func _shape_spin(field: Dictionary) -> Control:
	var key: StringName = field["key"]
	return _spin(field["label"], field["min"], field["max"], field["step"], field["value"], func(v: float) -> void:
		_actions.shapes.set_value(key, v)
		_refresh_buttons()
	, field["tooltip"], key)


func set_status(text: String) -> void:
	if _status:
		_status.text = text


func _on_reported(text: String) -> void:
	set_status(text)
	_sync_edit_fields()


func _sync_edit_fields() -> void:
	_set_spin(&"amount", _actions.amount)
	_set_spin(&"uv_scale_x", _actions.uv_scale.x)
	_set_spin(&"uv_scale_y", _actions.uv_scale.y)
	_set_spin(&"uv_offset_x", _actions.uv_offset.x)
	_set_spin(&"uv_offset_y", _actions.uv_offset.y)
	_set_spin(&"uv_rotation", _actions.uv_rotation_degrees)


func _set_spin(key: StringName, value: float) -> void:
	var box: Node = find_child(String(key), true, false)
	if box == null:
		return
	var spins: Array[SpinBox] = _spins_under(box)
	if spins.is_empty():
		return
	if not is_equal_approx(spins[0].value, value):
		spins[0].set_value_no_signal(value)


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


func _settings_block() -> Control:
	_settings = VBoxContainer.new()
	_settings.name = "Settings"
	_settings.add_theme_constant_override("separation", 6)
	_settings_fields = HFlowContainer.new()
	_settings_fields.name = "SettingsFields"
	_settings_fields.add_theme_constant_override("h_separation", 10)
	_settings.add_child(_settings_fields)
	_settings_chips = HFlowContainer.new()
	_settings_chips.name = "MaterialChips"
	_settings_chips.add_theme_constant_override("h_separation", 6)
	_settings.add_child(_settings_chips)
	return _settings


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
	button.name = id
	button.icon = SlabIcons.texture(row["icon"], _metrics.scale())
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(_scaled(BUTTON_SIZE.x), _scaled(BUTTON_SIZE.y))
	button.add_theme_font_size_override("font_size", _font(15))
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("slab_label", row["label"])
	button.tooltip_text = _tooltip_of(row)
	if _actions.section_of(row) == _actions.SECTION_CREATE:
		button.toggle_mode = true
		button.button_group = _create_group
		button.mouse_entered.connect(func() -> void: focus_create(StringName(id)))
	button.pressed.connect(func() -> void:
		if _actions.section_of(row) == _actions.SECTION_CREATE:
			focus_create(StringName(id))
		_actions.run(id)
	)
	_buttons[id] = button
	return button


func _sync_create_pressed() -> void:
	for id in _buttons:
		var row: Dictionary = _actions.find(id)
		if row.is_empty() or _actions.section_of(row) != _actions.SECTION_CREATE:
			continue
		_buttons[id].set_pressed_no_signal(StringName(id) == _create_focus)


func _tooltip_of(row: Dictionary) -> String:
	var lines := PackedStringArray([row["label"]])
	var body: String = _actions.tooltip_of(row)
	if body != "":
		lines.append(body)
	var shortcut: int = row["shortcut"]
	if shortcut != 0:
		lines.append("Shortcut %s." % OS.get_keycode_string(shortcut))
	return "\n".join(lines)


func _spins_under(node: Node) -> Array[SpinBox]:
	var out: Array[SpinBox] = []
	if node is SpinBox:
		out.append(node)
	for child in node.get_children():
		out.append_array(_spins_under(child))
	return out
