@tool
extends VBoxContainer

const Construction := preload("res://addons/slab/slab_construction.gd")
const Step := preload("res://addons/slab/slab_construction_step.gd")
const Recipe := preload("res://addons/slab/slab_construction_recipe.gd")

signal reported(message: String)

var _engine := Construction.new()
var _selection: RefCounted
var _actions: RefCounted
var _scene_root: Callable
var _undo: Object
var _body: VBoxContainer
var _expanded := false
var _queued := false
var _target: Node3D
var _metrics: RefCounted

func setup(selection: RefCounted, actions: RefCounted, scene_root: Callable, metrics: RefCounted = null) -> void:
	_metrics = metrics if metrics != null else preload("res://addons/slab/slab_metrics.gd").at_scale(1.0)
	name = "Construction"
	_selection = selection
	_actions = actions
	_scene_root = scene_root
	var toggle := Button.new()
	_style(toggle)
	toggle.text = "Construction"
	toggle.toggle_mode = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.tooltip_text = "Save editable construction steps; revisit parameters, bypass or reorder them."
	toggle.toggled.connect(func(value: bool):
		_expanded = value
		_body.visible = value
		if value: refresh()
	)
	add_child(toggle)
	_body = VBoxContainer.new()
	_body.visible = false
	add_child(_body)
	_selection.changed.connect(refresh)
	refresh()

func bind_undo(undo: Object) -> void:
	if _undo != null and _undo.has_signal("version_changed") and _undo.version_changed.is_connected(refresh):
		_undo.version_changed.disconnect(refresh)
	_undo = undo
	if _undo != null and _undo.has_signal("version_changed"):
		_undo.version_changed.connect(refresh)

func refresh() -> void:
	if _queued: return
	_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_queued = false
	if not is_instance_valid(_body): return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_target = _selection.solid
	if not is_instance_valid(_target) or not _target.is_class("SlabSolid"):
		_label(_body, "Select a Slab solid to edit its construction.")
		return
	if _actions.operation_active or _actions.array_active or _actions.plane_active:
		_label(_body, "Finish the active operation before editing construction.")
		return
	if _undo == null or not _scene_root.is_valid():
		_label(_body, "Construction needs the scene's Undo history.")
		return
	var recipe = (_target.get_meta(Construction.RECIPE_META) if _target.has_meta(Construction.RECIPE_META) else null)
	if recipe == null:
		_label(_body, "Start from this mesh, or replace it with an editable primitive.")
		_button(_body, "Keep mesh · Start history", _start_mesh)
		var row := HFlowContainer.new()
		_body.add_child(row)
		for method in [&"make_box", &"make_plane", &"make_stair", &"make_cylinder", &"make_arch", &"make_poly_shape", &"make_sweep"]:
			var plan: Dictionary = _actions.shapes.plan(method)
			_button(row, "Replace with " + str(plan.create), _start_primitive.bind(method))
		return
	if not recipe is Recipe:
		_label(_body, "Unsupported construction resource.")
		return
	_label(_body, "%s · %d steps" % [_target.name, recipe.steps.size()])
	if _target.get("data") != recipe.cached_data or _target.get("materials") != recipe.cached_materials:
		_label(_body, "Manual mesh, UV or material-slot changes need a checkpoint. Earlier parameter changes will require rebasing it.")
		_button(_body, "Record manual-edit checkpoint", _record_checkpoint)
	for index in recipe.steps.size():
		_step_card(recipe.steps[index], index, recipe.steps.size())
	var additions := HFlowContainer.new()
	_body.add_child(additions)
	_button(additions, "Bevel minimum-corner X edge", _add_bevel.bind(false))
	var picked := _button(additions, "Bevel picked edges", _add_bevel.bind(true))
	picked.disabled = _selection.mode != 2 or _selection.ids.is_empty()
	picked.tooltip_text = "Pins picked edge IDs to this exact input mesh. Upstream changes require rebinding."
	_button(additions, "Add Linear Array", _add_array.bind(false))
	_button(additions, "Add Radial Array", _add_array.bind(true))
	_boolean_picker()

func _step_card(step: Resource, index: int, count: int) -> void:
	var card := VBoxContainer.new()
	_body.add_child(card)
	var row := HFlowContainer.new()
	card.add_child(row)
	var toggle := CheckBox.new()
	_style(toggle)
	toggle.text = "%d. %s" % [index + 1, Step.Kind.keys()[step.kind].capitalize().replace("_", " ")]
	toggle.button_pressed = step.enabled
	toggle.disabled = index == 0
	toggle.toggled.connect(func(value: bool): _finish(_engine.set_step_enabled(_target, step.id, value, _scene_root.call(), _undo)))
	row.add_child(toggle)
	if index > 0:
		var up := _button(row, "↑", func(): _finish(_engine.reorder_step(_target, step.id, index - 1, _scene_root.call(), _undo)))
		up.disabled = index == 1
		up.tooltip_text = "Move step earlier"
		var down := _button(row, "↓", func(): _finish(_engine.reorder_step(_target, step.id, index + 1, _scene_root.call(), _undo)))
		down.disabled = index == count - 1
		down.tooltip_text = "Move step later"
	if step.kind in [Step.Kind.MESH_SOURCE, Step.Kind.CHECKPOINT]:
		_label(card, "Recorded mesh" if index == 0 else "Manual-edit barrier · upstream input must remain unchanged")
		return
	if step.kind == Step.Kind.BEVEL and step.selection_binding == Step.SelectionBinding.PINNED_EDGES:
		_label(card, "Picked edges · upstream changes require rebinding")
	if step.kind == Step.Kind.BEVEL and step.selection_binding == Step.SelectionBinding.MIN_CORNER_X_EDGE:
		_label(card, "Geometric selector: X-directed edge at the mesh minimum corner")
	var draft: Dictionary = step.parameters.duplicate(true)
	var fields := HFlowContainer.new()
	card.add_child(fields)
	if step.kind == Step.Kind.PRIMITIVE:
		_label(card, str(draft.method).trim_prefix("make_").capitalize())
		for i in draft.args.size():
			_field(fields, _argument_label(str(draft.method), i), draft.args[i], func(value: Variant): draft.args[i] = value)
	else:
		for key in draft:
			_field(fields, str(key).capitalize(), draft[key], func(value: Variant): draft[key] = value)
	if step.kind == Step.Kind.BOOLEAN:
		_label(card, "Operand: " + _operand_name(step.operand_uuid) + " · mode 0 Union / 1 Subtract / 2 Intersect")
	_button(card, "Apply parameters", func(): _finish(_engine.edit_step(_target, step.id, draft, _scene_root.call(), _undo)))

func _argument_label(method: String, index: int) -> String:
	var labels := {"make_box": ["Size"], "make_plane": ["Size"], "make_stair": ["Size", "Steps"],
		"make_cylinder": ["Radius", "Height", "Sides"], "make_arch": ["Span", "Depth", "Segments", "Thickness", "Arc"],
		"make_prism": ["Polygon", "Height"], "make_sweep": ["Path", "Profile", "Closed"]}
	return labels.get(method, ["Argument"])[index]

func _field(parent: Control, label: String, value: Variant, changed: Callable) -> void:
	var column := VBoxContainer.new()
	parent.add_child(column)
	_label(column, label)
	if value is bool:
		var check := CheckBox.new()
		_style(check)
		check.button_pressed = value
		check.toggled.connect(changed)
		column.add_child(check)
	elif value is Vector3 or value is Vector2:
		var components: Array = [value]
		var row := HBoxContainer.new()
		column.add_child(row)
		for i in (3 if value is Vector3 else 2):
			_number(row, value[i], false, func(number: float):
				components[0][i] = number
				changed.call(components[0])
			)
	elif value is int or value is float:
		_number(column, value, value is int, changed)
	elif value is PackedVector3Array or value is PackedVector2Array:
		var points: Array = [value.duplicate()]
		for i in value.size():
			_field(column, "Point %d" % (i + 1), value[i], func(point: Variant):
				points[0][i] = point
				changed.call(points[0])
			)

func _number(parent: Control, value: float, integer: bool, changed: Callable) -> void:
	var spin := SpinBox.new()
	_style(spin)
	_style(spin.get_line_edit())
	spin.min_value = -100000
	spin.max_value = 100000
	spin.step = 1.0 if integer else 0.01
	spin.value = value
	spin.custom_minimum_size.x = 85
	spin.value_changed.connect(func(number: float): changed.call(int(number) if integer else number))
	parent.add_child(spin)

func _start_mesh() -> void:
	_apply(Construction.from_mesh(_target), "Start construction history")

func _start_primitive(method: StringName) -> void:
	var plan: Dictionary = _actions.shapes.plan(method)
	_apply(Construction.from_primitive(_target, StringName(plan.method), plan.args), "Replace with editable primitive")

func _record_checkpoint() -> void:
	_apply(Construction.checkpoint(_target), "Record construction checkpoint")

func _add_bevel(picked: bool) -> void:
	var step := Step.new()
	step.kind = Step.Kind.BEVEL
	step.parameters = {"amount": _actions.bevel_amount, "segments": _actions.bevel_segments}
	if picked:
		step.selection_binding = Step.SelectionBinding.PINNED_EDGES
		step.picked_edges = _selection.ids.duplicate()
		step.input_fingerprint = Step.fingerprint(_target.get("data"))
	_append(step)

func _add_array(radial: bool) -> void:
	var step := Step.new()
	step.kind = Step.Kind.ARRAY_RADIAL if radial else Step.Kind.ARRAY_LINEAR
	step.parameters = {"count": 3, "axis": Vector3.UP, "center": Vector3.ZERO, "angle": 45.0, "rotate": true} if radial else {"count": 3, "step": Vector3(3, 0, 0)}
	_append(step)

func _boolean_picker() -> void:
	var row := HFlowContainer.new()
	_body.add_child(row)
	var picker := OptionButton.new()
	_style(picker)
	picker.name = "BooleanOperand"
	var operands: Array[Node3D] = []
	var pending: Array[Node] = [_scene_root.call()]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node != _target and node.is_class("SlabSolid"):
			operands.append(node)
			picker.add_item(str(_scene_root.call().get_path_to(node)))
	row.add_child(picker)
	var button := _button(row, "Add Boolean", func():
		var operand: Node3D = operands[picker.selected]
		var uuid := str(operand.get_meta(Construction.UUID_META, Step.new_uuid()))
		var step := Step.new()
		step.kind = Step.Kind.BOOLEAN
		step.parameters = {"mode": 1}
		step.operand_uuid = uuid
		_append(step, {uuid: operand})
	)
	button.disabled = operands.is_empty()
	button.tooltip_text = "Subtract the chosen scene solid; its identity is registered in the same Undo action."

func _operand_name(uuid: String) -> String:
	var pending: Array[Node] = [_scene_root.call()]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if str(node.get_meta(Construction.UUID_META, "")) == uuid: return str(node.name)
	return "Missing (" + uuid + ")"

func _append(step: Resource, bindings: Dictionary = {}) -> void:
	var recipe = _target.get_meta(Construction.RECIPE_META).copy_recipe()
	recipe.steps.append(step)
	_apply(recipe, "Add construction step", bindings)

func _apply(recipe: Resource, label: String, bindings: Dictionary = {}) -> void:
	_finish(_engine.apply_candidate(_target, recipe, _scene_root.call(), _undo, label, bindings))

func _finish(result: Dictionary) -> void:
	reported.emit("Construction updated." if result.error == OK else result.message)
	refresh()

func _button(parent: Control, label: String, action: Callable) -> Button:
	var button := Button.new()
	_style(button)
	button.text = label
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Control, text: String) -> void:
	var label := Label.new()
	_style(label)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)

func _style(control: Control) -> void:
	control.add_theme_font_size_override("font_size", _metrics.font(16))
