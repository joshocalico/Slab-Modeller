@tool
extends VBoxContainer

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPaintCanvas := preload("res://addons/slab/slab_paint_canvas.gd")
const SlabPaint := preload("res://addons/slab/slab_paint.gd")
const SlabKeybindProfiles := preload("res://addons/slab/slab_keybind_profiles.gd")
const SlabUVModeStrip := preload("res://addons/slab/slab_uv_mode_strip.gd")

enum Workspace { MODELLING, UV, PAINT }

const BUTTON_HEIGHT := 36.0
const SPIN_WIDTH := 104.0
const PANEL_HEIGHT := 240.0
const GRID_SEPARATION := 4.0
const ACCENT := Color(0.86, 0.72, 0.34)
const APPLY_PRIMARY := Color(1.0, 0.773, 0.0)  # Brand yellow #FFC500
const CHIP_SIZE := Vector2(28.0, 28.0)
const PAINT_PALETTE_HEIGHT := 40.0
const PAINT_ROW_HEIGHT := 28.0
const PAINT_PICKER_HEIGHT := 64.0
const PAINT_PICKER_WIDTH := 220.0
const PAINT_UV_ROW_HEIGHT := 44.0
const PAINT_CANVAS_MIN_HEIGHT := 190.0

var _selection: RefCounted
var _actions: RefCounted
var _metrics: RefCounted
var _scene_root_getter: Callable
var _status: Label
var _selection_context: Label
var _last_report := ""
var _command_column: VBoxContainer
var _settings: VBoxContainer
var _settings_column: VBoxContainer
var _settings_fields: HFlowContainer
var _buttons: Dictionary = {}
var _create_group: ButtonGroup
var _create_focus: StringName = &"make_box"
var _create_strip: VBoxContainer
var _create_chips: HFlowContainer
var _create_fields: HFlowContainer
var _create_button: Button
# Mode.OBJECT is 0, so -1 means the command column has never been built.
var _built_mode: int = -1
var _expanded_sections: Dictionary = {}
var _settings_title: Label
var _undo_hook: Object = null
var _paint: RefCounted
var _workspace: int = Workspace.MODELLING
var _model_body: BoxContainer
var _paint_body: Control
var _uv_toggle: Button
var _paint_toggle: Button
var _paint_canvas: Control
var _paint_brush: Control
var _paint_face: Label
var _paint_mat: Label
var _paint_dirty: Label
var _paint_palette: ScrollContainer
var _paint_chips: HBoxContainer
var _paint_tool_uv: Button
var _paint_tool_pixel: Button
var _unique_button: Button
var _paint_assign: Button
var _paint_save: Button
var _paint_resize: Button
var _paint_resize_form: VBoxContainer
var _paint_resize_width: SpinBox
var _paint_resize_height: SpinBox
var _paint_resize_aspect: CheckBox
var _paint_resize_sampling: OptionButton
var _paint_resize_target: StandardMaterial3D
var _paint_resize_ratio := 1.0
var _paint_resize_sync := false
var _paint_sample: Button
var _paint_actions: VBoxContainer
var _paint_action_tools: VBoxContainer
var _paint_inspector: ScrollContainer
var _paint_inspector_fields: VBoxContainer
var _paint_help: Label
var _paint_picker_wrap: Control
var _paint_picker: Node
var _paint_uv_hint: Label
var _paint_fit_uv: Button
var _paint_uv_controls: Control
var _uv_mode_strip: Control
var _paint_mapping_controls: Control
var _paint_mapping_grid: GridContainer
var _paint_mapping_title: Label
var _paint_mapping_state: Label
var _paint_density_row: Control
var _paint_unwrap: Button
var _paint_texture_px_label: Label
var _paint_texture_px_spin: SpinBox
var _brush_radius: SpinBox
var _brush_opacity: SpinBox
var _brush_color: ColorPickerButton
var _overlay_opacity: SpinBox
var _flatten_button: Button
var _channel_label: Label
var _channel_picker: HBoxContainer
var _layer_list: VBoxContainer
var _add_layer_button: Button
var _delete_layer_button: Button
var _keybind_dropdown: OptionButton
var _selection_controls: Control
var _operation_row: Control
var _loop_action_group: HBoxContainer
var _loop_apply: Button
var _loop_cancel: Button
var _named_solids: Array[Node] = []


func setup(selection: RefCounted, actions: RefCounted, metrics: RefCounted = null, scene_root_getter: Callable = Callable()) -> void:
	_selection = selection
	_actions = actions
	_scene_root_getter = scene_root_getter
	_actions.loop_values_updated.connect(_sync_loop_values)
	_actions.loop_state_changed.connect(_sync_loop_controls)
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
	_selection_controls = preload("res://addons/slab/slab_selection_controls.gd").new()
	_selection_controls.setup(_selection, _metrics, _scene_root_getter)
	add_child(_selection_controls)
	_operation_row = _operation_controls()
	add_child(_operation_row)
	add_child(_status)
	_model_body = BoxContainer.new()
	_model_body.name = "ModelBody"
	_model_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_model_body.add_theme_constant_override("separation", 8)
	_model_body.add_child(_command_scroll())
	_model_body.add_child(_build_settings_column())
	_model_body.resized.connect(_layout_model)
	add_child(_model_body)
	_paint_body = _paint_block()
	_paint_body.visible = false
	add_child(_paint_body)

	_selection.changed.connect(_on_selection_changed)
	_actions.reported.connect(_on_reported)
	_actions.status_reset_requested.connect(_reset_status)
	_watch_selected_names()
	refresh()
	_layout_model()


func _layout_model() -> void:
	var stacked: bool = _model_body.size.x < _scaled(850.0)
	_model_body.vertical = stacked
	if _settings_column != null:
		_settings_column.custom_minimum_size.x = 0.0 if stacked else _scaled(300.0)
		_settings_column.size_flags_horizontal = Control.SIZE_FILL


func _operation_controls() -> Control:
	var card := VBoxContainer.new()
	card.name = "OperationHandles"
	card.add_theme_constant_override("separation", int(_scaled(6)))

	var title := Label.new()
	title.name = "OpCardTitle"
	title.add_theme_font_size_override("font_size", _font(16))
	title.add_theme_color_override("font_color", ACCENT)
	card.add_child(title)

	var settings_row := HFlowContainer.new()
	settings_row.name = "OpCardSettings"
	settings_row.add_theme_constant_override("h_separation", int(_scaled(8)))

	var amount_label := Label.new()
	amount_label.add_theme_font_size_override("font_size", _font(14))
	amount_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.74))
	settings_row.add_child(amount_label)

	var amount := SpinBox.new()
	amount.name = "HandleAmount"
	amount.min_value = -64.0
	amount.max_value = 64.0
	amount.step = 0.001
	amount.suffix = "m"
	amount.custom_minimum_size.x = _scaled(110)
	amount.add_theme_font_size_override("font_size", _font(14))
	amount.get_line_edit().add_theme_font_size_override("font_size", _font(14))
	settings_row.add_child(amount)

	var segment_label := Label.new()
	segment_label.text = "Segments"
	segment_label.add_theme_font_size_override("font_size", _font(14))
	segment_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.74))
	settings_row.add_child(segment_label)

	var segments := SpinBox.new()
	segments.name = "bevel_segments"
	segments.min_value = 1
	segments.max_value = 16
	segments.step = 1
	segments.custom_minimum_size.x = _scaled(80)
	segments.add_theme_font_size_override("font_size", _font(14))
	segments.get_line_edit().add_theme_font_size_override("font_size", _font(14))
	settings_row.add_child(segments)

	card.add_child(settings_row)

	var commit_strip := HBoxContainer.new()
	commit_strip.name = "OpCardCommit"
	commit_strip.add_theme_constant_override("separation", int(_scaled(8)))

	var pending_text := {"distance": false, "segments": false}
	var synced := {"distance": NAN, "segments": -1, "op_id": "", "active": false}

	amount.get_line_edit().gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and amount.get_line_edit().has_focus():
			pending_text["distance"] = true)
	amount.value_changed.connect(func(value: float) -> void:
		if _actions.op_session_active():
			_actions.op_session_set_value("distance", value)
		else:
			_actions.operation_amount_changed.emit(value))

	segments.get_line_edit().gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and segments.get_line_edit().has_focus():
			pending_text["segments"] = true)
	segments.value_changed.connect(func(value: float) -> void:
		if _actions.op_session_active():
			_actions.op_session_set_value("segments", int(value))
		else:
			_actions.operation_segments_changed.emit(int(value)))

	var cancel_button := Button.new()
	cancel_button.name = "OpCardCancel"
	cancel_button.text = "Cancel"
	cancel_button.accessibility_name = "Cancel"
	cancel_button.set_meta("slab_label", "Cancel")
	cancel_button.add_theme_font_size_override("font_size", _font(14))
	cancel_button.tooltip_text = "Discard this preview. Escape also cancels."
	cancel_button.accessibility_description = cancel_button.tooltip_text
	cancel_button.pressed.connect(func() -> void:
		cancel_button.release_focus()
		_actions.op_session_cancel())
	commit_strip.add_child(cancel_button)

	var apply_button := Button.new()
	apply_button.name = "OpCardApply"
	apply_button.text = "Apply"
	apply_button.accessibility_name = "Apply"
	apply_button.set_meta("slab_label", "Apply")
	apply_button.add_theme_font_size_override("font_size", _font(14))
	apply_button.tooltip_text = "Commit this preview as one undoable edit. Enter also applies."
	apply_button.accessibility_description = apply_button.tooltip_text
	apply_button.pressed.connect(func() -> void:
		apply_button.release_focus()
		var distance_pending: bool = pending_text["distance"]
		var segments_pending: bool = pending_text["segments"]
		amount.set_block_signals(true)
		segments.set_block_signals(true)
		if distance_pending: amount.apply()
		if segments_pending: segments.apply()
		var wanted_distance: float = amount.value if distance_pending else _actions.operation_amount
		var wanted_segments: int = int(segments.value) if segments_pending else _actions.bevel_segments
		var bevel: bool = _actions.op_session_id() == "bevel"
		amount.set_block_signals(false)
		segments.set_block_signals(false)
		if distance_pending: _actions.op_session_set_value("distance", wanted_distance)
		if bevel and segments_pending: _actions.op_session_set_value("segments", wanted_segments)
		_actions.op_session_apply())
	commit_strip.add_child(apply_button)

	card.add_child(commit_strip)

	var style_apply := func(enabled: bool) -> void:
		if enabled:
			var box := StyleBoxFlat.new()
			box.bg_color = APPLY_PRIMARY
			box.set_corner_radius_all(3)
			box.content_margin_left = 10
			box.content_margin_right = 10
			box.content_margin_top = 4
			box.content_margin_bottom = 4
			apply_button.add_theme_stylebox_override("normal", box)
			var hover := box.duplicate() as StyleBoxFlat
			hover.bg_color = APPLY_PRIMARY.lightened(0.1)
			apply_button.add_theme_stylebox_override("hover", hover)
			var pressed := box.duplicate() as StyleBoxFlat
			pressed.bg_color = APPLY_PRIMARY.darkened(0.1)
			apply_button.add_theme_stylebox_override("pressed", pressed)
			apply_button.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
			apply_button.add_theme_color_override("font_hover_color", Color(0.1, 0.1, 0.1))
			apply_button.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.1))
		else:
			apply_button.remove_theme_stylebox_override("normal")
			apply_button.remove_theme_stylebox_override("hover")
			apply_button.remove_theme_stylebox_override("pressed")
			apply_button.remove_theme_color_override("font_color")
			apply_button.remove_theme_color_override("font_hover_color")
			apply_button.remove_theme_color_override("font_pressed_color")

	var sync := func() -> void:
		var active: bool = _actions.op_session_active()
		var was_visible: bool = card.visible
		card.visible = (_paint == null or not _paint.active) and active
		var op_id: String = _actions.op_session_id()
		var lifecycle_changed: bool = active != synced["active"] or op_id != synced["op_id"]

		if lifecycle_changed or not is_equal_approx(float(synced["distance"]), _actions.operation_amount):
			pending_text["distance"] = false
		if lifecycle_changed or int(synced["segments"]) != _actions.bevel_segments:
			pending_text["segments"] = false

		title.text = _actions.op_session_title()
		var fields: Array = _actions.op_session_fields()
		var distance_field: Dictionary = {}
		for field in fields:
			if field["id"] == "distance":
				distance_field = field
				break
		amount_label.text = distance_field.get("label", "Distance")
		segment_label.visible = active and op_id == "bevel"
		segments.visible = active and op_id == "bevel"

		if not pending_text["segments"]:
			segments.set_value_no_signal(_actions.bevel_segments)
		amount.set_block_signals(true)
		amount.min_value = float(distance_field.get("min", -64.0))
		amount.max_value = float(distance_field.get("max", 64.0))
		if not pending_text["distance"]:
			amount.set_value_no_signal(_actions.operation_amount)
		amount.set_block_signals(false)

		synced["distance"] = _actions.operation_amount
		synced["segments"] = _actions.bevel_segments
		synced["op_id"] = op_id
		synced["active"] = active

		var valid: bool = _actions.op_session_apply_enabled()
		apply_button.disabled = not valid
		style_apply.call(valid)

		if _settings != null:
			_settings.visible = _show_settings()
		_sync_model_chrome()
		_refresh_buttons()

	_selection.changed.connect(sync)
	_actions.operation_state_changed.connect(sync)
	sync.call()
	return card


func _show_settings() -> bool:
	if _selection.mode == SlabSelection.Mode.FACE:
		return not _selection.ids.is_empty() and _actions.snap_align_active and not _actions.operation_active
	if _selection.mode == SlabSelection.Mode.OBJECT:
		var has_tool: bool = _actions.snap_align_active or _actions.array_active or _actions.plane_active
		var has_boolean: bool = _selection.objects.size() == 2
		return not _actions.operation_active and (has_tool or has_boolean)
	return not _actions.operation_active and (_selection.mode != SlabSelection.Mode.VERTEX or _selection.ids.size() >= 2 or _actions.snap_align_active)


func _get_minimum_size() -> Vector2:
	var min_size := Vector2(0.0, _scaled(PANEL_HEIGHT))
	if _paint != null and _paint.active:
		min_size.y = maxf(_scaled(SlabPaint.PAINT_HEIGHT), _paint_workspace_minimum_height())
	return min_size


func _paint_workspace_minimum_height() -> float:
	var height := 0.0
	var count := 0
	for child in get_children():
		if child is Control and (child as Control).visible:
			height += _paint_body_maximum_tool_minimum_height() if child == _paint_body else (child as Control).get_combined_minimum_size().y
			count += 1
	return height + maxf(0, count - 1) * get_theme_constant("separation")


func _paint_body_maximum_tool_minimum_height() -> float:
	var height := 0.0
	var count := 0
	for child in _paint_body.get_children():
		if child is Control:
			var child_height := (child as Control).get_combined_minimum_size().y
			height += child_height
			count += 1
	return height + maxf(0, count - 1) * _paint_body.get_theme_constant("separation")


func bind_paint(paint: RefCounted) -> void:
	_paint = paint
	if _paint != null and _paint.has_signal("changed"):
		if not _paint.changed.is_connected(_on_paint_changed):
			_paint.changed.connect(_on_paint_changed)
	if _paint != null and _paint.has_signal("reported"):
		if not _paint.reported.is_connected(_on_reported):
			_paint.reported.connect(_on_reported)
	if _paint != null and _paint.has_signal("channel_changed"):
		if not _paint.channel_changed.is_connected(_on_channel_changed):
			_paint.channel_changed.connect(_on_channel_changed)
	if _paint != null and _paint.has_signal("layers_changed"):
		if not _paint.layers_changed.is_connected(_refresh_layer_list):
			_paint.layers_changed.connect(_refresh_layer_list)
	if _paint_canvas != null:
		_paint_canvas.setup(_paint, _metrics)
		_paint_canvas.custom_minimum_size.y = _scaled(PAINT_CANVAS_MIN_HEIGHT)
	_on_paint_changed()


func _on_channel_changed() -> void:
	_sync_channel_picker()
	_refresh_layer_list()
	_refresh_paint_chrome()


func _sync_channel_picker() -> void:
	if _channel_picker == null or _paint == null:
		return
	var current_ch: int = _paint.channel
	for i in _channel_picker.get_child_count():
		var btn: Button = _channel_picker.get_child(i) as Button
		if btn == null:
			continue
		var expected_pressed: bool = false
		match i:
			0: expected_pressed = current_ch == SlabPaint.Channel.ALBEDO
			1: expected_pressed = current_ch == SlabPaint.Channel.ROUGHNESS
			2: expected_pressed = current_ch == SlabPaint.Channel.EMISSION
		if btn.button_pressed != expected_pressed:
			btn.set_pressed_no_signal(expected_pressed)
	if _channel_label != null:
		_channel_label.text = _paint.current_channel_name()


func _refresh_layer_list() -> void:
	if _layer_list == null:
		return
	for child in _layer_list.get_children():
		_layer_list.remove_child(child)
		child.queue_free()
	if _paint == null:
		return
	var layers: Array[Dictionary] = _paint.all_layers_info()
	for layer_info: Dictionary in layers:
		var row := _create_layer_row(layer_info)
		_layer_list.add_child(row)
	if _delete_layer_button != null:
		_delete_layer_button.disabled = layers.size() <= 1


func _create_layer_row(info: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Layer%d" % info.index
	row.add_theme_constant_override("separation", 2)
	row.custom_minimum_size.y = _scaled(22.0)
	
	var vis_btn := Button.new()
	vis_btn.name = "LayerVis%d" % info.index
	vis_btn.text = "👁" if info.visible else "○"
	vis_btn.toggle_mode = true
	vis_btn.button_pressed = info.visible
	vis_btn.tooltip_text = "Toggle layer visibility"
	vis_btn.add_theme_font_size_override("font_size", _font(10))
	vis_btn.custom_minimum_size = Vector2(_scaled(20.0), _scaled(20.0))
	var layer_idx: int = info.index
	vis_btn.toggled.connect(func(pressed: bool) -> void:
		if _paint:
			_paint.set_layer_visible(layer_idx, pressed)
	)
	row.add_child(vis_btn)
	
	var name_btn := Button.new()
	name_btn.name = "LayerName%d" % info.index
	name_btn.text = info.name
	name_btn.flat = true
	name_btn.toggle_mode = true
	name_btn.button_pressed = info.active
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.add_theme_font_size_override("font_size", _font(11))
	name_btn.tooltip_text = "Click to select this layer"
	if info.active:
		name_btn.add_theme_color_override("font_color", Color(0.92, 0.78, 0.28))
	name_btn.pressed.connect(func() -> void:
		if _paint:
			_paint.set_active_layer(layer_idx)
	)
	row.add_child(name_btn)
	
	return row


func bind_undo(undo: Object) -> void:
	if _undo_hook != null and _undo_hook.has_signal("version_changed"):
		if _undo_hook.version_changed.is_connected(_refresh_soon):
			_undo_hook.version_changed.disconnect(_refresh_soon)
	_undo_hook = undo
	if _undo_hook != null and _undo_hook.has_signal("version_changed"):
		_undo_hook.version_changed.connect(_refresh_soon)


func _refresh_soon() -> void:
	# Clear the previous result immediately. A newly committed command can
	# report its result after this signal, before the deferred refresh runs.
	_last_report = ""
	call_deferred("refresh")


func _scaled(value: float) -> float:
	return _metrics.px(value)


func _font(px: int) -> int:
	return _metrics.font(px)


func refresh() -> void:
	_sync_model_chrome()
	var mode: int = _selection.mode
	if _built_mode != mode:
		_rebuild_commands(_actions.command_sections_for(mode))
		_built_mode = mode
		_refresh_settings()
	_refresh_buttons()
	_settings.visible = _show_settings()
	_refresh_create_strip_visibility()
	_refresh_selection_context()
	set_status(_last_report if _last_report != "" else _selection.describe())
	if _paint != null and _paint.active:
		_refresh_paint_chrome()


func focus_create(id: StringName) -> void:
	if not _actions.shapes.CATALOG.has(id):
		return
	if _create_focus == id:
		_sync_create_pressed()
		_actions.create_settings_changed.emit()
		return
	_create_focus = id
	if _selection.mode == SlabSelection.Mode.OBJECT:
		_refresh_settings()
	_sync_create_pressed()
	_actions.create_settings_changed.emit()


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
	for child in _create_chips.get_children():
		_create_chips.remove_child(child)
		child.free()
	for section in sections:
		var heading: String = section["heading"]
		if heading == SlabActions.SECTION_CREATE:
			for row in section["rows"]:
				_create_chips.add_child(_action_button(row))
			continue
		var flow := _section_flow(section["rows"])
		if heading == SlabActions.SECTION_SELECTION:
			_command_column.add_child(_section_toggle(heading, flow))
		else:
			_command_column.add_child(_section_label(heading))
		_command_column.add_child(flow)
	_sync_create_pressed()


func _refresh_buttons() -> void:
	for id in _buttons:
		var button: Button = _buttons[id]
		var row: Dictionary = _actions.find(id)
		var reason: String = _actions.disabled_reason(row)
		button.disabled = reason != ""
		button.tooltip_text = reason if reason != "" else _tooltip_of(row)


func _refresh_settings() -> void:
	_loop_action_group = null
	_loop_apply = null
	_loop_cancel = null
	_settings.visible = _show_settings()
	for spin in _spins_under(_settings_fields):
		spin.apply()
		if not spin.is_inside_tree():
			spin.value_changed.emit(spin.value)
	for child in _settings_fields.get_children():
		_settings_fields.remove_child(child)
		child.queue_free()
	_refresh_create_strip()
	var mode: int = _selection.mode
	if mode == SlabSelection.Mode.OBJECT:
		var has_tool_active: bool = _actions.snap_align_active or _actions.array_active or _actions.plane_active
		var has_boolean: bool = _selection.objects.size() == 2 and not has_tool_active
		if has_tool_active:
			_settings_title.text = "Snap to Vertex" if _actions.snap_align_active else ("Array" if _actions.array_active else "Plane Cut")
			_settings_title.visible = true
		elif has_boolean:
			_settings_title.text = "Boolean operands"
			_settings_title.visible = true
		else:
			_settings_title.visible = false
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
		elif has_boolean:
			_add_boolean_operands()
	elif mode == SlabSelection.Mode.FACE:
		if _actions.snap_align_active:
			_settings_title.text = "Align Face"
			_settings_title.visible = true
			_add_snap_align_settings()
		else:
			_settings_title.visible = false
	else:
		_settings_title.text = "Snap to Vertex" if _actions.snap_align_active else ("Weld" if mode == SlabSelection.Mode.VERTEX else "Loop cut")
		_settings_title.visible = true
		if _actions.snap_align_active:
			_add_snap_align_settings()
		elif mode == SlabSelection.Mode.VERTEX:
			_settings_fields.add_child(_spin("Weld distance", SlabActions.AMOUNT_FLOOR, SlabActions.AMOUNT_CEILING, 0.05, _clamped_amount(), func(v: float) -> void:
				_actions.amount = v
			, "", &"amount"))
	if mode == SlabSelection.Mode.EDGE and not _actions.snap_align_active:
		_settings_fields.add_child(_spin("Cuts", 1, 32, 1, _actions.loop_count, func(v: float) -> void:
			_actions.loop_count = int(v)
			_actions.loop_settings_changed.emit()
		, "Number of evenly spaced loop cuts.", &"loop_count"))
		_settings_fields.add_child(_spin("Centre %", 0.1, 99.9, 0.1, _actions.loop_position * 100.0, func(v: float) -> void:
			_actions.loop_position = v / 100.0
			_actions.loop_settings_changed.emit()
		, "Centre of the loop group as a percentage along the starting edge.", &"loop_position"))
		_loop_action_group = HBoxContainer.new()
		_loop_action_group.name = "LoopActions"
		_loop_action_group.add_theme_constant_override("separation", int(_scaled(GRID_SEPARATION)))
		_loop_apply = _named_action("Apply", "Apply", "Apply the loop preview as one undoable edit.", _apply_loop_preview)
		_loop_apply.name = "LoopApply"
		_loop_action_group.add_child(_loop_apply)
		_loop_cancel = _named_action("Cancel", "Clear", "Discard the loop preview and keep the original solid.", func() -> void:
			_actions.loop_cancel_requested.emit()
		)
		_loop_cancel.name = "LoopCancel"
		_loop_action_group.add_child(_loop_cancel)
		_settings_fields.add_child(_loop_action_group)
		_sync_loop_controls()


func _add_boolean_operands() -> void:
	var operands := VBoxContainer.new()
	operands.name = "BooleanOperands"
	operands.custom_minimum_size.x = _scaled(240.0)
	operands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	operands.add_theme_constant_override("separation", int(_scaled(3.0)))
	for role in [["Target", _selection.objects[0]], ["Second solid", _selection.objects[1]]]:
		var label := Label.new()
		label.text = "%s: %s" % [role[0], role[1].name]
		label.tooltip_text = label.text + (" (this solid receives the result)" if role[0] == "Target" else " (this is the cutter for Subtract)")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", _font(13))
		operands.add_child(label)
	var swap := _named_action("Swap operands", "Reload", "Exchange which selected solid receives the Boolean result. The second solid is the cutter for Subtract.", _actions.swap_boolean_operands)
	swap.name = "SwapBooleanOperands"
	operands.add_child(swap)
	_settings_fields.add_child(operands)


func _refresh_create_strip_visibility() -> void:
	if _create_strip == null:
		return
	var mode: int = _selection.mode
	var is_object_mode: bool = mode == SlabSelection.Mode.OBJECT
	var painting: bool = _paint != null and _paint.active
	_create_strip.visible = is_object_mode and not painting
	if _create_button != null:
		var tool_blocks_create: bool = _actions.array_active or _actions.plane_active or _actions.snap_align_active
		_create_button.disabled = tool_blocks_create
		if tool_blocks_create:
			_create_button.tooltip_text = "Finish or cancel the active tool first."
		else:
			_create_button.tooltip_text = "Preview the selected shape in the viewport, then click or press Enter to place it."


func _refresh_create_strip() -> void:
	if _create_strip == null or _create_fields == null or _create_button == null:
		return
	for spin in _spins_under(_create_fields):
		spin.apply()
		if not spin.is_inside_tree():
			spin.value_changed.emit(spin.value)
	for child in _create_fields.get_children():
		_create_fields.remove_child(child)
		child.queue_free()
	_refresh_create_strip_visibility()
	var mode: int = _selection.mode
	var is_object_mode: bool = mode == SlabSelection.Mode.OBJECT
	var painting: bool = _paint != null and _paint.active
	if not is_object_mode or painting:
		return
	for field in _actions.shapes.fields_for(_create_focus):
		_create_fields.add_child(_shape_spin(field))


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


func _create_label() -> String:
	for entry in _actions.shapes.entries():
		if StringName(entry["id"]) == _create_focus:
			return str(entry["label"])
	return "solid"


func _clamped_amount() -> float:
	return clampf(absf(_actions.amount), SlabActions.AMOUNT_FLOOR, SlabActions.AMOUNT_CEILING)


func _section_toggle(heading: String, flow: Control) -> Button:
	var button := Button.new()
	button.name = "Section" + heading
	button.toggle_mode = true
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.y = _scaled(28.0)
	button.add_theme_font_size_override("font_size", _font(16))
	var caption := heading
	button.accessibility_name = caption + " commands"
	var sync := func(open: bool) -> void:
		button.text = ("▾  " if open else "▸  ") + caption
		button.accessibility_description = "Expanded. Activate to collapse." if open else "Collapsed. Activate to expand."
		button.tooltip_text = "Hide %s controls." % caption if open else "Show %s controls. Keyboard shortcuts also work while collapsed." % caption
		flow.visible = open
	button.set_pressed_no_signal(_expanded_sections.get(heading, false))
	sync.call(button.button_pressed)
	button.toggled.connect(func(open: bool) -> void:
		_expanded_sections[heading] = open
		sync.call(open)
		_settings.visible = _show_settings()
	)
	return button


func _shape_spin(field: Dictionary) -> Control:
	var key: StringName = field["key"]
	return _spin(field["label"], field["min"], field["max"], field["step"], field["value"], func(v: float) -> void:
		if is_equal_approx(_actions.shapes.value_of(key), v):
			return
		_actions.shapes.set_value(key, v)
		_actions.create_settings_changed.emit()
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
	if _paint != null and _paint.active:
		_refresh_paint_chrome()


func _on_selection_changed() -> void:
	_watch_selected_names()
	_last_report = ""
	if _selection.mode == SlabSelection.Mode.OBJECT:
		_refresh_settings()
	refresh()


func _watch_selected_names() -> void:
	for solid in _named_solids:
		if is_instance_valid(solid) and solid.renamed.is_connected(_on_selected_renamed):
			solid.renamed.disconnect(_on_selected_renamed)
	_named_solids.clear()
	for solid in _selection.objects:
		if is_instance_valid(solid):
			_named_solids.append(solid)
			solid.renamed.connect(_on_selected_renamed)


func _on_selected_renamed() -> void:
	if not _actions.operation_active:
		_last_report = ""
	_refresh_settings()
	refresh()


func _exit_tree() -> void:
	for solid in _named_solids:
		if is_instance_valid(solid) and solid.renamed.is_connected(_on_selected_renamed):
			solid.renamed.disconnect(_on_selected_renamed)
	_named_solids.clear()


func _reset_status() -> void:
	_last_report = ""
	set_status(_selection.describe())


func _sync_edit_fields() -> void:
	_set_spin(&"amount", _actions.amount)


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
	row.add_child(VSeparator.new())
	_uv_toggle = Button.new()
	_uv_toggle.name = "UVWorkspace"
	_uv_toggle.text = "UV"
	_uv_toggle.toggle_mode = true
	_uv_toggle.focus_mode = Control.FOCUS_ALL
	_uv_toggle.tooltip_text = "Open the UV workspace for unwrapping and material placement. Escape closes it."
	_uv_toggle.accessibility_name = "UV workspace"
	_uv_toggle.accessibility_description = _uv_toggle.tooltip_text
	_uv_toggle.add_theme_font_size_override("font_size", _font(15))
	_uv_toggle.custom_minimum_size.y = _scaled(BUTTON_HEIGHT)
	_uv_toggle.pressed.connect(_toggle_uv_workspace)
	row.add_child(_uv_toggle)
	_paint_toggle = Button.new()
	_paint_toggle.name = "PaintWorkspace"
	_paint_toggle.text = "Paint"
	_paint_toggle.toggle_mode = true
	_paint_toggle.focus_mode = Control.FOCUS_ALL
	_paint_toggle.tooltip_text = "Open the pixel Paint workspace. Escape closes it."
	_paint_toggle.accessibility_name = "Paint workspace"
	_paint_toggle.accessibility_description = _paint_toggle.tooltip_text
	_paint_toggle.add_theme_font_size_override("font_size", _font(15))
	_paint_toggle.custom_minimum_size.y = _scaled(BUTTON_HEIGHT)
	_paint_toggle.pressed.connect(_toggle_paint_workspace)
	row.add_child(_paint_toggle)
	row.add_child(VSeparator.new())
	_keybind_dropdown = _build_keybind_dropdown()
	row.add_child(_keybind_dropdown)
	_selection_context = Label.new()
	_selection_context.name = "SelectionContext"
	_selection_context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_context.custom_minimum_size.x = 0.0
	_selection_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_selection_context.autowrap_mode = TextServer.AUTOWRAP_OFF
	_selection_context.clip_text = true
	_selection_context.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_selection_context.add_theme_font_size_override("font_size", _font(14))
	_selection_context.add_theme_color_override("font_color", Color(0.78, 0.78, 0.74))
	row.add_child(_selection_context)
	return row


func _refresh_selection_context() -> void:
	if _selection_context == null:
		return
	_selection_context.text = _selection.compact_description()
	_selection_context.tooltip_text = _selection_context.text


func _build_keybind_dropdown() -> OptionButton:
	var dropdown := OptionButton.new()
	dropdown.name = "KeybindProfile"
	dropdown.focus_mode = Control.FOCUS_ALL
	dropdown.add_theme_font_size_override("font_size", _font(13))
	dropdown.custom_minimum_size.x = _scaled(140.0)
	dropdown.tooltip_text = "Choose a keyboard shortcut profile. Slab is the default; Familiar profiles remap common modelling shortcuts."
	dropdown.accessibility_name = "Keyboard profile"
	dropdown.accessibility_description = dropdown.tooltip_text
	if _actions != null and _actions.keybind_profiles != null:
		for label in _actions.keybind_profiles.all_profile_labels():
			dropdown.add_item(label)
		dropdown.select(_actions.keybind_profiles.profile())
		dropdown.item_selected.connect(_on_keybind_profile_changed)
		_actions.keybind_profiles.profile_changed.connect(func(_p: int) -> void:
			_on_profile_updated()
		)
	return dropdown


func _on_keybind_profile_changed(index: int) -> void:
	if _actions == null or _actions.keybind_profiles == null:
		return
	_actions.keybind_profiles.set_profile(index)
	_on_profile_updated()


func _on_profile_updated() -> void:
	var conflicts: Array[String] = []
	if _actions != null and _actions.keybind_profiles != null:
		conflicts = _actions.keybind_profiles.conflicts_with_godot()
	if not conflicts.is_empty():
		var conflict_msg := "Conflicts with Godot: " + ", ".join(conflicts)
		_actions.reported.emit(conflict_msg)
	_refresh_buttons()


func _build_settings_column() -> Control:
	_settings_column = VBoxContainer.new()
	_settings_column.name = "SettingsColumn"
	_settings_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_column.add_theme_constant_override("separation", 6)
	_create_strip = _build_create_strip()
	_settings_column.add_child(_create_strip)
	_settings_column.add_child(_settings_block())
	return _settings_column


func _settings_block() -> Control:
	_settings = VBoxContainer.new()
	_settings.name = "Settings"
	_settings.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_fields = HFlowContainer.new()
	_settings_fields.name = "SettingsFields"
	_settings_fields.add_theme_constant_override("h_separation", 10)
	_settings_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	content.add_child(_settings_fields)
	scroll.add_child(content)
	_settings.add_child(scroll)
	return _settings


func _build_create_strip() -> VBoxContainer:
	var strip := VBoxContainer.new()
	strip.name = "CreateStrip"
	strip.add_theme_constant_override("separation", int(_scaled(4)))
	_create_chips = HFlowContainer.new()
	_create_chips.name = "CreateChips"
	_create_chips.add_theme_constant_override("h_separation", int(_scaled(GRID_SEPARATION)))
	_create_chips.add_theme_constant_override("v_separation", int(_scaled(GRID_SEPARATION)))
	_create_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(_create_chips)
	_create_fields = HFlowContainer.new()
	_create_fields.name = "CreateFields"
	_create_fields.add_theme_constant_override("h_separation", 10)
	_create_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(_create_fields)
	_create_button = _named_action("Create", "Add", "Preview the selected shape in the viewport, then click or press Enter to place it.", _create_shape)
	_create_button.name = "CreateShape"
	strip.add_child(_create_button)
	return strip


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
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	label.text = "UV" if text.to_upper() == "UV" else text.capitalize()
	label.add_theme_font_size_override("font_size", _font(16))
	label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.78))
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
	button.accessibility_description = _tooltip_of(row)
	button.add_theme_font_size_override("font_size", _font(15))
	button.custom_minimum_size = Vector2(0.0, _scaled(BUTTON_HEIGHT))
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.set_meta("slab_label", row["label"])
	button.tooltip_text = _tooltip_of(row)
	if _actions.section_of(row) == _actions.SECTION_CREATE:
		button.toggle_mode = true
		button.button_group = _create_group
	button.pressed.connect(func() -> void:
		if _actions.section_of(row) == _actions.SECTION_CREATE:
			focus_create(StringName(id))
		else:
			_actions.run(id)
	)
	_buttons[id] = button
	return button


func _create_shape() -> void:
	for spin in _spins_under(_create_fields):
		spin.apply()
	_actions.request_create_placement(_create_focus)


func _paint_block() -> Control:
	var body := VBoxContainer.new()
	body.name = "PaintBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	body.add_theme_constant_override("separation", 3)
	body.add_child(_paint_target_row())
	var split := HBoxContainer.new()
	split.name = "PaintWorkspaceSplit"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	var inspector_scroll := ScrollContainer.new()
	_paint_inspector = inspector_scroll
	inspector_scroll.name = "PaintInspector"
	inspector_scroll.custom_minimum_size.x = _scaled(350.0)
	inspector_scroll.size_flags_horizontal = Control.SIZE_FILL
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	inspector_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var inspector := VBoxContainer.new()
	_paint_inspector_fields = inspector
	inspector.name = "PaintInspectorFields"
	inspector.custom_minimum_size.x = _scaled(342.0)
	inspector.add_theme_constant_override("separation", 4)
	inspector_scroll.add_child(inspector)
	inspector.add_child(_paint_action_row())
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
	inspector.add_child(_paint_palette)
	_paint_uv_controls = _paint_uv_control_row()
	inspector.add_child(_paint_uv_controls)
	_paint_mapping_controls = _paint_mapping_section()
	inspector.add_child(_paint_mapping_controls)
	_paint_brush = _brush_column()
	inspector.add_child(_paint_brush)
	split.add_child(inspector_scroll)
	var row := HBoxContainer.new()
	row.name = "PaintCanvasRow"
	row.custom_minimum_size.x = _scaled(200.0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.clip_contents = true
	row.add_theme_constant_override("separation", 8)
	_paint_canvas = SlabPaintCanvas.new()
	_paint_canvas.setup(_paint, _metrics, _selection)
	_paint_canvas.custom_minimum_size.y = _scaled(PAINT_CANVAS_MIN_HEIGHT)
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
	_paint_canvas.uv_element_picked.connect(_on_uv_element_picked)
	_paint_uv_hint = Label.new()
	_paint_uv_hint.name = "PaintUvHint"
	_paint_uv_hint.text = SlabPaint.uv_canvas_hint()
	_paint_uv_hint.add_theme_font_size_override("font_size", _font(12))
	_paint_uv_hint.add_theme_color_override("font_color", Color(0.92, 0.86, 0.62, 0.92))
	var hint_bg := StyleBoxFlat.new()
	hint_bg.bg_color = Color(0.04, 0.04, 0.04, 0.82)
	hint_bg.corner_radius_top_left = 3
	hint_bg.corner_radius_top_right = 3
	hint_bg.corner_radius_bottom_left = 3
	hint_bg.corner_radius_bottom_right = 3
	hint_bg.content_margin_left = 5
	hint_bg.content_margin_right = 5
	hint_bg.content_margin_top = 2
	hint_bg.content_margin_bottom = 2
	_paint_uv_hint.add_theme_stylebox_override("normal", hint_bg)
	_paint_uv_hint.clip_text = true
	_paint_uv_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_paint_uv_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	_paint_canvas.add_child(_paint_uv_hint)
	_paint_uv_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_paint_uv_hint.offset_left = 6
	_paint_uv_hint.offset_top = 4
	_paint_uv_hint.offset_right = -104
	_paint_uv_hint.offset_bottom = 28
	_paint_fit_uv = Button.new()
	_paint_fit_uv.name = "PaintFitUv"
	_paint_fit_uv.text = "Fit UV"
	_paint_fit_uv.add_theme_font_size_override("font_size", _font(12))
	_paint_fit_uv.tooltip_text = "Frame the selected faces' complete unwrapped UV outlines."
	_paint_fit_uv.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_paint_canvas.add_child(_paint_fit_uv)
	_paint_fit_uv.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_paint_fit_uv.offset_left = -96
	_paint_fit_uv.offset_top = 3
	_paint_fit_uv.offset_right = -8
	_paint_fit_uv.offset_bottom = 29
	_paint_fit_uv.pressed.connect(_paint_canvas.frame_uv)
	_uv_mode_strip = _build_uv_mode_strip()
	_paint_canvas.add_child(_uv_mode_strip)
	_uv_mode_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_uv_mode_strip.offset_left = 6
	_uv_mode_strip.offset_top = 32
	row.add_child(_paint_canvas)
	split.add_child(row)
	body.add_child(split)
	return body


func _build_uv_mode_strip() -> Control:
	var panel := PanelContainer.new()
	panel.name = "UVModeStrip"
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.04, 0.04, 0.82)
	bg.corner_radius_top_left = 3
	bg.corner_radius_top_right = 3
	bg.corner_radius_bottom_left = 3
	bg.corner_radius_bottom_right = 3
	bg.content_margin_left = 4
	bg.content_margin_right = 4
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", bg)
	var strip := SlabUVModeStrip.new()
	strip.name = "UVModeStripButtons"
	strip.setup(_selection, _metrics)
	panel.add_child(strip)
	panel.visible = false
	return panel


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
	_paint_face.visible = false
	_paint_face.clip_text = true
	_paint_face.autowrap_mode = TextServer.AUTOWRAP_OFF
	_paint_face.size_flags_stretch_ratio = 2.0
	_paint_mat = _paint_caption("Material", "none")
	_paint_dirty = _paint_caption("Save", "")
	_paint_dirty.name = "PaintDirty"
	_paint_dirty.visible = false
	row.add_child(_paint_face)
	row.add_child(_paint_dirty)
	return row


func _paint_action_row() -> Control:
	var tools := VBoxContainer.new()
	_paint_actions = tools
	tools.name = "PaintActions"
	_paint_action_tools = tools
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tools.add_theme_constant_override("separation", 4)
	tools.add_child(_paint_mat)
	var buttons := HFlowContainer.new()
	buttons.name = "PaintActionButtons"
	buttons.add_theme_constant_override("h_separation", 4)
	_paint_assign = _named_action("Assign", "MaterialPreviewCube", "Assign the active material to the selected faces.", func() -> void:
		if _paint:
			_paint.assign_active_to_selection()
	)
	_paint_assign.name = "PaintAssign"
	buttons.add_child(_paint_assign)
	_unique_button = _named_action("Make Unique", "Duplicate", "Copies this solid's material so painting does not rewrite shared tiles.", func() -> void:
		if _paint:
			_commit_paint_mapping_inputs()
			_paint.make_unique()
	)
	buttons.add_child(_unique_button)
	_paint_save = _named_action("Save Paint", "Save", "Write the painted image to PNG, then save the scene.", func() -> void:
		if _paint:
			_paint.save_png(_paint.default_save_path())
	)
	_paint_save.name = "PaintSave"
	buttons.add_child(_paint_save)
	_paint_resize = _named_action("Resize…", "ImageTexture", "Resize the owned paint image while preserving normalized UV placement.", _open_paint_resize_form)
	_paint_resize.name = "PaintResize"
	buttons.add_child(_paint_resize)
	_paint_sample = _named_action("Sample", "ListSelect", "Use the selected faces' common material as the brush. Alt-click a viewport face to sample it directly.", func() -> void:
		if _paint:
			_paint.sample_selection()
	)
	_paint_sample.name = "PaintSample"
	buttons.add_child(_paint_sample)
	tools.add_child(buttons)
	_paint_resize_form = _make_paint_resize_form()
	tools.add_child(_paint_resize_form)
	_paint_picker_wrap = _paint_picker_slot()
	tools.add_child(_paint_picker_wrap)
	_paint_help = Label.new()
	_paint_help.name = "PaintHelp"
	_paint_help.add_theme_font_size_override("font_size", _font(13))
	_paint_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paint_help.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_paint_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_paint_help.custom_minimum_size.x = 0.0
	tools.add_child(_paint_help)
	return tools


func _paint_mapping_section() -> Control:
	var section := VBoxContainer.new()
	section.name = "PaintMapping"
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 4)
	var title := Label.new()
	_paint_mapping_title = title
	title.text = "Mapping"
	title.add_theme_font_size_override("font_size", _font(13))
	title.add_theme_color_override("font_color", Color(0.92, 0.78, 0.28))
	section.add_child(title)
	_paint_mapping_state = Label.new()
	_paint_mapping_state.name = "PaintMappingState"
	_paint_mapping_state.add_theme_font_size_override("font_size", _font(12))
	_paint_mapping_state.add_theme_color_override("font_color", Color(0.78, 0.78, 0.74))
	section.add_child(_paint_mapping_state)
	var fields := GridContainer.new()
	_paint_mapping_grid = fields
	fields.columns = 2
	fields.add_theme_constant_override("h_separation", 4)
	fields.add_theme_constant_override("v_separation", 4)
	_paint_density_row = _compact_spin("Pixels/metre", 1, 4096, 1, _actions.uv_pixels_per_meter, func(v: float) -> void:
		_actions.uv_pixels_per_meter = v
	, "Density used by Unwrap.", &"paint_uv_pixels_per_meter")
	fields.add_child(_paint_density_row)
	var texture_px := _compact_spin("Texture px", 16, 16384, 1, _actions.uv_texture_resolution, func(v: float) -> void:
		_actions.uv_texture_resolution = int(v)
	, "Reference atlas resolution for Unwrap and the size of a blank image created by Make Unique. Existing artwork is not resized.", &"paint_uv_texture_resolution")
	_paint_texture_px_label = texture_px.get_child(0) as Label
	_paint_texture_px_spin = texture_px.get_child(1) as SpinBox
	fields.add_child(texture_px)
	section.add_child(fields)
	var unwrap := _named_action("Unwrap", "ArrayMesh", "Unfold the selected face region at this density and texture resolution.", func() -> void:
		_commit_paint_mapping_inputs()
		_actions.run("uv_unwrap")
		if _paint != null and _last_report.begins_with("Unwrapped "):
			_paint.refresh_uv_mapping()
			_paint_canvas.frame_uv.call_deferred()
	)
	_paint_unwrap = unwrap
	unwrap.name = "PaintUnwrap"
	section.add_child(unwrap)
	return section


func _paint_uv_control_row() -> Control:
	var fields := VBoxContainer.new()
	# Direct dialog children span the button bar. Let empty body space pass mouse
	# releases through to the native OK/Cancel buttons; field children remain interactive.
	fields.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fields.name = "PaintUvControls"
	fields.custom_minimum_size.y = _scaled(PAINT_UV_ROW_HEIGHT)
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	fields.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.name = "PaintPlacementTitle"
	title.text = "Placement"
	title.add_theme_font_size_override("font_size", _font(13))
	title.add_theme_color_override("font_color", Color(0.92, 0.78, 0.28))
	fields.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.add_child(_compact_spin("Repeat U", 0.05, 64.0, 0.05, 1.0, func(v: float) -> void:
		_actions.uv_scale = Vector2(v, _actions.uv_scale.y)
	, "Texture repeats across the face in U.", &"paint_uv_repeat_u"))
	grid.add_child(_compact_spin("Repeat V", 0.05, 64.0, 0.05, 1.0, func(v: float) -> void:
		_actions.uv_scale = Vector2(_actions.uv_scale.x, v)
	, "Texture repeats across the face in V.", &"paint_uv_repeat_v"))
	grid.add_child(_compact_spin("Offset U", -64.0, 64.0, 0.05, 0.0, func(v: float) -> void:
		_actions.uv_offset = Vector2(v, _actions.uv_offset.y)
	, "Texture offset in U.", &"paint_uv_offset_u"))
	grid.add_child(_compact_spin("Offset V", -64.0, 64.0, 0.05, 0.0, func(v: float) -> void:
		_actions.uv_offset = Vector2(_actions.uv_offset.x, v)
	, "Texture offset in V.", &"paint_uv_offset_v"))
	grid.add_child(_compact_spin("Rotation", -360.0, 360.0, 1.0, 0.0, func(v: float) -> void:
		_actions.uv_rotation_degrees = v
	, "Texture rotation in degrees.", &"paint_uv_rotation"))
	fields.add_child(grid)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 4)
	actions.add_child(_named_action("Apply UV", "ImageTexture", "Apply these UV values to the selected face.", func() -> void:
		if _paint:
			_commit_paint_uv_inputs()
			_paint.apply_uv()
	))
	actions.add_child(_named_action("Repeat ×2", "ZoomMore", "Double both texture repeat values and apply them to the selected faces.", func() -> void:
		_commit_paint_uv_inputs()
		_paint.scale_uv(2.0)
		_sync_paint_uv_input_text()
	))
	actions.add_child(_named_action("Repeat ÷2", "ZoomLess", "Halve both texture repeat values and apply them to the selected faces.", func() -> void:
		_commit_paint_uv_inputs()
		_paint.scale_uv(0.5)
		_sync_paint_uv_input_text()
	))
	actions.add_child(_named_action("Reset UV", "Reload", "Reset repeats, offsets and rotation on the selected face.", func() -> void:
		if _paint:
			_paint.reset_uv()
	))
	actions.add_child(_named_action("UV 90°", "ToolRotate", "Rotate UV placement by ninety degrees.", func() -> void:
		if _paint:
			_paint.rotate_uv_90()
	))
	fields.add_child(actions)
	return fields


func _paint_picker_slot() -> Control:
	var wrap := MarginContainer.new()
	wrap.name = "PaintMaterialPickerWrap"
	wrap.custom_minimum_size = Vector2(_scaled(PAINT_PICKER_WIDTH), _scaled(PAINT_PICKER_HEIGHT))
	wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	var picker: Node = _make_paint_picker()
	wrap.add_child(picker)
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
				picker.custom_minimum_size = Vector2(_scaled(PAINT_PICKER_WIDTH), _scaled(PAINT_PICKER_HEIGHT))
			if picker.has_signal("resource_changed"):
				picker.resource_changed.connect(func(res: Resource) -> void:
					if _paint != null:
						_paint.choose_brush_material(res as StandardMaterial3D)
				)
			if picker.has_signal("resource_selected"):
				picker.resource_selected.connect(func(res: Resource, _inspect: bool) -> void:
					if _paint != null:
						_paint.inspect_brush_resource(res)
				)
			_apply_picker_fonts(picker)
			return picker
	var fake := Button.new()
	fake.name = "PaintMaterialPicker"
	fake.text = "Assign"
	fake.clip_text = true
	fake.focus_mode = Control.FOCUS_NONE
	fake.custom_minimum_size = Vector2(_scaled(PAINT_PICKER_WIDTH), _scaled(PAINT_PICKER_HEIGHT))
	fake.add_theme_font_size_override("font_size", _font(13))
	_paint_picker = fake
	return fake


func _apply_picker_fonts(node: Node) -> void:
	if node is Label or node is Button or node is LineEdit:
		node.add_theme_font_size_override("font_size", _font(13))
	for child in node.get_children():
		_apply_picker_fonts(child)


func _brush_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = _scaled(140.0)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", 2)
	
	var channel_section := Label.new()
	channel_section.text = "Channel"
	channel_section.add_theme_font_size_override("font_size", _font(13))
	channel_section.add_theme_color_override("font_color", ACCENT)
	col.add_child(channel_section)
	
	_channel_picker = HBoxContainer.new()
	_channel_picker.name = "ChannelPicker"
	_channel_picker.add_theme_constant_override("separation", 2)
	var channel_group := ButtonGroup.new()
	for ch_entry in [[SlabPaint.Channel.ALBEDO, "Albedo"], [SlabPaint.Channel.ROUGHNESS, "Roughness"], [SlabPaint.Channel.EMISSION, "Emission"]]:
		var ch_btn := Button.new()
		ch_btn.name = "Channel%s" % ch_entry[1]
		ch_btn.text = ch_entry[1]
		ch_btn.toggle_mode = true
		ch_btn.button_group = channel_group
		ch_btn.button_pressed = ch_entry[0] == SlabPaint.Channel.ALBEDO
		ch_btn.add_theme_font_size_override("font_size", _font(11))
		ch_btn.custom_minimum_size.y = _scaled(24.0)
		ch_btn.tooltip_text = "Paint on the %s channel." % ch_entry[1]
		var channel_id: int = ch_entry[0]
		ch_btn.pressed.connect(func() -> void:
			if _paint:
				_paint.channel = channel_id
		)
		_channel_picker.add_child(ch_btn)
	col.add_child(_channel_picker)
	
	_channel_label = Label.new()
	_channel_label.name = "ChannelLabel"
	_channel_label.text = "Albedo"
	_channel_label.add_theme_font_size_override("font_size", _font(12))
	_channel_label.add_theme_color_override("font_color", Color(0.92, 0.78, 0.28))
	_channel_label.tooltip_text = "Currently painting on this channel."
	_channel_label.visible = false
	col.add_child(_channel_label)
	
	col.add_child(HSeparator.new())
	
	var layer_header := HBoxContainer.new()
	layer_header.add_theme_constant_override("separation", 4)
	var layer_label := Label.new()
	layer_label.text = "Layers"
	layer_label.add_theme_font_size_override("font_size", _font(13))
	layer_label.add_theme_color_override("font_color", ACCENT)
	layer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_header.add_child(layer_label)
	
	_add_layer_button = Button.new()
	_add_layer_button.name = "AddLayer"
	_add_layer_button.text = "+"
	_add_layer_button.tooltip_text = "Add a new layer to the current channel."
	_add_layer_button.add_theme_font_size_override("font_size", _font(12))
	_add_layer_button.custom_minimum_size = Vector2(_scaled(24.0), _scaled(20.0))
	_add_layer_button.pressed.connect(func() -> void:
		if _paint:
			_paint.add_layer()
	)
	layer_header.add_child(_add_layer_button)
	
	_delete_layer_button = Button.new()
	_delete_layer_button.name = "DeleteLayer"
	_delete_layer_button.text = "-"
	_delete_layer_button.tooltip_text = "Delete the active layer."
	_delete_layer_button.add_theme_font_size_override("font_size", _font(12))
	_delete_layer_button.custom_minimum_size = Vector2(_scaled(24.0), _scaled(20.0))
	_delete_layer_button.pressed.connect(func() -> void:
		if _paint:
			_paint.remove_layer()
	)
	layer_header.add_child(_delete_layer_button)
	col.add_child(layer_header)
	
	_layer_list = VBoxContainer.new()
	_layer_list.name = "LayerList"
	_layer_list.add_theme_constant_override("separation", 2)
	col.add_child(_layer_list)
	
	var overlay_opacity_row := _compact_spin("Opacity", 0.0, 1.0, 0.05, 1.0, func(v: float) -> void:
		if _paint:
			_paint.overlay_opacity = v
	, "Active layer opacity. Strokes remain non-destructive until Flatten.", &"overlay_opacity")
	_overlay_opacity = overlay_opacity_row.get_child(1) as SpinBox
	col.add_child(overlay_opacity_row)
	
	_flatten_button = _named_action("Flatten", "MoveDown", "Commit all visible layers to the base as one undoable action.", func() -> void:
		if _paint:
			_paint.flatten()
	)
	_flatten_button.name = "PaintFlatten"
	col.add_child(_flatten_button)
	
	col.add_child(HSeparator.new())
	
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
	
	var overlay := CheckBox.new()
	overlay.name = "PaintUvOverlay"
	overlay.text = "Show UV"
	overlay.tooltip_text = "Overlay the selected face's UV boundaries on the image. Repeated tiles can overlap."
	overlay.add_theme_font_size_override("font_size", _font(12))
	overlay.focus_mode = Control.FOCUS_NONE
	overlay.toggled.connect(func(visible: bool) -> void:
		_paint_canvas.show_pixel_uv = visible
	)
	col.add_child(overlay)
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
		_close_paint_resize_form()
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
		if button.has_focus(): button.release_focus()
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


func _sync_model_chrome() -> void:
	var in_workspace: bool = _workspace != Workspace.MODELLING
	var modelling: bool = not in_workspace and not _actions.operation_active
	if _selection_controls != null:
		_selection_controls.visible = modelling
	if _model_body != null:
		_model_body.visible = modelling


func _toggle_uv_workspace() -> void:
	if _workspace == Workspace.UV:
		_exit_workspace()
	else:
		_enter_workspace(Workspace.UV)


func _toggle_paint_workspace() -> void:
	if _workspace == Workspace.PAINT:
		_exit_workspace()
	else:
		_enter_workspace(Workspace.PAINT)


func _enter_workspace(ws: int) -> void:
	if _paint == null:
		return
	_workspace = ws
	if ws == Workspace.UV:
		_paint.tool = SlabPaint.Tool.MATERIAL_UV
	else:
		_paint.tool = SlabPaint.Tool.PIXEL
	if not _paint.active:
		_paint.enter()
	else:
		_on_paint_changed()


func _exit_workspace() -> void:
	_workspace = Workspace.MODELLING
	if _paint != null and _paint.active:
		_paint.exit()
	else:
		_on_paint_changed()


func current_workspace() -> int:
	return _workspace


func _on_paint_changed() -> void:
	var on: bool = _paint != null and _paint.active
	if not on:
		_workspace = Workspace.MODELLING
		_close_paint_resize_form()
	else:
		_workspace = Workspace.PAINT if _paint.tool == SlabPaint.Tool.PIXEL else Workspace.UV
	add_theme_constant_override("separation", 3 if on else 6)
	_sync_model_chrome()
	if _operation_row != null:
		_operation_row.visible = not on and _actions.operation_active
	var external_only: bool = _selection != null and _selection.has_only_external_meshes()
	if _uv_toggle != null:
		_uv_toggle.set_pressed_no_signal(_workspace == Workspace.UV)
		_style_tool(_uv_toggle, _workspace == Workspace.UV)
		_uv_toggle.disabled = external_only
		if external_only:
			_uv_toggle.tooltip_text = "Convert to a Slab solid first (Promote — later)."
		else:
			_uv_toggle.tooltip_text = "Open the UV workspace for unwrapping and material placement. Escape closes it."
	if _paint_toggle != null:
		_paint_toggle.set_pressed_no_signal(_workspace == Workspace.PAINT)
		_style_tool(_paint_toggle, _workspace == Workspace.PAINT)
		_paint_toggle.disabled = external_only
		if external_only:
			_paint_toggle.tooltip_text = "Convert to a Slab solid first (Promote — later)."
		else:
			_paint_toggle.tooltip_text = "Open the pixel Paint workspace. Escape closes it."
	if _paint_body != null:
		_paint_body.visible = on
	clip_contents = on
	custom_minimum_size.x = _scaled(560.0) if on else 0.0
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
	_paint_face.text = paint_target_text(_selection)
	if _paint != null and _selection != null and _selection.objects.size() == 1 and not _selection.ids.is_empty():
		var count: int = _selection.ids.size()
		_paint_face.text = "%s · %d %s · %s" % [_selection.solid.name, count,
			"face" if count == 1 else "faces", _paint.selected_material_summary()]
	_paint_face.tooltip_text = _paint_face.text
	if _selection_context != null and _paint != null and _paint.active:
		_selection_context.text = _paint_face.text
		_selection_context.tooltip_text = _paint_face.text
	var mat_text := "none"
	var is_uv_workspace: bool = _workspace == Workspace.UV
	var is_paint_workspace: bool = _workspace == Workspace.PAINT
	if _paint != null:
		var mat: Variant = _paint.material() if is_paint_workspace else _paint.brush_material()
		mat_text = _paint.material_label(mat, _paint.slot())
		if mat == null:
			mat_text = "none"
		if mat is StandardMaterial3D and _paint.is_owned(mat):
			mat_text += " (unique)"
	_paint_mat.text = "%s: %s" % ["Texture" if is_paint_workspace else "Brush", mat_text]
	_paint_mat.clip_text = true
	_paint_mat.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_paint_mat.tooltip_text = _paint_mat.text
	_paint_dirty.text = _paint.save_status() if _paint != null else ""
	_paint_dirty.visible = false
	_paint_dirty.clip_text = true
	_paint_dirty.tooltip_text = _paint_dirty.text
	_paint_assign.visible = is_uv_workspace
	_paint_sample.visible = is_uv_workspace
	_paint_picker_wrap.visible = is_uv_workspace
	_paint_palette.visible = is_uv_workspace
	if _uv_mode_strip != null:
		_uv_mode_strip.visible = is_uv_workspace
	if _paint_canvas != null:
		_paint_canvas.set_uv_element_mode(is_uv_workspace)
	_paint_save.visible = is_paint_workspace
	_paint_save.disabled = _paint == null or not _paint.is_owned(_paint.material())
	_paint_resize.visible = is_paint_workspace
	_paint_resize.disabled = _paint == null or not _paint.can_resize_image()
	_paint_resize.tooltip_text = "Choose Width, Height, and resampling for the owned paint image." if not _paint_resize.disabled else "Make Unique before resizing this image."
	_paint_help.visible = is_paint_workspace
	_paint_help.text = _pixel_help_text()
	_paint_help.tooltip_text = _paint_help.text
	if _paint_tool_uv != null:
		_paint_tool_uv.visible = false
	if _paint_tool_pixel != null:
		_paint_tool_pixel.visible = false
	if _paint_uv_hint != null:
		var preview_caption: String = _paint.brush_preview_caption() if _paint != null else ""
		var uv_mode_hint := _uv_mode_hint()
		if preview_caption != "":
			_paint_uv_hint.text = preview_caption
			_paint_uv_hint.tooltip_text = "%s\n%s" % [preview_caption, uv_mode_hint]
		else:
			_paint_uv_hint.text = uv_mode_hint
			_paint_uv_hint.tooltip_text = uv_mode_hint
		_paint_uv_hint.visible = is_uv_workspace
	if _paint_fit_uv != null:
		_paint_fit_uv.visible = is_uv_workspace
	if _paint_uv_controls != null:
		_paint_uv_controls.visible = is_uv_workspace
	if _paint_brush != null:
		_paint_brush.visible = is_paint_workspace
	if _paint_inspector != null:
		_paint_inspector.custom_minimum_size.x = _scaled(180.0 if is_paint_workspace else 350.0)
	if _paint_inspector_fields != null:
		_paint_inspector_fields.custom_minimum_size.x = _scaled(172.0 if is_paint_workspace else 342.0)
	if _paint_mapping_grid != null:
		_paint_mapping_grid.columns = 1 if is_paint_workspace else 2
	if _paint_mapping_title != null:
		_paint_mapping_title.text = "Image" if is_paint_workspace else "Mapping"
	if _paint_mapping_state != null:
		_paint_mapping_state.text = _paint_mapping_summary()
		_paint_mapping_state.visible = is_uv_workspace
	if _paint_density_row != null:
		_paint_density_row.visible = is_uv_workspace
	if _paint_unwrap != null:
		_paint_unwrap.visible = is_uv_workspace
	var pixel_has_artwork := false
	if is_paint_workspace and _paint != null:
		var pixel_material: Variant = _paint.material()
		pixel_has_artwork = pixel_material is StandardMaterial3D and pixel_material.albedo_texture != null
	if _paint_texture_px_label != null:
		_paint_texture_px_label.text = "Texture px" if is_uv_workspace or pixel_has_artwork else "New image px"
		_paint_texture_px_label.tooltip_text = "Existing artwork dimensions; Make Unique preserves them." if pixel_has_artwork else "Reference atlas resolution for Unwrap and the size of a blank image created by Make Unique."
	if _paint_texture_px_spin != null:
		_paint_texture_px_spin.editable = not pixel_has_artwork
		_paint_texture_px_spin.tooltip_text = _paint_texture_px_label.tooltip_text
	if _paint != null:
		_set_spin(&"paint_uv_pixels_per_meter", _actions.uv_pixels_per_meter)
		_set_spin(&"paint_uv_texture_resolution", _actions.uv_texture_resolution)
		_set_spin(&"paint_uv_repeat_u", _actions.uv_scale.x)
		_set_spin(&"paint_uv_repeat_v", _actions.uv_scale.y)
		_set_spin(&"paint_uv_offset_u", _actions.uv_offset.x)
		_set_spin(&"paint_uv_offset_v", _actions.uv_offset.y)
		_set_spin(&"paint_uv_rotation", _actions.uv_rotation_degrees)
	if _paint_picker != null and is_instance_valid(_paint_picker) and _paint != null:
		if _paint_picker.has_method("set_edited_resource"):
			_paint_picker.set("edited_resource", _paint.material())
	if _unique_button != null:
		var allowed: bool = _paint != null and _paint.can_make_unique()
		_unique_button.disabled = not allowed
		_unique_button.tooltip_text = "Copy the current material onto the selected faces so pixel painting does not rewrite shared tiles." if allowed else "Select faces that share one material before Make Unique."
	if _overlay_opacity != null and _paint != null:
		_overlay_opacity.set_value_no_signal(_paint.overlay_opacity)
	if _flatten_button != null:
		var can_flatten: bool = _paint != null and _paint.can_flatten()
		_flatten_button.disabled = not can_flatten
		var channel_name: String = _paint.current_channel_name() if _paint else "Albedo"
		_flatten_button.tooltip_text = "Commit all visible layers to the %s base as one undoable action." % channel_name if can_flatten else "Paint strokes on the overlay first."
	if _channel_label != null:
		_channel_label.visible = false
	if _channel_picker != null:
		_channel_picker.visible = is_paint_workspace
		if is_paint_workspace:
			_sync_channel_picker()
	if _layer_list != null:
		_layer_list.visible = is_paint_workspace
		if is_paint_workspace:
			_refresh_layer_list()
	if _add_layer_button != null:
		_add_layer_button.visible = is_paint_workspace
	if _delete_layer_button != null:
		_delete_layer_button.visible = is_paint_workspace
	_refresh_paint_palette()
	if _paint != null and _paint.active:
		custom_minimum_size.y = maxf(_scaled(SlabPaint.PAINT_HEIGHT), _paint_workspace_minimum_height())
	update_minimum_size()


func _paint_mapping_summary() -> String:
	if _selection == null or _selection.solid == null or _selection.ids.is_empty():
		return "No face mapping selected"
	var unwrapped := 0
	for face in _selection.ids:
		var attrs: Dictionary = _selection.solid.call("face_uv", face)
		if bool(attrs.get("unwrapped", false)):
			unwrapped += 1
	if unwrapped == 0:
		return "Planar mapping"
	if unwrapped == _selection.ids.size():
		return "Unwrapped mapping"
	return "Mixed mapping"


func _pixel_help_text() -> String:
	if _selection == null or _selection.objects.size() != 1 or _selection.ids.is_empty():
		return "Select a face in Face mode to paint."
	if _paint == null:
		return ""
	if _paint.material() == null:
		return "Make Unique creates an image for these faces." if _paint.can_make_unique() else "Select faces that share one material."
	if not _paint.is_owned(_paint.material()):
		return "Make Unique before painting this shared texture."
	return "Paint on the image or model. Save Paint, then save the scene."


static func paint_target_text(selection: Variant) -> String:
	if selection == null or selection.objects.is_empty():
		return "No solid selected · Select a Slab solid, then a face."
	if selection.objects.size() > 1:
		return "%d solids selected · Select one solid to paint." % selection.objects.size()
	var target: Node3D = selection.objects[0]
	var count: int = selection.ids.size()
	if count == 0:
		return "%s · Select a face to paint." % target.name
	return "%s · %d %s selected" % [target.name, count, "face" if count == 1 else "faces"]


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
		chip.button_pressed = _paint != null and mats[i] != null and mats[i] == _paint.brush_material()
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
		chip.tooltip_text = "Choose %s as the brush. Assign or click a viewport face to apply it." % label
		if mats[i] == null:
			chip.tooltip_text = "This slot has no material. Choose a material resource before assigning it."
		if _paint != null:
			chip.icon = _paint.thumbnail(mats[i], thumb_px)
		chip.pressed.connect(func() -> void:
			if _paint:
				_paint.select_material_slot(i)
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
	button.add_theme_stylebox_override("hover_pressed", box)
	button.add_theme_color_override("font_color", Color(0.12, 0.1, 0.06) if pressed else Color(0.86, 0.86, 0.82))
	button.add_theme_color_override("font_pressed_color", Color(0.12, 0.1, 0.06))
	button.add_theme_color_override("font_hover_color", Color(0.12, 0.1, 0.06) if pressed else Color(0.95, 0.95, 0.9))
	button.add_theme_color_override("font_hover_pressed_color", Color(0.12, 0.1, 0.06))


func _sync_create_pressed() -> void:
	for id in _buttons:
		var row: Dictionary = _actions.find(id)
		if row.is_empty() or _actions.section_of(row) != _actions.SECTION_CREATE:
			continue
		_buttons[id].set_pressed_no_signal(StringName(id) == _create_focus)
		var selected_style := _buttons[id].get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		if selected_style != null:
			selected_style.bg_color = ACCENT
			_buttons[id].add_theme_stylebox_override("pressed", selected_style)
			_buttons[id].add_theme_color_override("font_pressed_color", Color(0.12, 0.1, 0.06))


func _tooltip_of(row: Dictionary) -> String:
	if _actions.section_of(row) == _actions.SECTION_CREATE:
		return "%s\nChoose this shape and set its dimensions, then click Create.\n%s" % [row["label"], _actions.shapes.describe(row["id"])]
	var lines := PackedStringArray([row["label"]])
	var body: String = _actions.tooltip_of(row)
	if body != "":
		lines.append(body)
	var shortcut: int = _actions.shortcut_of(row)
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


func _commit_paint_mapping_inputs() -> void:
	if _paint_mapping_controls == null:
		return
	for spin in _spins_under(_paint_mapping_controls):
		spin.apply()
		spin.get_line_edit().release_focus()


func _commit_paint_uv_inputs() -> void:
	if _paint_uv_controls == null:
		return
	for spin in _spins_under(_paint_uv_controls):
		spin.apply()
		spin.get_line_edit().release_focus()


func _sync_paint_uv_input_text() -> void:
	_set_spin(&"paint_uv_repeat_u", _actions.uv_scale.x)
	_set_spin(&"paint_uv_repeat_v", _actions.uv_scale.y)
	for key in [&"paint_uv_repeat_u", &"paint_uv_repeat_v"]:
		var row: Node = find_child(String(key), true, false)
		if row != null:
			var spins := _spins_under(row)
			if not spins.is_empty():
				spins[0].get_line_edit().text = str(spins[0].value)


func _make_paint_resize_form() -> VBoxContainer:
	var form := VBoxContainer.new()
	form.name = "PaintResizeForm"
	form.visible = false
	form.add_theme_constant_override("separation", 4)
	_paint_resize_width = SpinBox.new()
	_paint_resize_width.name = "PaintResizeWidth"
	_paint_resize_width.min_value = 16
	_paint_resize_width.max_value = 16384
	_paint_resize_width.step = 1
	_paint_resize_width.prefix = "Width  "
	_paint_resize_width.add_theme_font_size_override("font_size", _font(13))
	_paint_resize_width.get_line_edit().add_theme_font_size_override("font_size", _font(13))
	_paint_resize_width.accessibility_name = "Resize image width"
	_paint_resize_height = SpinBox.new()
	_paint_resize_height.name = "PaintResizeHeight"
	_paint_resize_height.min_value = 16
	_paint_resize_height.max_value = 16384
	_paint_resize_height.step = 1
	_paint_resize_height.prefix = "Height  "
	_paint_resize_height.add_theme_font_size_override("font_size", _font(13))
	_paint_resize_height.get_line_edit().add_theme_font_size_override("font_size", _font(13))
	_paint_resize_height.accessibility_name = "Resize image height"
	_paint_resize_width.value_changed.connect(func(value: float) -> void:
		if _paint_resize_aspect != null and _paint_resize_aspect.button_pressed and not _paint_resize_sync:
			_paint_resize_sync = true
			_paint_resize_height.set_value_no_signal(round(value / _paint_resize_ratio))
			_paint_resize_height.get_line_edit().text = str(int(_paint_resize_height.value))
			_paint_resize_sync = false
	)
	_paint_resize_height.value_changed.connect(func(value: float) -> void:
		if _paint_resize_aspect != null and _paint_resize_aspect.button_pressed and not _paint_resize_sync:
			_paint_resize_sync = true
			_paint_resize_width.set_value_no_signal(round(value * _paint_resize_ratio))
			_paint_resize_width.get_line_edit().text = str(int(_paint_resize_width.value))
			_paint_resize_sync = false
	)
	_paint_resize_aspect = CheckBox.new()
	_paint_resize_aspect.name = "PaintResizeAspect"
	_paint_resize_aspect.text = "Keep aspect"
	_paint_resize_aspect.button_pressed = true
	_paint_resize_aspect.add_theme_font_size_override("font_size", _font(13))
	_paint_resize_aspect.accessibility_name = "Keep image aspect ratio"
	_paint_resize_sampling = OptionButton.new()
	_paint_resize_sampling.name = "PaintResizeSampling"
	_paint_resize_sampling.add_item("Smooth")
	_paint_resize_sampling.add_item("Nearest")
	_paint_resize_sampling.add_theme_font_size_override("font_size", _font(13))
	_paint_resize_sampling.accessibility_name = "Resize sampling"
	form.add_child(_paint_resize_width)
	form.add_child(_paint_resize_height)
	form.add_child(_paint_resize_aspect)
	form.add_child(_paint_resize_sampling)
	var actions := HFlowContainer.new()
	var cancel := Button.new()
	cancel.name = "PaintResizeCancel"
	cancel.text = "Cancel"
	cancel.add_theme_font_size_override("font_size", _font(13))
	cancel.accessibility_name = "Cancel image resize"
	cancel.pressed.connect(_close_paint_resize_form)
	var apply := Button.new()
	apply.name = "PaintResizeConfirm"
	apply.text = "Apply Resize"
	apply.add_theme_font_size_override("font_size", _font(13))
	apply.accessibility_name = "Apply image resize"
	apply.pressed.connect(_apply_paint_resize)
	actions.add_child(cancel)
	actions.add_child(apply)
	form.add_child(actions)
	return form


func _open_paint_resize_form() -> void:
	if _paint == null or not _paint.can_resize_image():
		set_status("Make Unique before resizing this image.")
		return
	_paint_resize_target = _paint.material()
	_paint_resize_width.set_value_no_signal(_paint.image().get_width())
	_paint_resize_height.set_value_no_signal(_paint.image().get_height())
	_paint_resize_ratio = float(_paint_resize_width.value) / maxf(float(_paint_resize_height.value), 1.0)
	_paint_resize_width.get_line_edit().text = str(int(_paint_resize_width.value))
	_paint_resize_height.get_line_edit().text = str(int(_paint_resize_height.value))
	_paint_resize_aspect.button_pressed = true
	_paint_resize_sampling.select(0)
	_paint_resize_form.visible = true
	_paint_resize_form.update_minimum_size()
	_reveal_paint_resize_form()


func _reveal_paint_resize_form() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _paint_resize_form != null and _paint_resize_form.is_visible_in_tree() and _paint_inspector != null:
		_paint_inspector.ensure_control_visible(_paint_resize_form.get_child(_paint_resize_form.get_child_count() - 1))
		_paint_inspector.scroll_horizontal = 0


func _apply_paint_resize() -> void:
	_paint_resize_width.apply()
	_paint_resize_height.apply()
	_paint.resize_image(int(_paint_resize_width.value), int(_paint_resize_height.value),
		_paint_resize_sampling.selected == 0, _paint_resize_target)
	_close_paint_resize_form()


func _close_paint_resize_form() -> void:
	if _paint_resize_form != null:
		_paint_resize_form.visible = false
	_paint_resize_target = null


func _sync_loop_values() -> void:
	if _settings_fields == null:
		return
	for spin in _spins_under(_settings_fields):
		if spin.get_parent().name == "loop_count":
			spin.set_value_no_signal(_actions.loop_count)
		elif spin.get_parent().name == "loop_position":
			spin.set_value_no_signal(_actions.loop_position * 100.0)


func _sync_loop_controls() -> void:
	if _loop_action_group == null or _loop_apply == null or _loop_cancel == null:
		return
	_loop_action_group.visible = _actions.loop_active
	_loop_apply.disabled = not _actions.loop_can_apply


func _apply_loop_preview() -> void:
	for key in [&"loop_count", &"loop_position"]:
		var field: Node = find_child(String(key), true, false)
		if field != null:
			for spin in _spins_under(field):
				spin.apply()
	_actions.loop_apply_requested.emit()


func _on_uv_element_picked(element_id: int, additive: bool) -> void:
	if _selection == null:
		return
	_selection.toggle_uv_element(element_id, additive)


func _uv_mode_hint() -> String:
	return SlabPaint.uv_canvas_hint()
