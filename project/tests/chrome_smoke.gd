extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")

const ADDON_DIR := "res://addons/slab"

const EDITOR_INTERFACE_ALLOWLIST: PackedStringArray = [
	"plugin.gd",
	"slab_editor_host_live.gd",
	"slab_actions.gd",
	"slab_icons.gd",
]

const EDITOR_INTERFACE_FENCE: PackedStringArray = [
	"slab_viewport.gd",
	"slab_panel.gd",
	"slab_mode_strip.gd",
	"slab_pick.gd",
]

const SCALES: PackedFloat32Array = [0.75, 1.0, 1.25, 1.5, 2.0]

var _fails := 0
var _ran := 0


func case_every_panel_font_clears_the_floor_at_every_scale() -> void:
	for scale in SCALES:
		var panel := _build_panel(scale)
		var strip := _build_strip(scale)
		for control in _text_controls(panel):
			var size: int = control.get_theme_font_size("font_size")
			expect(size >= SlabMetrics.FONT_FLOOR,
				"at scale %.2f, panel %s renders at %d, floor is %d" % [
					scale, _path_of(panel, control), size, SlabMetrics.FONT_FLOOR
				])
		for control in _text_controls(strip):
			var size: int = control.get_theme_font_size("font_size")
			expect(size >= SlabMetrics.FONT_FLOOR,
				"at scale %.2f, strip %s renders at %d, floor is %d" % [
					scale, _path_of(strip, control), size, SlabMetrics.FONT_FLOOR
				])
		panel.free()
		strip.free()


func case_every_text_control_declares_a_font_size() -> void:
	var panel := _build_panel(1.0)
	for control in _text_controls(panel):
		expect(control.has_theme_font_size_override("font_size"),
			"%s declares its own font_size instead of inheriting one" % _path_of(panel, control))
	panel.free()


func case_every_declared_field_renders_one_spin() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	var spins: Array[SpinBox] = _spins(panel)
	var expected: int = 7 + actions.shapes.fields().size()
	expect(spins.size() == expected, "panel renders %d spins for 7 edit fields plus the shape catalog, got %d" % [expected, spins.size()])
	for field in actions.shapes.fields():
		var named: Node = panel.find_child(String(field["key"]), true, false)
		expect(named != null, "the %s field has a spin" % field["key"])
		if named != null:
			var spin: SpinBox = _spins(named)[0]
			expect(is_equal_approx(spin.value, field["value"]), "the %s spin starts at %s" % [field["key"], field["value"]])
			expect(spin.tooltip_text == field["tooltip"], "the %s spin carries the field tooltip" % field["key"])
	panel.free()


func case_create_tooltips_follow_the_fields() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	var stair: Button = _button_for(panel, "Stair")
	expect(stair != null and stair.tooltip_text.contains("8 steps"), "the Stair button starts by saying 8 steps")
	var steps: SpinBox = _spins(panel.find_child("stair_steps", true, false))[0]
	# Range only emits value_changed inside the tree, and this harness runs in _init.
	steps.value = 20.0
	steps.value_changed.emit(steps.value)
	expect(stair.tooltip_text.contains("20 steps") and not stair.tooltip_text.contains("8 steps"),
		"turning the Steps spin rewrites the Stair tooltip, got %s" % stair.tooltip_text)
	selection.mode = SlabSelection.Mode.FACE
	expect(stair.tooltip_text == "Stair needs Object mode.", "a disabled reason still wins over the live tooltip")
	panel.free()


func case_font_scaling_is_monotonic() -> void:
	var previous: int = 0
	for scale in SCALES:
		var panel := _build_panel(scale)
		var largest: int = _largest_font(panel)
		expect(largest >= previous, "font sizes grow with editor scale, %.2f gave %d after %d" % [scale, largest, previous])
		previous = largest
		panel.free()


func case_pick_radius_scales_without_an_editor_hint_branch() -> void:
	expect(SlabMetrics.at_scale(1.0).pick_radius() == SlabPick.BASE_RADIUS, "scale 1 is the base radius")
	expect(SlabMetrics.at_scale(2.0).pick_radius() == SlabPick.BASE_RADIUS * 2.0, "scale 2 doubles the radius")
	expect(SlabMetrics.at_scale(0.5).pick_radius() == SlabPick.BASE_RADIUS,
		"a sub-1 editor scale never shrinks the radius below base")
	expect(not _source_of("slab_pick.gd").contains("is_editor_hint"),
		"the pick radius no longer depends on whether it is running in the editor")


func case_strip_tooltip_matches_the_binding_table() -> void:
	var strip := _build_strip(1.0)
	for button in _buttons(strip):
		var mode: int = int(button.get_meta("slab_mode"))
		var keycode: int = SlabModeStrip.keycode_for(mode)
		expect(keycode != 0, "mode %s has a binding" % SlabSelection.MODE_LABELS[mode])
		expect(button.tooltip_text.contains(OS.get_keycode_string(keycode)),
			"the %s tooltip names %s" % [SlabSelection.MODE_LABELS[mode], OS.get_keycode_string(keycode)])
		expect(SlabModeStrip.mode_for_keycode(keycode) == mode, "the binding table round-trips for %s" % mode)
	strip.free()


func case_editor_interface_stays_behind_the_host() -> void:
	for file_name in EDITOR_INTERFACE_FENCE:
		expect(not _source_of(file_name).contains("EditorInterface"),
			"%s does not reach EditorInterface" % file_name)
	for file_name in _addon_sources():
		if EDITOR_INTERFACE_ALLOWLIST.has(file_name) or EDITOR_INTERFACE_FENCE.has(file_name):
			continue
		expect(not _source_of(file_name).contains("EditorInterface"),
			"%s does not reach EditorInterface" % file_name)


func case_plugin_forwards_input_without_a_selection() -> void:
	var source: String = _source_of("plugin.gd")
	expect(source.contains("set_input_event_forwarding_always_enabled"),
		"plugin.gd still forwards viewport input with an empty selection")
	expect(source.contains("_forward_3d_gui_input"), "plugin.gd still forwards 3D GUI input")


func _build_panel(scale: float) -> SlabPanel:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(scale))
	return panel


func _build_strip(scale: float) -> SlabModeStrip:
	var selection := SlabSelection.new()
	var strip := SlabModeStrip.new()
	strip.setup(selection, true, SlabMetrics.at_scale(scale))
	return strip


func _text_controls(node: Node) -> Array[Control]:
	var out: Array[Control] = []
	_collect_text(node, out)
	return out


func _collect_text(node: Node, out: Array[Control]) -> void:
	if node is Label or node is Button or node is LineEdit:
		out.append(node)
	for child in node.get_children():
		_collect_text(child, out)


func _buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_buttons(child))
	return out


func _spins(node: Node) -> Array[SpinBox]:
	var out: Array[SpinBox] = []
	if node is SpinBox:
		out.append(node)
	for child in node.get_children():
		out.append_array(_spins(child))
	return out


func _button_for(node: Node, text: String) -> Button:
	for button in _buttons(node):
		if button.text == text:
			return button
	return null


func _largest_font(node: Node) -> int:
	var largest: int = 0
	for control in _text_controls(node):
		largest = maxi(largest, control.get_theme_font_size("font_size"))
	return largest


func _path_of(root: Node, control: Control) -> String:
	var bits: PackedStringArray = PackedStringArray()
	var current: Node = control
	while current != null and current != root:
		bits.insert(0, current.name)
		current = current.get_parent()
	bits.insert(0, root.name)
	return "/".join(bits)


func _addon_sources() -> PackedStringArray:
	var names := PackedStringArray()
	_walk_gd(ADDON_DIR, names)
	return names


func _walk_gd(dir_path: String, names: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			names.append(file_name)
	for nested in dir.get_directories():
		_walk_gd(dir_path.path_join(nested), names)


func _source_of(file_name: String) -> String:
	var path: String = ADDON_DIR.path_join(file_name)
	if not FileAccess.file_exists(path):
		path = ADDON_DIR.path_join("gizmos").path_join(file_name)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("cannot read " + file_name)
		return ""
	return file.get_as_text()


func _init() -> void:
	for case_name in _case_names():
		call(case_name)
		_ran += 1
	if _fails != 0:
		push_error(str(_fails) + " failures")
		quit(1)
	else:
		print("chrome_smoke ok cases=%d" % _ran)
		quit(0)


func _case_names() -> PackedStringArray:
	var names := PackedStringArray()
	var filter: String = OS.get_environment("SLAB_CASE")
	for method in get_method_list():
		var method_name: String = method.name
		if not method_name.begins_with("case_"):
			continue
		if filter != "" and method_name != filter and method_name != "case_" + filter:
			continue
		names.append(method_name)
	return names


func expect(ok: bool, what: String) -> void:
	if ok:
		print("ok ", what)
		return
	push_error("FAIL " + what)
	print("FAIL ", what)
	_fails += 1
