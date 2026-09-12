@tool
extends VBoxContainer

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPaintCanvas := preload("res://addons/slab/slab_paint_canvas.gd")
const SlabPaint := preload("res://addons/slab/slab_paint.gd")

const BUTTON_HEIGHT := 36.0
const SPIN_WIDTH := 104.0
const PANEL_HEIGHT := 240.0
const GRID_SEPARATION := 4.0
const ACCENT := Color(0.86, 0.72, 0.34)
const CHIP_SIZE := Vector2(28.0, 28.0)
const PAINT_PALETTE_HEIGHT := 40.0
const PAINT_ROW_HEIGHT := 28.0
const PAINT_UV_ROW_HEIGHT := 44.0

var _selection: RefCounted
var _actions: RefCounted
var _metrics: RefCounted
var _status: Label
var _last_report := ""
var _command_column: VBoxContainer
var _settings: VBoxContainer
var _settings_fields: HFlowContainer
var _settings_chips: HFlowContainer
var _buttons: Dictionary = {}
var _create_group: ButtonGroup
var _create_focus: StringName = &"make_box"
# Mode.OBJECT is 0, so -1 means the command column has never been built.
var _built_mode: int = -1
var _uv_open: bool = false
var _settings_title: Label
var _uv_wrap: HFlowContainer
var _undo_hook: Object = null
var _paint: RefCounted
var _model_body: VBoxContainer
var _paint_body: Control
var _paint_toggle: Button
var _paint_canvas: Control
var _paint_face: Label
var _paint_mat: Label
var _paint_dirty: Label
var _paint_palette: ScrollContainer
var _paint_chips: HBoxContainer
var _paint_tool_uv: Button
var _paint_tool_pixel: Button
var _unique_button: Button
var _paint_picker: Node
var _paint_uv_hint: Label
var _paint_uv_controls: Control
var _brush_radius: SpinBox
var _brush_opacity: SpinBox
var _brush_color: ColorPickerButton


func setup(selection: RefCounted, actions: RefCounted, metrics: RefCounted = null) -> void:
	_selection = selection
	_actions = actions
	_actions.loop_values_updated.connect(_sync_loop_values)
	_actions.plane_state_changed.connect(_refresh_settings)
	_actions.array_state_changed.connect(_refresh_settings)
	_actions.snap_align_state_changed.connect(_refresh_settings)
	_metrics = metrics if metrics != null else preload("res://addons/slab/slab_metrics.gd").at_scale(1.0)
	name = "Slab"
	clip_contents = true
	custom_minimum_size = Vector2(0.0, _scaled(PANEL_HEIGHT))
	add_theme_constant_override("separation", 6)
	_create_group = ButtonGroup.new()

	_status = _status_label()
	add_child(_header())
	add_child(_status)
	_model_body = VBoxContainer.new()
	_model_body.name = "ModelBody"
	_model_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_model_body.add_theme_constant_override("separation", 8)
	_model_body.add_child(_command_scroll())
	_model_body.add_child(_settings_block())
	add_child(_model_body)
	_paint_body = _paint_block()
	_paint_body.visible = false
	add_child(_paint_body)

	_selection.changed.connect(_on_selection_changed)
	_actions.reported.connect(_on_reported)
	_actions.status_reset_requested.connect(_reset_status)
	refresh()


func _get_minimum_size() -> Vector2:
	var min_size := Vector2(0.0, _scaled(PANEL_HEIGHT))
	if _paint != null and _paint.active:
		min_size.y = _scaled(SlabPaint.PAINT_HEIGHT)
	return min_size


func bind_paint(paint: RefCounted) -> void:
	_paint = paint
	if _paint != null and _paint.has_signal("changed"):
		if not _paint.changed.is_connected(_on_paint_changed):
			_paint.changed.connect(_on_paint_changed)
	if _paint != null and _paint.has_signal("reported"):
		if not _paint.reported.is_connected(_on_reported):
			_paint.reported.connect(_on_reported)
	if _paint_canvas != null:
		_paint_canvas.setup(_paint, _metrics)
	_on_paint_changed()


func bind_undo(undo: Object) -> void:
	if _undo_hook != null and _undo_hook.has_signal("version_changed"):
		if _undo_hook.version_changed.is_connected(_refresh_soon):
			_undo_hook.version_changed.disconnect(_refresh_soon)
	_undo_hook = undo
	if _undo_hook != null and _undo_hook.has_signal("version_changed"):
		_undo_hook.version_changed.connect(_refresh_soon)


func _refresh_soon() -> void:
	call_deferred("refresh")


func _scaled(value: float) -> float:
	return _metrics.px(value)


func _font(px: int) -> int:
	return _metrics.font(px)


func refresh() -> void:
	var mode: int = _selection.mode
	if _built_mode != mode:
		_rebuild_commands(_actions.command_sections_for(mode))
		_built_mode = mode
		_refresh_settings()
	_refresh_buttons()
	_refresh_material_chips()
	set_status(_last_report if _last_report != "" else _selection.describe())
	if _paint != null and _paint.active:
		_refresh_paint_chrome()


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
	for child in _command_column.get_children():
		_command_column.remove_child(child)
		child.free()
	for section in sections:
		_command_column.add_child(_section_label(section["heading"]))
		_command_column.add_child(_section_flow(section["rows"]))
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
		child.queue_free()
	var mode: int = _selection.mode
	if mode == SlabSelection.Mode.OBJECT:
		_settings_title.text = "Snap to Vertex" if _actions.snap_align_active else ("Array" if _actions.array_active else ("Plane Cut" if _actions.plane_active else "New %s" % _create_label()))
		_settings_title.visible = true
		_uv_wrap = null
		if _actions.snap_align_active:
			_add_snap_align_settings()
		elif _actions.array_active:
			_add_array_settings()
		elif _actions.plane_active:
			_settings_fields.add_child(_spin("Normal X", -64.0, 64.0, 0.05, _actions.plane_normal.x, func(v: float) -> void:
				_actions.plane_normal.x = v
				_actions.plane_settings_changed.emit()
			, "Local-space plane normal X.", &"plane_normal_x"))
			_settings_fields.add_child(_spin("Normal Y", -64.0, 64.0, 0.05, _actions.plane_normal.y, func(v: float) -> void:
				_actions.plane_normal.y = v
				_actions.plane_settings_changed.emit()
			, "Local-space plane normal Y.", &"plane_normal_y"))
			_settings_fields.add_child(_spin("Normal Z", -64.0, 64.0, 0.05, _actions.plane_normal.z, func(v: float) -> void:
				_actions.plane_normal.z = v
				_actions.plane_settings_changed.emit()
			, "Local-space plane normal Z.", &"plane_normal_z"))
			_settings_fields.add_child(_spin("Offset m", -64.0, 64.0, 0.000001, _actions.plane_offset, func(v: float) -> void:
				_actions.plane_offset = v
				_actions.plane_settings_changed.emit()
			, "Metres from the local origin along the normalized normal.", &"plane_offset"))
			var side := OptionButton.new()
			side.name = "plane_side"
			side.add_item("Keep negative", 0)
			side.add_item("Keep positive", 1)
			side.select(1 if _actions.plane_keep_positive else 0)
			side.tooltip_text = "Choose which closed half of the solid remains."
			side.item_selected.connect(func(index: int) -> void:
				_actions.plane_keep_positive = index == 1
				_actions.plane_settings_changed.emit()
			)
			_settings_fields.add_child(side)
			_settings_fields.add_child(_spin("Cap material", 0, 4096, 1, _actions.plane_cap_material, func(v: float) -> void:
				_actions.plane_cap_material = int(v)
				_actions.plane_settings_changed.emit()
			, "Material slot assigned to every new cap.", &"plane_cap_material"))
			_settings_fields.add_child(_named_action("Apply", "Apply", "Apply the preview as one undoable edit.", func() -> void:
				_actions.plane_apply_requested.emit()
			))
			_settings_fields.add_child(_named_action("Cancel", "Clear", "Discard the preview and keep the original solid.", func() -> void:
				_actions.plane_cancel_requested.emit()
			))
		else:
			for field in _actions.shapes.fields_for(_create_focus):
				_settings_fields.add_child(_shape_spin(field))
	elif mode == SlabSelection.Mode.FACE:
		_settings_title.text = "Align Face" if _actions.snap_align_active else "Distance"
		_settings_title.visible = true
		if _actions.snap_align_active:
			_add_snap_align_settings()
			_uv_wrap = null
		else:
			_settings_fields.add_child(_spin("Distance", SlabActions.EXTRUDE_FLOOR, SlabActions.AMOUNT_CEILING, 0.05, _actions.amount, func(v: float) -> void:
				_actions.amount = v
			, "Positive extrudes outward. Negative extrudes inward. Inset uses the absolute value.", &"amount"))
			_settings_fields.add_child(_uv_toggle())
			_uv_wrap = HFlowContainer.new()
			_uv_wrap.name = "UvFields"
			_uv_wrap.add_theme_constant_override("h_separation", 10)
			_uv_wrap.visible = _uv_open
			_uv_wrap.add_child(_spin("UV scale X", 0.05, 64.0, 0.05, _actions.uv_scale.x, func(v: float) -> void:
				_actions.uv_scale = Vector2(v, _actions.uv_scale.y)
			, "", &"uv_scale_x"))
			_uv_wrap.add_child(_spin("UV scale Y", 0.05, 64.0, 0.05, _actions.uv_scale.y, func(v: float) -> void:
				_actions.uv_scale = Vector2(_actions.uv_scale.x, v)
			, "", &"uv_scale_y"))
			_uv_wrap.add_child(_spin("UV offset X", -64.0, 64.0, 0.05, _actions.uv_offset.x, func(v: float) -> void:
				_actions.uv_offset = Vector2(v, _actions.uv_offset.y)
			, "", &"uv_offset_x"))
			_uv_wrap.add_child(_spin("UV offset Y", -64.0, 64.0, 0.05, _actions.uv_offset.y, func(v: float) -> void:
				_actions.uv_offset = Vector2(_actions.uv_offset.x, v)
			, "", &"uv_offset_y"))
			_uv_wrap.add_child(_spin("UV rotation", -360.0, 360.0, 1.0, _actions.uv_rotation_degrees, func(v: float) -> void:
				_actions.uv_rotation_degrees = v
			, "", &"uv_rotation"))
			_uv_wrap.add_child(_spin("Pixels / metre", 1, 4096, 1, _actions.uv_pixels_per_meter, func(v: float) -> void:
				_actions.uv_pixels_per_meter = v
			, "Density used by Unwrap.", &"uv_pixels_per_meter"))
			_uv_wrap.add_child(_spin("Texture px", 16, 16384, 1, _actions.uv_texture_resolution, func(v: float) -> void:
				_actions.uv_texture_resolution = int(v)
			, "Texture resolution used to convert density into normalized UV scale.", &"uv_texture_resolution"))
			_settings_fields.add_child(_uv_wrap)
	else:
		_settings_title.text = "Bevel" if _actions.bevel_active else ("Snap to Vertex" if _actions.snap_align_active else "Amount")
		_settings_title.visible = true
		if _actions.bevel_active:
			_add_bevel_settings()
		elif _actions.snap_align_active:
			_add_snap_align_settings()
		else:
			_settings_fields.add_child(_spin("Amount", SlabActions.AMOUNT_FLOOR, SlabActions.AMOUNT_CEILING, 0.05, _clamped_amount(), func(v: float) -> void:
				_actions.amount = v
			, "", &"amount"))
		_uv_wrap = null
	if mode == SlabSelection.Mode.EDGE and not _actions.snap_align_active and not _actions.bevel_active:
		_settings_fields.add_child(_spin("Cuts", 1, 32, 1, _actions.loop_count, func(v: float) -> void:
			_actions.loop_count = int(v)
			_actions.loop_settings_changed.emit()
		, "Number of evenly spaced loop cuts.", &"loop_count"))
		_settings_fields.add_child(_spin("Centre %", 0.1, 99.9, 0.1, _actions.loop_position * 100.0, func(v: float) -> void:
			_actions.loop_position = v / 100.0
			_actions.loop_settings_changed.emit()
		, "Centre of the loop group as a percentage along the starting edge.", &"loop_position"))
	_refresh_material_chips()


func _add_array_settings() -> void:
	var kinds := HBoxContainer.new()
	kinds.name = "array_mode"
	kinds.add_theme_constant_override("separation", int(_scaled(6.0)))
	for entry in [["Linear", SlabActions.ARRAY_LINEAR], ["Radial", SlabActions.ARRAY_RADIAL]]:
		var kind := Button.new()
		kind.name = "array_%s" % String(entry[0]).to_lower()
		kind.text = entry[0]
		kind.toggle_mode = true
		kind.button_pressed = _actions.array_mode == entry[1]
		kind.tooltip_text = "Use %s array spacing." % String(entry[0]).to_lower()
		kind.add_theme_font_size_override("font_size", _font(14))
		kind.pressed.connect(func() -> void:
			_actions.array_mode = entry[1]
			_actions.array_settings_changed.emit()
			call_deferred("_refresh_settings")
		)
		kinds.add_child(kind)
	_settings_fields.add_child(kinds)
	_settings_fields.add_child(_spin("Count", 2, 256, 1, _actions.array_count, func(v: float) -> void:
		_actions.array_count = int(v)
		_actions.array_settings_changed.emit()
	, "Total instances including the selected source.", &"array_count"))
	if _actions.array_mode == SlabActions.ARRAY_LINEAR:
		_add_array_vector("Step", "array_step", _actions.array_linear_step, func(value: Vector3) -> void:
			_actions.array_linear_step = value
		)
	else:
		_add_array_vector("Centre", "array_center", _actions.array_radial_center, func(value: Vector3) -> void:
			_actions.array_radial_center = value
		)
		_add_array_vector("Axis", "array_axis", _actions.array_radial_axis, func(value: Vector3) -> void:
			_actions.array_radial_axis = value
		)
		_settings_fields.add_child(_spin("Angle °", -360.0, 360.0, 0.1, _actions.array_radial_angle_degrees, func(v: float) -> void:
			_actions.array_radial_angle_degrees = v
			_actions.array_settings_changed.emit()
		, "Exact angle between neighbouring instances.", &"array_angle"))
		var rotate := CheckButton.new()
		rotate.name = "array_rotate"
		rotate.text = "Rotate copies"
		rotate.button_pressed = _actions.array_rotate_copies
		rotate.tooltip_text = "Turn each copy around the radial axis with its position."
		rotate.add_theme_font_size_override("font_size", _font(14))
		rotate.toggled.connect(func(on: bool) -> void:
			_actions.array_rotate_copies = on
			_actions.array_settings_changed.emit()
		)
		_settings_fields.add_child(rotate)
	_settings_fields.add_child(_named_action("Apply", "Apply", "Create every previewed copy as one undo action.", func() -> void:
		_actions.array_apply_requested.emit()
	))
	_settings_fields.add_child(_named_action("Cancel", "Clear", "Discard the preview without changing the scene.", func() -> void:
		_actions.array_cancel_requested.emit()
	))


func _add_snap_align_settings() -> void:
	var hint := Label.new()
	hint.name = "snap_align_hint"
	hint.text = "Hover another solid, then click its target vertex." if _actions.snap_align_mode == SlabActions.SNAP_VERTEX else "Hover another solid, then click its target face."
	hint.tooltip_text = "The cyan preview shows the exact anchor pair or final rigid placement."
	hint.add_theme_font_size_override("font_size", _font(14))
	_settings_fields.add_child(hint)
	if _actions.snap_align_mode == SlabActions.SNAP_FACE:
		var oppose := CheckButton.new()
		oppose.name = "align_oppose_normals"
		oppose.text = "Oppose normals"
		oppose.button_pressed = _actions.align_oppose_normals
		oppose.tooltip_text = "Seat faces against each other. Disable to point their normals the same way."
		oppose.add_theme_font_size_override("font_size", _font(14))
		oppose.toggled.connect(func(on: bool) -> void:
			_actions.align_oppose_normals = on
			_actions.snap_align_settings_changed.emit()
		)
		_settings_fields.add_child(oppose)
	_settings_fields.add_child(_named_action("Cancel", "Clear", "Leave the source unchanged and clear the target preview.", func() -> void:
		_actions.snap_align_cancel_requested.emit()
	))


func _add_bevel_settings() -> void:
	_settings_fields.add_child(_spin("Amount", SlabActions.AMOUNT_FLOOR, SlabActions.AMOUNT_CEILING, 0.05, _actions.amount, func(v: float) -> void:
		_actions.amount = v
		_actions.bevel_settings_changed.emit()
	, "Exact bevel width in metres.", &"bevel_amount"))
	_settings_fields.add_child(_spin("Segments", 1, 16, 1, _actions.bevel_segments, func(v: float) -> void:
		_actions.bevel_segments = int(v)
		_actions.bevel_settings_changed.emit()
	, "One is a chamfer; higher values make a rounder profile.", &"bevel_segments"))
	_settings_fields.add_child(_named_action("Apply", "Apply", "Commit the preview as one undoable bevel.", func() -> void:
		_actions.bevel_apply_requested.emit()
	))
	_settings_fields.add_child(_named_action("Cancel", "Clear", "Discard the bevel preview.", func() -> void:
		_actions.bevel_cancel_requested.emit()
	))


func _add_array_vector(label: String, key_prefix: String, value: Vector3, changed: Callable) -> void:
	for component in ["x", "y", "z"]:
		var axis: String = component
		var index := Vector3.AXIS_X if axis == "x" else (Vector3.AXIS_Y if axis == "y" else Vector3.AXIS_Z)
		_settings_fields.add_child(_spin("%s %s" % [label, axis.to_upper()], -1024.0, 1024.0, 0.01, value[index], func(v: float) -> void:
			var next: Vector3 = _actions.array_linear_step
			if key_prefix == "array_center":
				next = _actions.array_radial_center
			elif key_prefix == "array_axis":
				next = _actions.array_radial_axis
			next[index] = v
			changed.call(next)
			_actions.array_settings_changed.emit()
		, "Parent-local %s %s component." % [label.to_lower(), axis.to_upper()], StringName("%s_%s" % [key_prefix, axis])))


func _refresh_material_chips() -> void:
	for child in _settings_chips.get_children():
		_settings_chips.remove_child(child)
		child.queue_free()
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
	_actions.clamp_material_slot()
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
		call_deferred("_refresh_material_chips")
	)
	return chip


func _add_material() -> void:
	_actions.add_material()
	call_deferred("_refresh_material_chips")


func _create_label() -> String:
	for entry in _actions.shapes.entries():
		if StringName(entry["id"]) == _create_focus:
			return str(entry["label"])
	return "solid"


func _clamped_amount() -> float:
	return clampf(absf(_actions.amount), SlabActions.AMOUNT_FLOOR, SlabActions.AMOUNT_CEILING)


func _uv_toggle() -> Button:
	var button := Button.new()
	button.name = "uv_toggle"
	button.text = "UV"
	button.toggle_mode = true
	button.button_pressed = _uv_open
	button.tooltip_text = "Show UV scale, offset, and rotation."
	button.focus_mode = Control.FOCUS_ALL
	button.accessibility_name = "Toggle UV settings"
	button.accessibility_description = button.tooltip_text
	button.custom_minimum_size.y = _scaled(BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", _font(15))
	button.pressed.connect(func() -> void:
		_uv_open = button.button_pressed
		if _uv_wrap != null:
			_uv_wrap.visible = _uv_open
	)
	return button


func _shape_spin(field: Dictionary) -> Control:
	var key: StringName = field["key"]
	return _spin(field["label"], field["min"], field["max"], field["step"], field["value"], func(v: float) -> void:
		_actions.shapes.set_value(key, v)
		_refresh_buttons()
	, field["tooltip"], key)


func set_status(text: String) -> void:
	if _status:
		_status.text = text
		_status.tooltip_text = text


func _on_reported(text: String) -> void:
	_last_report = text
	set_status(text)
	_sync_edit_fields()
	if _selection.mode == SlabSelection.Mode.FACE:
		call_deferred("_refresh_material_chips")


func _on_selection_changed() -> void:
	_last_report = ""
	refresh()


func _reset_status() -> void:
	_last_report = ""
	set_status(_selection.describe())


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
	_paint_toggle = Button.new()
	_paint_toggle.name = "SurfacePaint"
	_paint_toggle.text = "Surface Paint"
	_paint_toggle.toggle_mode = true
	_paint_toggle.focus_mode = Control.FOCUS_ALL
	_paint_toggle.tooltip_text = "Open the Surface Paint workspace. Escape closes it."
	_paint_toggle.accessibility_name = "Surface Paint"
	_paint_toggle.accessibility_description = _paint_toggle.tooltip_text
	_paint_toggle.add_theme_font_size_override("font_size", _font(15))
	_paint_toggle.custom_minimum_size.y = _scaled(BUTTON_HEIGHT)
	_paint_toggle.pressed.connect(func() -> void:
		if _paint != null:
			_paint.toggle()
	)
	row.add_child(_paint_toggle)
	return row


func _settings_block() -> Control:
	_settings = VBoxContainer.new()
	_settings.name = "Settings"
	_settings.add_theme_constant_override("separation", 6)
	_settings_title = Label.new()
	_settings_title.name = "SettingsTitle"
	_settings_title.add_theme_font_size_override("font_size", _font(16))
	_settings_title.add_theme_color_override("font_color", ACCENT)
	_settings.add_child(_settings_title)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size.y = _scaled(96.0)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_settings_fields = HFlowContainer.new()
	_settings_fields.name = "SettingsFields"
	_settings_fields.add_theme_constant_override("h_separation", 10)
	_settings_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_settings_fields)
	_settings.add_child(scroll)
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
	label.name = "Status"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.add_theme_font_size_override("font_size", _font(16))
	label.add_theme_color_override("font_color", ACCENT)
	label.text = "No solid selected."
	label.tooltip_text = label.text
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


func _section_flow(rows: Array[Dictionary]) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", int(_scaled(GRID_SEPARATION)))
	flow.add_theme_constant_override("v_separation", int(_scaled(GRID_SEPARATION)))
	for row in rows:
		flow.add_child(_action_button(row))
	return flow


func _action_button(row: Dictionary) -> Button:
	var id: String = row["id"]
	var button := Button.new()
	button.name = id
	button.icon = SlabIcons.texture(row["icon"], _metrics.scale())
	button.text = row["label"]
	button.clip_text = false
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_ALL
	button.accessibility_name = row["label"]
	button.accessibility_description = _actions.tooltip_of(row)
	button.add_theme_font_size_override("font_size", _font(15))
	button.custom_minimum_size = Vector2(0.0, _scaled(BUTTON_HEIGHT))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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


func _paint_block() -> Control:
	var body := VBoxContainer.new()
	body.name = "PaintBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	body.add_theme_constant_override("separation", 4)
	body.add_child(_paint_target_row())
	body.add_child(_paint_action_row())
	_paint_uv_controls = _paint_uv_control_row()
	body.add_child(_paint_uv_controls)
	_paint_palette = ScrollContainer.new()
	_paint_palette.name = "PaintPalette"
	_paint_palette.custom_minimum_size.y = _scaled(PAINT_PALETTE_HEIGHT)
	_paint_palette.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_paint_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paint_palette.clip_contents = true
	_paint_palette.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_paint_palette.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_paint_chips = HBoxContainer.new()
	_paint_chips.name = "PaintSlots"
	_paint_chips.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_paint_chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_paint_chips.add_theme_constant_override("separation", 6)
	_paint_palette.add_child(_paint_chips)
	body.add_child(_paint_palette)
	var row := HBoxContainer.new()
	row.name = "PaintCanvasRow"
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.clip_contents = true
	row.add_theme_constant_override("separation", 8)
	_paint_canvas = SlabPaintCanvas.new()
	_paint_canvas.setup(_paint, _metrics)
	_paint_canvas.stroke_started.connect(func() -> void:
		if _paint:
			_paint.begin_stroke()
	)
	_paint_canvas.painted_pixel.connect(func(pixel: Vector2) -> void:
		if _paint:
			_paint.dab_pixel(pixel)
	)
	_paint_canvas.stroke_ended.connect(func() -> void:
		if _paint:
			_paint.end_stroke()
	)
	_paint_canvas.stroke_cancelled.connect(func() -> void:
		if _paint:
			_paint.cancel_stroke()
	)
	_paint_canvas.uv_dragged.connect(func(delta: Vector2, mode: int) -> void:
		if _paint:
			_paint.drag_uv(delta, mode)
	)
	_paint_uv_hint = Label.new()
	_paint_uv_hint.name = "PaintUvHint"
	_paint_uv_hint.text = SlabPaint.uv_canvas_hint()
	_paint_uv_hint.add_theme_font_size_override("font_size", _font(12))
	_paint_uv_hint.add_theme_color_override("font_color", Color(0.92, 0.86, 0.62, 0.92))
	_paint_uv_hint.clip_text = true
	_paint_uv_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_paint_uv_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint_uv_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_paint_uv_hint.offset_left = 6
	_paint_uv_hint.offset_top = 4
	_paint_uv_hint.offset_right = -6
	_paint_uv_hint.offset_bottom = 18
	_paint_canvas.add_child(_paint_uv_hint)
	row.add_child(_paint_canvas)
	row.add_child(_brush_column())
	body.add_child(row)
	return body


func _paint_target_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "PaintTarget"
	row.custom_minimum_size.y = _scaled(PAINT_ROW_HEIGHT)
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.clip_contents = true
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	_paint_tool_uv = _paint_tool_button("Material / UV", SlabPaint.Tool.MATERIAL_UV, group)
	_paint_tool_pixel = _paint_tool_button("Pixel", SlabPaint.Tool.PIXEL, group)
	row.add_child(_paint_tool_uv)
	row.add_child(_paint_tool_pixel)
	_paint_face = _paint_caption("Face", "none")
	_paint_mat = _paint_caption("Material", "none")
	_paint_dirty = _paint_caption("Save", "")
	_paint_dirty.name = "PaintDirty"
	row.add_child(_paint_face)
	row.add_child(_paint_mat)
	row.add_child(_paint_dirty)
	return row


func _paint_action_row() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "PaintActions"
	scroll.custom_minimum_size.y = _scaled(PAINT_ROW_HEIGHT)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.clip_contents = true
	var tools := HBoxContainer.new()
	tools.custom_minimum_size.y = _scaled(PAINT_ROW_HEIGHT)
	tools.clip_contents = true
	tools.add_theme_constant_override("separation", 8)
	_unique_button = _named_action("Make Unique", "Duplicate", "Copies this solid's material so painting does not rewrite shared tiles.", func() -> void:
		if _paint:
			_paint.make_unique()
	)
	tools.add_child(_unique_button)
	tools.add_child(_named_action("Save Paint", "Save", "Writes the albedo PNG so paint survives reopen.", func() -> void:
		if _paint:
			_paint.save_png(_paint.default_save_path())
	))
	tools.add_child(_named_action("Sample", "ListSelect", "Click a face in the viewport with Alt, or this then a face, to copy material and UV.", func() -> void:
		if _paint and _selection.solid != null and not _selection.ids.is_empty():
			_paint.sample_face(_selection.solid, _selection.ids[0])
	))
	tools.add_child(_paint_picker_slot())
	scroll.add_child(tools)
	return scroll


func _paint_uv_control_row() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "PaintUvControls"
	scroll.custom_minimum_size.y = _scaled(PAINT_UV_ROW_HEIGHT)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.clip_contents = true
	var fields := HBoxContainer.new()
	fields.name = "PaintUvFields"
	fields.custom_minimum_size.y = _scaled(PAINT_ROW_HEIGHT)
	fields.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	fields.add_theme_constant_override("separation", 8)
	fields.add_child(_compact_spin("Repeat U", 0.05, 64.0, 0.05, 1.0, func(v: float) -> void:
		_actions.uv_scale = Vector2(v, _actions.uv_scale.y)
	, "Texture repeats across the face in U.", &"paint_uv_repeat_u"))
	fields.add_child(_compact_spin("Repeat V", 0.05, 64.0, 0.05, 1.0, func(v: float) -> void:
		_actions.uv_scale = Vector2(_actions.uv_scale.x, v)
	, "Texture repeats across the face in V.", &"paint_uv_repeat_v"))
	fields.add_child(_compact_spin("Offset U", -64.0, 64.0, 0.05, 0.0, func(v: float) -> void:
		_actions.uv_offset = Vector2(v, _actions.uv_offset.y)
	, "Texture offset in U.", &"paint_uv_offset_u"))
	fields.add_child(_compact_spin("Offset V", -64.0, 64.0, 0.05, 0.0, func(v: float) -> void:
		_actions.uv_offset = Vector2(_actions.uv_offset.x, v)
	, "Texture offset in V.", &"paint_uv_offset_v"))
	fields.add_child(_compact_spin("Rotation", -360.0, 360.0, 1.0, 0.0, func(v: float) -> void:
		_actions.uv_rotation_degrees = v
	, "Texture rotation in degrees.", &"paint_uv_rotation"))
	fields.add_child(_named_action("Apply UV", "ImageTexture", "Apply these UV values to the selected face.", func() -> void:
		if _paint:
			_paint.apply_uv()
	))
	fields.add_child(_named_action("Reset UV", "Reload", "Reset repeats, offsets and rotation on the selected face.", func() -> void:
		if _paint:
			_paint.reset_uv()
	))
	fields.add_child(_named_action("UV 90°", "ToolRotate", "Rotate UV placement by ninety degrees.", func() -> void:
		if _paint:
			_paint.rotate_uv_90()
	))
	scroll.add_child(fields)
	return scroll


func _paint_picker_slot() -> Control:
	var wrap := Control.new()
	wrap.name = "PaintMaterialPickerWrap"
	wrap.custom_minimum_size = Vector2(_scaled(168.0), _scaled(PAINT_ROW_HEIGHT))
	wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = true
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	var picker: Node = _make_paint_picker()
	wrap.add_child(picker)
	wrap.resized.connect(func() -> void:
		if picker is Control and is_instance_valid(picker):
			picker.position = Vector2.ZERO
			picker.size = wrap.size
			_compact_resource_preview(picker)
	)
	_compact_resource_preview(picker)
	return wrap


func _make_paint_picker() -> Node:
	if Engine.is_editor_hint() and ClassDB.class_exists("EditorResourcePicker"):
		var picker: Variant = ClassDB.instantiate("EditorResourcePicker")
		if picker is Node:
			_paint_picker = picker
			picker.name = "PaintMaterialPicker"
			picker.set("base_type", "StandardMaterial3D")
			picker.set("toggle_mode", false)
			if picker is Control:
				picker.custom_minimum_size = Vector2(_scaled(168.0), _scaled(PAINT_ROW_HEIGHT))
				picker.clip_contents = true
			if picker.has_signal("resource_changed"):
				picker.resource_changed.connect(func(res: Resource) -> void:
					if _paint != null and res is StandardMaterial3D:
						_paint.pick_material(res)
				)
			if picker.has_signal("child_entered_tree"):
				picker.child_entered_tree.connect(func(_n: Node) -> void:
					_compact_resource_preview(picker)
				)
			_apply_picker_fonts(picker)
			return picker
	var fake := Button.new()
	fake.name = "PaintMaterialPicker"
	fake.text = "Assign"
	fake.clip_text = true
	fake.focus_mode = Control.FOCUS_NONE
	fake.custom_minimum_size = Vector2(_scaled(168.0), _scaled(PAINT_ROW_HEIGHT))
	fake.add_theme_font_size_override("font_size", _font(13))
	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.custom_minimum_size = Vector2(64, 64)
	preview.mouse_filter = Control.MOUSE_FILTER_STOP
	fake.add_child(preview)
	_paint_picker = fake
	return fake


func _compact_resource_preview(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is TextureRect:
		node.visible = false
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.custom_minimum_size = Vector2.ZERO
		node.size = Vector2.ZERO
	if node is Button:
		node.add_theme_constant_override("icon_max_width", int(_scaled(16.0)))
		node.expand_icon = false
		node.custom_minimum_size.y = _scaled(PAINT_ROW_HEIGHT)
		node.clip_contents = true
	if node is Control:
		node.clip_contents = true
		if node.custom_minimum_size.y > _scaled(PAINT_ROW_HEIGHT):
			node.custom_minimum_size.y = _scaled(PAINT_ROW_HEIGHT)
	for child in node.get_children():
		_compact_resource_preview(child)


func _apply_picker_fonts(node: Node) -> void:
	if node is Label or node is Button or node is LineEdit:
		node.add_theme_font_size_override("font_size", _font(13))
	for child in node.get_children():
		_apply_picker_fonts(child)


func _brush_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = _scaled(132.0)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", 2)
	var brush := Label.new()
	brush.text = "Brush"
	brush.add_theme_font_size_override("font_size", _font(13))
	brush.add_theme_color_override("font_color", ACCENT)
	col.add_child(brush)
	_brush_color = ColorPickerButton.new()
	_brush_color.name = "BrushColor"
	_brush_color.color = Color(0.86, 0.18, 0.16)
	_brush_color.custom_minimum_size = Vector2(_scaled(120.0), _scaled(PAINT_ROW_HEIGHT))
	_brush_color.add_theme_font_size_override("font_size", _font(13))
	_brush_color.focus_mode = Control.FOCUS_NONE
	_brush_color.color_changed.connect(func(c: Color) -> void:
		if _paint:
			_paint.brush_color = c
	)
	col.add_child(_brush_color)
	col.add_child(_compact_spin("Radius", 1.0, 64.0, 1.0, 8.0, func(v: float) -> void:
		if _paint:
			_paint.brush_radius = v
	, "Brush radius in texture pixels.", &"brush_radius"))
	col.add_child(_compact_spin("Opacity", 0.05, 1.0, 0.05, 1.0, func(v: float) -> void:
		if _paint:
			_paint.brush_opacity = v
	, "Brush opacity.", &"brush_opacity"))
	return col


func _compact_spin(label_text: String, min_v: float, max_v: float, step: float, value: float, on_change: Callable, tooltip: String, key: StringName) -> Control:
	var row := HBoxContainer.new()
	row.name = String(key)
	row.custom_minimum_size.y = _scaled(PAINT_ROW_HEIGHT)
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = tooltip
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.add_theme_font_size_override("font_size", _font(12))
	label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.74))
	label.custom_minimum_size.x = _scaled(52.0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = value
	spin.tooltip_text = tooltip
	spin.focus_mode = Control.FOCUS_ALL
	spin.accessibility_name = label_text
	spin.accessibility_description = tooltip
	spin.custom_minimum_size.x = _scaled(76.0)
	spin.add_theme_font_size_override("font_size", _font(12))
	spin.get_line_edit().add_theme_font_size_override("font_size", _font(12))
	spin.get_line_edit().select_all_on_focus = true
	spin.value_changed.connect(on_change)
	row.add_child(spin)
	return row


func _paint_tool_button(text: String, tool: int, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.name = "PaintToolPixel" if tool == SlabPaint.Tool.PIXEL else "PaintToolMaterial"
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = tool == SlabPaint.Tool.MATERIAL_UV
	button.focus_mode = Control.FOCUS_ALL
	button.accessibility_name = text
	button.add_theme_font_size_override("font_size", _font(15))
	button.custom_minimum_size = Vector2(_scaled(110.0), _scaled(PAINT_ROW_HEIGHT))
	button.set_meta("slab_label", text)
	button.pressed.connect(func() -> void:
		if _paint:
			_paint.tool = tool
	)
	return button


func _named_action(text: String, icon: String, tip: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = SlabIcons.texture(icon, _metrics.scale())
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_ALL
	button.accessibility_name = text
	button.accessibility_description = tip
	button.clip_text = false
	button.clip_contents = true
	button.add_theme_font_size_override("font_size", _font(13))
	button.add_theme_constant_override("icon_max_width", int(_scaled(16.0)))
	button.custom_minimum_size = Vector2(0.0, _scaled(PAINT_ROW_HEIGHT))
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.set_meta("slab_label", text)
	button.pressed.connect(func() -> void:
		# Modal actions rebuild this settings row. Release keyboard focus first so
		# editor shortcuts such as Undo work immediately after Apply.
		button.release_focus()
		on_press.call()
	)
	return button


func _paint_caption(heading: String, text: String) -> Label:
	var label := Label.new()
	label.text = "%s: %s" % [heading, text]
	label.add_theme_font_size_override("font_size", _font(13))
	label.clip_text = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.custom_minimum_size.x = _scaled(72.0)
	return label


func _on_paint_changed() -> void:
	var on: bool = _paint != null and _paint.active
	if _paint_toggle != null:
		_paint_toggle.set_pressed_no_signal(on)
	if _model_body != null:
		_model_body.visible = not on
	if _paint_body != null:
		_paint_body.visible = on
	clip_contents = on
	custom_minimum_size.y = _scaled(SlabPaint.PAINT_HEIGHT if on else PANEL_HEIGHT)
	if _status != null:
		_status.autowrap_mode = TextServer.AUTOWRAP_OFF if on else TextServer.AUTOWRAP_WORD_SMART
		_status.clip_text = on
		_status.max_lines_visible = 1 if on else -1
	if _brush_color != null and _paint != null:
		_brush_color.color = _paint.brush_color
	update_minimum_size()
	_refresh_paint_chrome()


func _refresh_paint_chrome() -> void:
	if _paint_face == null:
		return
	var face_text := "none"
	if _selection != null and not _selection.ids.is_empty():
		face_text = str(_selection.ids[0])
	_paint_face.text = "Face: %s" % face_text
	var mat_text := "none"
	if _paint != null and _paint.slot() >= 0:
		var mat: Variant = _paint.material()
		mat_text = _paint.material_label(mat, _paint.slot())
		if mat is StandardMaterial3D and _paint.is_owned(mat):
			mat_text += " (unique)"
	_paint_mat.text = "Material: %s" % mat_text
	_paint_dirty.text = _paint.save_status() if _paint != null else ""
	if _paint_tool_uv != null and _paint != null:
		_paint_tool_uv.set_pressed_no_signal(_paint.tool == SlabPaint.Tool.MATERIAL_UV)
		_style_tool(_paint_tool_uv, _paint.tool == SlabPaint.Tool.MATERIAL_UV)
	if _paint_tool_pixel != null and _paint != null:
		_paint_tool_pixel.set_pressed_no_signal(_paint.tool == SlabPaint.Tool.PIXEL)
		_style_tool(_paint_tool_pixel, _paint.tool == SlabPaint.Tool.PIXEL)
	if _paint_uv_hint != null:
		_paint_uv_hint.text = SlabPaint.uv_canvas_hint()
		_paint_uv_hint.visible = _paint != null and not _paint.is_pixel()
	if _paint_uv_controls != null:
		_paint_uv_controls.visible = _paint != null and not _paint.is_pixel()
	if _paint != null:
		_set_spin(&"paint_uv_repeat_u", _actions.uv_scale.x)
		_set_spin(&"paint_uv_repeat_v", _actions.uv_scale.y)
		_set_spin(&"paint_uv_offset_u", _actions.uv_offset.x)
		_set_spin(&"paint_uv_offset_v", _actions.uv_offset.y)
		_set_spin(&"paint_uv_rotation", _actions.uv_rotation_degrees)
	if _paint_picker != null and is_instance_valid(_paint_picker) and _paint != null:
		if _paint_picker.has_method("set_edited_resource"):
			_paint_picker.set("edited_resource", _paint.material())
			_compact_resource_preview(_paint_picker)
	if _unique_button != null:
		var allowed: bool = _paint != null and _paint.can_make_unique()
		_unique_button.disabled = not allowed
		_unique_button.tooltip_text = "Copies this solid's material so painting does not rewrite shared tiles." if allowed else "Select a face, then Make Unique so the copy attaches to that face."
	_refresh_paint_palette()


func _refresh_paint_palette() -> void:
	if _paint_chips == null:
		return
	for child in _paint_chips.get_children():
		_paint_chips.remove_child(child)
		child.queue_free()
	if _selection == null or _selection.solid == null:
		var hint := Label.new()
		hint.text = "Select a solid to paint."
		hint.add_theme_font_size_override("font_size", _font(15))
		_paint_chips.add_child(hint)
		return
	var mats: Array = _selection.solid.get("materials")
	var thumb_px: int = maxi(16, int(_scaled(CHIP_SIZE.x)))
	for i in mats.size():
		var chip := Button.new()
		chip.name = "paint_material_%d" % i
		chip.toggle_mode = true
		chip.button_pressed = _actions != null and i == _actions.material_slot
		var label: String = _paint.material_label(mats[i], i) if _paint != null else "Slot %d" % i
		var text_w: float = _paint_chip_text_width(label)
		chip.custom_minimum_size = Vector2(
			maxf(_scaled(110.0), float(thumb_px) + _scaled(16.0) + text_w),
			_scaled(CHIP_SIZE.y)
		)
		chip.focus_mode = Control.FOCUS_NONE
		chip.clip_text = true
		chip.clip_contents = true
		chip.expand_icon = false
		chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
		chip.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		chip.add_theme_constant_override("icon_max_width", thumb_px)
		chip.add_theme_font_size_override("font_size", _font(11))
		var chip_style := _paint_chip_style()
		chip.add_theme_stylebox_override("normal", chip_style)
		chip.add_theme_stylebox_override("hover", chip_style)
		chip.add_theme_stylebox_override("pressed", chip_style)
		chip.text = label
		chip.tooltip_text = label
		if _paint != null:
			chip.icon = _paint.thumbnail(mats[i], thumb_px)
		chip.pressed.connect(func() -> void:
			_actions.material_slot = i
			if _paint:
				_paint.rebind()
		)
		_paint_chips.add_child(chip)


func _paint_chip_text_width(label: String) -> float:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return maxf(48.0, float(label.length()) * 7.0)
	return font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _font(11)).x


func _paint_chip_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.16, 0.16, 0.16)
	box.set_corner_radius_all(3)
	box.content_margin_left = 4
	box.content_margin_right = 6
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


func _style_tool(button: Button, pressed: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = ACCENT if pressed else Color(0.2, 0.2, 0.2)
	box.set_corner_radius_all(3)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	if pressed:
		box.border_width_bottom = 2
		box.border_color = Color(0.12, 0.1, 0.06)
	button.add_theme_stylebox_override("normal", box)
	button.add_theme_stylebox_override("pressed", box)
	button.add_theme_stylebox_override("hover", box)
	button.add_theme_color_override("font_color", Color(0.12, 0.1, 0.06) if pressed else Color(0.86, 0.86, 0.82))
	button.add_theme_color_override("font_pressed_color", Color(0.12, 0.1, 0.06))
	button.add_theme_color_override("font_hover_color", Color(0.12, 0.1, 0.06) if pressed else Color(0.95, 0.95, 0.9))


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


func _sync_loop_values() -> void:
	if _settings_fields == null:
		return
	for spin in _spins_under(_settings_fields):
		if spin.get_parent().name == "loop_count":
			spin.set_value_no_signal(_actions.loop_count)
		elif spin.get_parent().name == "loop_position":
			spin.set_value_no_signal(_actions.loop_position * 100.0)
