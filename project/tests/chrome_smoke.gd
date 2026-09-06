extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")

const ADDON_DIR := "res://addons/slab"

const EDITOR_INTERFACE_ALLOWLIST: PackedStringArray = [
	"plugin.gd",
	"slab_editor_host_live.gd",
	"slab_actions.gd",
]

const EDITOR_INTERFACE_FENCE: PackedStringArray = [
	"slab_viewport.gd",
	"slab_panel.gd",
	"slab_mode_strip.gd",
	"slab_pick.gd",
]

const SCALES: PackedFloat32Array = [0.75, 1.0, 1.25, 1.5, 2.0]
const MODES: Array = [
	SlabSelection.Mode.OBJECT, SlabSelection.Mode.VERTEX, SlabSelection.Mode.EDGE, SlabSelection.Mode.FACE,
]

var _fails := 0
var _ran := 0


func case_every_panel_font_clears_the_floor_at_every_scale() -> void:
	for scale in SCALES:
		for mode in MODES:
			var panel := _build_panel(scale, mode)
			for control in _text_controls(panel):
				var size: int = control.get_theme_font_size("font_size")
				expect(size >= SlabMetrics.FONT_FLOOR,
					"at scale %.2f in %s mode, panel %s renders at %d, floor is %d" % [
						scale, SlabSelection.MODE_LABELS[mode], _path_of(panel, control), size, SlabMetrics.FONT_FLOOR
					])
			panel.free()
		var strip := _build_strip(scale)
		for control in _text_controls(strip):
			var size: int = control.get_theme_font_size("font_size")
			expect(size >= SlabMetrics.FONT_FLOOR,
				"at scale %.2f, strip %s renders at %d, floor is %d" % [
					scale, _path_of(strip, control), size, SlabMetrics.FONT_FLOOR
				])
		strip.free()


func case_every_text_control_declares_a_font_size() -> void:
	for mode in MODES:
		var panel := _build_panel(1.0, mode)
		for control in _text_controls(panel):
			expect(control.has_theme_font_size_override("font_size"),
				"in %s mode, %s declares its own font_size instead of inheriting one" % [
					SlabSelection.MODE_LABELS[mode], _path_of(panel, control)
				])
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
	panel.free()


func case_rebuild_blocks_button_signals_before_it_clears_them() -> void:
	var source: String = _source_of("slab_panel.gd")
	var rebuild: int = source.find("func _rebuild_commands")
	var block: int = source.find("set_block_signals", rebuild)
	var clear: int = source.find("_buttons.clear()", rebuild)
	expect(rebuild != -1 and block != -1 and clear != -1 and block < clear,
		"rebuild blocks button signals before it clears _buttons")


func case_command_buttons_are_icons_named_in_the_tooltip() -> void:
	var panel := _build_panel(1.0)
	var stair: Button = _button_for(panel, "Stair")
	expect(stair != null, "Object mode still has Stair")
	expect(stair.text == "", "Stair has no caption")
	expect(stair.icon != null, "Stair has an icon outside the editor")
	expect(stair.icon.get_width() == int(16.0 * SlabIcons.RASTER_SCALE),
		"bundled icons rasterize at %d px, got %d" % [int(16.0 * SlabIcons.RASTER_SCALE), stair.icon.get_width()])
	expect(SlabIcons.texture("BoxMesh", 2.0).get_width() == int(16.0 * SlabIcons.RASTER_SCALE * 2.0),
		"scale 2 doubles the raster, got %d" % SlabIcons.texture("BoxMesh", 2.0).get_width())
	expect(stair.tooltip_text.begins_with("Stair"), "the tooltip leads with the command name, got %s" % stair.tooltip_text)
	expect(stair.tooltip_text.contains("8 steps"), "the tooltip still carries the live shape phrase")
	expect(is_equal_approx(stair.custom_minimum_size.x, SlabPanel.BUTTON_SIZE.x),
		"the cell is the icon size, got %s" % stair.custom_minimum_size)
	panel.free()


func case_a_twelve_px_svg_vector_rasters_to_the_cell() -> void:
	var svg := FileAccess.get_file_as_string("res://addons/slab/icons/CurveIn.svg")
	expect(svg != "", "CurveIn.svg reads")
	var native := Image.new()
	expect(native.load_svg_from_string(svg, 1.0) == OK and native.get_width() == 12,
		"CurveIn canvas is 12 px, got %d" % native.get_width())
	var stretched := Image.new()
	stretched.load_svg_from_string(svg, SlabIcons.RASTER_SCALE)
	expect(stretched.get_width() == 24, "scale 2 of a 12 px canvas is 24 px, got %d" % stretched.get_width())
	stretched.resize(int(16.0 * SlabIcons.RASTER_SCALE), int(16.0 * SlabIcons.RASTER_SCALE), Image.INTERPOLATE_BILINEAR)
	var vector := Image.new()
	vector.load_svg_from_string(svg, 16.0 * SlabIcons.RASTER_SCALE / 12.0)
	expect(vector.get_data() != stretched.get_data(),
		"a bilinear stretch of 24 px is not the same as a 32 px SVG raster")
	var got: Image = SlabIcons.texture("CurveIn").get_image()
	expect(got != null and got.get_data() == vector.get_data(),
		"CurveIn matches the 32 px vector raster, not a stretch")


func case_every_command_icon_rasterizes_outside_the_editor() -> void:
	var fallback: Texture2D = SlabIcons.texture(SlabIcons.FALLBACK)
	expect(fallback != null, "the Node3D fallback rasterizes")
	var seen := {}
	for row in SlabActions.new().rows():
		var name: String = row["icon"]
		if seen.has(name):
			continue
		seen[name] = true
		expect(FileAccess.file_exists("res://addons/slab/icons/%s.svg" % name),
			"row %s has a bundled svg named %s" % [row["id"], name])
		var tex: Texture2D = SlabIcons.texture(name)
		expect(tex != null and tex != fallback, "row %s rasterizes %s, not the fallback" % [row["id"], name])
		expect(tex.get_width() == int(16.0 * SlabIcons.RASTER_SCALE) and tex.get_height() == int(16.0 * SlabIcons.RASTER_SCALE),
			"row %s %s is 32 px square, got %dx%d" % [row["id"], name, tex.get_width(), tex.get_height()])
	for mode in SlabModeStrip.MODE_ICONS:
		var name: String = SlabModeStrip.MODE_ICONS[mode]
		expect(FileAccess.file_exists("res://addons/slab/icons/%s.svg" % name),
			"mode %s has a bundled svg named %s" % [SlabSelection.MODE_LABELS[mode], name])
		var tex: Texture2D = SlabIcons.texture(name)
		expect(tex != null and tex != fallback,
			"mode %s rasterizes %s, not the fallback" % [SlabSelection.MODE_LABELS[mode], name])
		expect(tex.get_width() == int(16.0 * SlabIcons.RASTER_SCALE),
			"mode %s %s is 32 px, got %d" % [SlabSelection.MODE_LABELS[mode], name, tex.get_width()])


func case_command_icons_are_unique_inside_each_mode() -> void:
	var actions := SlabActions.new()
	for mode in MODES:
		var label: String = SlabSelection.MODE_LABELS[mode]
		var seen := {}
		var strip: String = SlabModeStrip.MODE_ICONS[mode]
		for section in actions.command_sections_for(mode):
			for row in section["rows"]:
				var name: String = row["icon"]
				if name == strip:
					expect(false, "%s reuses the %s mode icon %s" % [row["id"], label, strip])
				else:
					expect(true, "%s does not reuse the %s mode icon" % [row["id"], label])
				if seen.has(name):
					expect(false, "%s and %s share %s in %s mode" % [seen[name], row["id"], name, label])
				else:
					expect(true, "%s uses %s in %s mode" % [row["id"], name, label])
					seen[name] = row["id"]


func case_face_mode_shows_only_face_and_selection_commands() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	expect(_button_for(panel, "Extrude") == null, "Object mode does not render the Extrude button")
	selection.mode = SlabSelection.Mode.FACE
	expect(_label_for(panel, "CREATE") == null, "Face mode does not render a Create heading")
	expect(_button_for(panel, "Stair") == null, "Face mode does not render the Stair button")
	for field in actions.shapes.fields():
		var key: String = String(field["key"])
		expect(panel.find_child(key, true, false) == null, "Face mode does not render the %s Create field" % key)
	expect(_spins(panel).size() == 7, "Face mode keeps the 7 edit spins, got %d" % _spins(panel).size())
	expect(_label_for(panel, "FACE") != null and _label_for(panel, "SELECTION") != null,
		"Face mode renders the Face and Selection headings")
	expect(_button_for(panel, "Select Loop") == null, "Face mode does not render the Edge-only Select Loop")
	var extrude: Button = _button_for(panel, "Extrude")
	expect(extrude != null and extrude.disabled and extrude.tooltip_text == "Extrude needs 1 face.",
		"Extrude stays on the dock, disabled for count, with the old wording")
	var before: PackedStringArray = _command_tree_signature(panel)
	panel.refresh()
	expect(_command_tree_signature(panel) == before, "a second Face refresh keeps the same class and label order")
	selection.set_ids(PackedInt64Array([7]))
	expect(_button_for(panel, "Extrude") == extrude and not extrude.disabled,
		"picking a face enables the same Extrude button instead of rebuilding the column")
	selection.mode = SlabSelection.Mode.OBJECT
	expect(_button_for(panel, "Extrude") == null and _button_for(panel, "Stair") != null,
		"returning to Object mode brings the Create buttons back and drops Extrude")
	panel.free()


func case_a_half_typed_create_field_commits_on_mode_change() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	root.add_child(panel)
	var steps: SpinBox = _spins(panel.find_child("stair_steps", true, false))[0]
	steps.get_line_edit().text = "20"
	selection.mode = SlabSelection.Mode.FACE
	expect(is_equal_approx(actions.shapes.value_of(&"stair_steps"), 20.0),
		"leaving Object mode applies a half-typed Steps value, got %s" % actions.shapes.value_of(&"stair_steps"))
	selection.mode = SlabSelection.Mode.OBJECT
	var stair: Button = _button_for(panel, "Stair")
	expect(stair != null and stair.tooltip_text.contains("20 steps"),
		"the rebuilt Stair tooltip follows the committed steps, got %s" % stair.tooltip_text)
	panel.free()


func case_command_grids_fit_once_the_panel_has_a_width() -> void:
	var panel := _build_panel(1.0)
	var grid: GridContainer = _first_grid(panel)
	expect(grid != null, "Object mode has a command grid")
	expect(grid.columns == SlabPanel.DEFAULT_COLUMNS,
		"a detached panel keeps the default column count, got %d" % grid.columns)
	root.add_child(panel)
	panel.size = Vector2(1600.0, 320.0)
	# Setting size on a SceneTree harness does not emit resized.
	panel.resized.emit()
	expect(grid.columns == int(1600.0 / (SlabPanel.BUTTON_SIZE.x + SlabPanel.GRID_SEPARATION)),
		"1600 px fits as many icon cells as the stride allows, got %d" % grid.columns)
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


func case_unlabeled_mode_strip_names_the_mode() -> void:
	var selection := SlabSelection.new()
	var strip := SlabModeStrip.new()
	strip.setup(selection, false, SlabMetrics.at_scale(1.0))
	for button in _buttons(strip):
		var mode: int = int(button.get_meta("slab_mode"))
		var label: String = SlabSelection.MODE_LABELS[mode]
		expect(button.text == "", "the spatial strip has no caption for %s" % label)
		expect(button.tooltip_text.begins_with(label),
			"the unlabeled %s tooltip leads with the mode name, got %s" % [label, button.tooltip_text])
		expect(button.tooltip_text.contains(OS.get_keycode_string(SlabModeStrip.keycode_for(mode))),
			"the unlabeled %s tooltip still names the shortcut" % label)
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


func _build_panel(scale: float, mode: int = SlabSelection.Mode.OBJECT) -> SlabPanel:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(scale))
	selection.mode = mode
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


func _button_for(node: Node, label: String) -> Button:
	for button in _buttons(node):
		if String(button.get_meta("slab_label", "")) == label:
			return button
	return null


func _first_grid(node: Node) -> GridContainer:
	if node is GridContainer:
		return node
	for child in node.get_children():
		var found: GridContainer = _first_grid(child)
		if found != null:
			return found
	return null


func _label_for(node: Node, text: String) -> Label:
	if node is Label and node.text == text:
		return node
	for child in node.get_children():
		var found: Label = _label_for(child, text)
		if found != null:
			return found
	return null


func _command_tree_signature(panel: SlabPanel) -> PackedStringArray:
	var out := PackedStringArray()
	_sign(panel.find_child("Commands", true, false), 0, out)
	return out


func _sign(node: Node, depth: int, out: PackedStringArray) -> void:
	if node == null:
		return
	var bits: PackedStringArray = [str(depth), node.get_class()]
	if not String(node.name).begins_with("@"):
		bits.append(node.name)
	if node is Label:
		bits.append(node.text)
	if node is Button:
		bits.append(String(node.get_meta("slab_label", "")))
	out.append(" ".join(bits))
	for child in node.get_children():
		_sign(child, depth + 1, out)


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
