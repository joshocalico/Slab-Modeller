extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabModeStrip := preload("res://addons/slab/slab_mode_strip.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabIcons := preload("res://addons/slab/slab_icons.gd")
const SlabPlugin := preload("res://addons/slab/plugin.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")

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
	"slab_paint.gd",
	"slab_paint_uv.gd",
	"slab_paint_raster.gd",
	"slab_paint_canvas.gd",
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
	var spins: Array[SpinBox] = _spins(panel.find_child("Settings", true, false))
	var box_fields: Array[Dictionary] = actions.shapes.fields_for(&"make_box")
	expect(spins.size() == box_fields.size(), "Object mode starts with the Box fields only, got %d" % spins.size())
	for field in box_fields:
		var named: Node = panel.find_child(String(field["key"]), true, false)
		expect(named != null, "the %s field has a spin" % field["key"])
		if named != null:
			var spin: SpinBox = _spins(named)[0]
			expect(is_equal_approx(spin.value, field["value"]), "the %s spin starts at %s" % [field["key"], field["value"]])
			expect(spin.tooltip_text == field["tooltip"], "the %s spin carries the field tooltip" % field["key"])
	expect(panel.find_child("stair_steps", true, false) == null, "Box focus hides the Stair steps field")
	panel.free()


func case_create_tooltips_follow_the_fields() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	panel.focus_create(&"make_stair")
	var stair: Button = _button_for(panel, "Stair")
	expect(stair != null and stair.tooltip_text.contains("8 steps"), "the Stair button starts by saying 8 steps")
	var steps: SpinBox = _spins(panel.find_child("stair_steps", true, false))[0]
	# Range only emits value_changed inside the tree. This case never adds the panel to it.
	steps.value = 20.0
	steps.value_changed.emit(steps.value)
	expect(stair.tooltip_text.contains("20 steps") and not stair.tooltip_text.contains("8 steps"),
		"turning the Steps spin rewrites the Stair tooltip, got %s" % stair.tooltip_text)
	panel.free()


func case_uv_quick_actions_update_the_spins() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([7]))
	var scale_x: SpinBox = _spins(panel.find_child("uv_scale_x", true, false))[0]
	var rotation: SpinBox = _spins(panel.find_child("uv_rotation", true, false))[0]
	expect(is_equal_approx(scale_x.value, 1.0), "UV scale X starts at 1")
	actions.run("uv_scale_up")
	expect(is_equal_approx(scale_x.value, 2.0), "UV Larger writes 2 into the spin, got %s" % scale_x.value)
	actions.run("uv_scale_up")
	expect(is_equal_approx(scale_x.value, 4.0), "a second UV Larger writes 4 into the spin, got %s" % scale_x.value)
	actions.run("uv_rotate")
	expect(is_equal_approx(rotation.value, 90.0), "UV Rotate writes 90 into the spin, got %s" % rotation.value)
	actions.run("uv_reset")
	expect(is_equal_approx(scale_x.value, 1.0) and is_equal_approx(rotation.value, 0.0),
		"UV Reset restores the spins, got scale %s rotation %s" % [scale_x.value, rotation.value])
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
	expect(stair.text == "Stair", "Stair shows its name")
	expect(stair.icon != null, "Stair has an icon outside the editor")
	expect(stair.icon.get_width() == int(16.0 * SlabIcons.RASTER_SCALE),
		"bundled icons rasterize at %d px, got %d" % [int(16.0 * SlabIcons.RASTER_SCALE), stair.icon.get_width()])
	expect(SlabIcons.texture("BoxMesh", 2.0).get_width() == int(16.0 * SlabIcons.RASTER_SCALE * 2.0),
		"scale 2 doubles the raster, got %d" % SlabIcons.texture("BoxMesh", 2.0).get_width())
	expect(stair.tooltip_text.begins_with("Stair"), "the tooltip leads with the command name, got %s" % stair.tooltip_text)
	expect(stair.tooltip_text.contains("8 steps"), "the tooltip still carries the live shape phrase")
	expect(not stair.clip_text, "Stair does not clip its caption")
	_expect_label_fits(stair, "Stair")
	panel.free()


func case_command_icon_fits_inside_the_cell() -> void:
	var panel := _build_panel(1.0)
	var stair: Button = _button_for(panel, "Stair")
	_expect_icon_fits(stair, "Stair")
	panel.free()
	var strip := _build_strip(1.0)
	for button in _buttons(strip):
		_expect_icon_fits(button, button.text)
	strip.free()


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


func case_stair_uses_the_material_design_stairs_glyph() -> void:
	var svg := FileAccess.get_file_as_string("res://addons/slab/icons/Stair.svg")
	expect(svg.contains('viewBox="0 0 24 24"'), "Stair.svg keeps the MDI 24x24 viewBox")
	expect(svg.contains("M15,5V9H11V13H7V17H3V20H10V16H14V12H18V8H22V5H15Z"),
		"Stair.svg keeps the MDI stairs path")
	var notice := FileAccess.get_file_as_string("res://addons/slab/icons/NOTICE")
	expect(notice.contains("Godot Engine editor icons"), "NOTICE still credits Godot icons")
	expect(notice.contains("Apache License, Version 2.0"), "NOTICE names Apache for Stair")
	expect(FileAccess.file_exists("res://addons/slab/icons/Apache-2.0.txt"),
		"Apache-2.0.txt sits next to Stair.svg")


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
	expect(_spins(panel.find_child("Settings", true, false)).size() == 6, "Face mode keeps Distance and the five UV spins, got %d" % _spins(panel.find_child("Settings", true, false)).size())
	expect(is_equal_approx(panel.custom_minimum_size.y, SlabPanel.PANEL_HEIGHT),
		"the dock stays compact, got %s" % panel.custom_minimum_size.y)
	expect(_label_for(panel, "FACE") != null and _label_for(panel, "SELECTION") != null,
		"Face mode renders the Face and Selection headings")
	expect(_label_for(panel, "UV") != null, "Face mode renders a UV heading")
	var uv_wrap: Node = panel.find_child("UvFields", true, false)
	expect(uv_wrap != null and not uv_wrap.visible, "UV spins start hidden")
	expect(_button_for(panel, "Select Loop") == null, "Face mode does not render the Edge-only Select Loop")
	var extrude: Button = _button_for(panel, "Extrude")
	expect(extrude != null and extrude.text == "Extrude", "Extrude shows its name")
	expect(not extrude.clip_text, "Extrude does not clip its caption")
	_expect_label_fits(extrude, "Extrude")
	expect(extrude.disabled and extrude.tooltip_text == "Extrude needs 1 face.",
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


func case_surface_paint_opens_a_canvas_not_just_uv_fields() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var paint: RefCounted = preload("res://addons/slab/slab_paint.gd").new()
	paint.bind(selection, actions, SlabTestUndo.new())
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	panel.bind_paint(paint)
	var toggle: Button = panel.find_child("SurfacePaint", true, false)
	expect(toggle != null and toggle.text == "Surface Paint", "the dock names Surface Paint")
	expect(panel.find_child("PaintCanvas", true, false) != null, "the dock has a texture canvas")
	expect(panel.find_child("PaintBody", true, false) != null, "the dock has a paint workspace")
	expect(not panel.find_child("PaintBody", true, false).visible, "paint starts closed")
	paint.enter()
	expect(panel.find_child("PaintBody", true, false).visible, "Surface Paint shows the workspace")
	expect(not panel.find_child("ModelBody", true, false).visible, "modeling commands hide while painting")
	expect(panel.custom_minimum_size.y > SlabPanel.PANEL_HEIGHT, "the paint dock is taller than the model strip")
	expect(_button_for(panel, "Pixel") != null and _button_for(panel, "Material / UV") != null,
		"paint has distinct Material/UV and Pixel tools")
	expect(_button_for(panel, "Make Unique") != null, "Make Unique is labeled")
	expect(panel.find_child("BrushColor", true, false) != null, "brush color sits next to the canvas")
	expect(is_equal_approx(panel.custom_minimum_size.y, preload("res://addons/slab/slab_paint.gd").PAINT_HEIGHT),
		"the paint dock stays bounded so the 3D viewport keeps height")
	expect(panel.find_child("PaintPalette", true, false) is ScrollContainer,
		"the material palette scrolls in one strip")
	expect(panel.find_child("PaintPalette", true, false).custom_minimum_size.y <= 40.5,
		"the named palette is a 40px strip")
	expect(panel.get_combined_minimum_size().y <= preload("res://addons/slab/slab_paint.gd").PAINT_HEIGHT + 0.5,
		"the paint dock combined minimum stays bounded, got %s" % panel.get_combined_minimum_size().y)
	expect(panel.find_child("PaintUvHint", true, false) != null
		and String(panel.find_child("PaintUvHint", true, false).text).contains("rotates"),
		"UV modifiers have a compact hint")
	expect(panel.find_child("PaintMaterialPickerWrap", true, false) != null,
		"the material picker is clipped to the action row")
	expect(panel.find_child("PaintActions", true, false) != null
		and panel.find_child("PaintActions", true, false).custom_minimum_size.y <= 28.5,
		"paint actions are a 28px row")
	expect(_source_of("slab_solid_gizmo.gd").contains("_paint_hides_albedo"),
		"Surface Paint drops the opaque face fill")
	expect(_source_of("slab_solid_gizmo.gd").contains("PAINT_EDGE"),
		"Surface Paint keeps an on-top face outline")
	var unique_off: Button = _button_for(panel, "Make Unique")
	expect(unique_off != null and unique_off.disabled, "Make Unique stays off until a face is selected")
	paint.tool = preload("res://addons/slab/slab_paint.gd").Tool.PIXEL
	var pixel: Button = _button_for(panel, "Pixel")
	var uv: Button = _button_for(panel, "Material / UV")
	expect(pixel != null and pixel.button_pressed and uv != null and not uv.button_pressed,
		"Pixel vs Material/UV shows which tool is selected")
	paint.exit()
	expect(panel.find_child("ModelBody", true, false).visible, "closing paint restores modeling")
	panel.free()


func case_a_half_typed_create_field_commits_on_mode_change() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	root.add_child(panel)
	panel.focus_create(&"make_stair")
	var steps: SpinBox = _spins(panel.find_child("stair_steps", true, false))[0]
	var hits := {"n": 0}
	steps.value_changed.connect(func(_v: float) -> void: hits["n"] += 1)
	steps.get_line_edit().text = "20"
	selection.mode = SlabSelection.Mode.FACE
	expect(hits["n"] == 1, "leaving Object mode commits Steps once, got %d" % hits["n"])
	expect(is_equal_approx(actions.shapes.value_of(&"stair_steps"), 20.0),
		"leaving Object mode applies a half-typed Steps value, got %s" % actions.shapes.value_of(&"stair_steps"))
	selection.mode = SlabSelection.Mode.OBJECT
	var stair: Button = _button_for(panel, "Stair")
	expect(stair != null and stair.tooltip_text.contains("20 steps"),
		"the rebuilt Stair tooltip follows the committed steps, got %s" % stair.tooltip_text)
	panel.free()


func case_stair_sits_on_the_create_row() -> void:
	var panel := _build_panel(1.0)
	var flow: HFlowContainer = _first_command_row(panel)
	expect(flow != null, "Object mode has a Create flow")
	var labels: PackedStringArray = PackedStringArray()
	for child in flow.get_children():
		if child is Button:
			labels.append(String(child.get_meta("slab_label", "")))
	expect(labels.has("Stair"), "Create lists Stair, got %s" % [labels])
	expect(labels.find("Stair") == 2, "Stair stays the third Create icon after Box and Plane, got %s" % [labels])
	var stair: Button = _button_for(panel, "Stair")
	expect(stair.icon != null, "Stair has a glyph")
	panel.focus_create(&"make_stair")
	expect(panel.find_child("stair_steps", true, false) != null, "focusing Stair shows Steps")
	expect(panel.find_child("arch_arc", true, false) == null, "Stair focus hides Arch's Arc")
	panel.free()


func case_create_icons_sit_above_the_settings() -> void:
	var panel := _build_panel(1.0)
	var commands: Node = panel.find_child("Commands", true, false)
	var settings: Node = panel.find_child("Settings", true, false)
	expect(commands != null and settings != null, "the dock has Commands and Settings")
	expect(commands.get_parent().get_parent() == settings.get_parent(),
		"command icons and settings share the model body")
	expect(commands.get_parent().get_index() < settings.get_index(),
		"command icons sit above the settings strip")
	expect(_button_for(panel, "Stair").get_parent().get_parent() == commands,
		"Stair lives in the command column, not the settings strip")
	panel.free()


func case_command_labels_fit_and_wrap() -> void:
	var panel := _build_panel(1.0)
	var flow: HFlowContainer = _first_command_row(panel)
	expect(flow != null, "Object mode lays commands in a wrapping flow")
	for label in ["Box", "Cylinder", "Mirror X", "Mirror Y", "Mirror Z", "Center Pivot", "Snap To Grid"]:
		var button: Button = _button_for(panel, label)
		expect(button != null, "%s is on the Object dock" % label)
		expect(not button.clip_text, "%s does not clip its caption" % label)
		_expect_label_fits(button, label)
	for label in ["Mirror X", "Center Pivot", "Snap To Grid"]:
		var button: Button = _button_for(panel, label)
		expect(button.get_minimum_size().x > 76.0,
			"%s is wider than the old clipped cell, got %.1f" % [label, button.get_minimum_size().x])
	root.add_child(panel)
	panel.size = Vector2(1226.0, 320.0)
	panel.resized.emit()
	for label in ["Box", "Mirror X"]:
		var button: Button = _button_for(panel, label)
		expect(button.get_minimum_size().x <= 1226.0, "%s can sit on a 1226 px dock" % label)
		expect(button.size.x >= 40.0,
			"%s keeps a hit target, size=%s min=%s" % [label, button.size, button.custom_minimum_size])
	panel.free()
	var face := _build_panel(1.0, SlabSelection.Mode.FACE)
	for label in ["Extrude", "Inset", "Flip Normals"]:
		var button: Button = _button_for(face, label)
		expect(button != null, "%s is on the Face dock" % label)
		expect(not button.clip_text, "%s does not clip its caption" % label)
		_expect_label_fits(button, label)
	face.free()
	var edge := _build_panel(1.0, SlabSelection.Mode.EDGE)
	var loop: Button = _button_for(edge, "Insert Loop")
	expect(loop != null and not loop.clip_text, "Insert Loop does not clip its caption")
	_expect_label_fits(loop, "Insert Loop")
	edge.free()


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


func case_primary_panel_buttons_are_keyboard_reachable_and_named() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	var paint: RefCounted = preload("res://addons/slab/slab_paint.gd").new()
	paint.bind(selection, actions, SlabTestUndo.new())
	panel.bind_paint(paint)
	root.add_child(panel)

	var expected: Array[Button] = []
	for button in _buttons(panel):
		if button.has_meta("slab_mode") or button.has_meta("slab_label") or button.name == "SurfacePaint":
			expected.append(button)
	for button in expected:
		expect(button.focus_mode == Control.FOCUS_ALL, "%s is reachable by keyboard focus" % button.name)
		expect(button.accessibility_name != "", "%s has an accessible name" % button.name)

	var box: Button = panel.find_child("make_box", true, false)
	var surface: Button = panel.find_child("SurfacePaint", true, false)
	expect(box != null and box.accessibility_name == "Box", "Create Box has its visible accessible name")
	expect(surface != null and surface.accessibility_name == "Surface Paint", "Surface Paint has its visible accessible name")
	if box != null:
		box.grab_focus()
		expect(root.get_viewport().gui_get_focus_owner() == box, "Create Box accepts keyboard focus")
	if surface != null:
		surface.grab_focus()
		expect(root.get_viewport().gui_get_focus_owner() == surface, "Surface Paint accepts keyboard focus")
	panel.free()


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
	expect(source.contains("set_process_shortcut_input"), "plugin.gd listens for editor shortcuts")
	expect(source.contains("main_screen_changed"), "plugin.gd tracks the named main screen")
	expect(not source.contains("get_base_control().gui_get_focus_owner"),
		"plugin.gd does not call gui_get_focus_owner on the base Panel")
	expect(not source.contains("get_editor_main_screen().is_ancestor_of"),
		"shortcut scope does not treat the shared main-screen container as the active screen")


func case_shortcut_gate_queries_the_viewport_and_stays_in_3d() -> void:
	var line := LineEdit.new()
	root.add_child(line)
	line.grab_focus()
	var focus: Control = SlabPlugin.focus_owner(root.get_viewport())
	expect(focus == line, "focus comes from Viewport.gui_get_focus_owner, got %s" % focus)
	expect(SlabPlugin.focus_eats_keys(focus), "a LineEdit keeps E for typing")
	line.release_focus()
	line.free()

	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.pressed = true
	var screen := Control.new()
	var viewport_3d := SubViewport.new()
	screen.add_child(viewport_3d)
	root.add_child(screen)
	expect(SlabPlugin.spatial_editor_is_active(viewport_3d, "3D"),
		"a visible 3D viewport is the modeling context")
	expect(SlabPlugin.should_claim_shortcut(event, viewport_3d, root.get_viewport(), "3D"),
		"E is claimed in the 3D editor when nothing is typing")
	expect(not SlabPlugin.spatial_editor_is_active(viewport_3d, "Script"),
		"the Script workspace is not the modeling context")
	expect(not SlabPlugin.should_claim_shortcut(event, viewport_3d, root.get_viewport(), "2D"),
		"E is left to Godot on the 2D workspace")
	screen.visible = false
	expect(not SlabPlugin.spatial_editor_is_active(viewport_3d, "3D"),
		"a hidden 3D viewport is not active")
	screen.visible = true
	var typing := LineEdit.new()
	root.add_child(typing)
	typing.grab_focus()
	expect(not SlabPlugin.should_claim_shortcut(event, viewport_3d, root.get_viewport(), "3D"),
		"E is left to Godot while a LineEdit has focus")
	typing.release_focus()
	var dock := Button.new()
	dock.text = "Dock"
	root.add_child(dock)
	dock.grab_focus()
	expect(SlabPlugin.focus_is_outside_spatial_editor(dock, viewport_3d),
		"a dock control is outside the spatial editor")
	expect(not SlabPlugin.should_claim_shortcut(event, viewport_3d, root.get_viewport(), "3D"),
		"E is left to Godot when a dock has focus")
	dock.release_focus()
	screen.free()
	typing.free()
	dock.free()


func case_object_settings_are_for_the_next_shape() -> void:
	var panel := _build_panel(1.0)
	var title: Label = panel.find_child("SettingsTitle", true, false)
	expect(title != null and title.text == "New Box", "Object mode labels Box fields as New Box, got %s" % (title.text if title else "missing"))
	panel.focus_create(&"make_cylinder")
	expect(title.text == "New Cylinder", "Cylinder focus relabels the strip, got %s" % title.text)
	panel.free()


func case_face_distance_accepts_a_negative_extrude() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	selection.mode = SlabSelection.Mode.FACE
	var amount: SpinBox = _spins(panel.find_child("amount", true, false))[0]
	expect(amount.min_value < 0.0, "Face distance allows inward values, min %s" % amount.min_value)
	amount.value = -1.0
	amount.value_changed.emit(amount.value)
	expect(is_equal_approx(actions.amount, -1.0), "typing -1 keeps -1, got %s" % actions.amount)
	expect(is_equal_approx(amount.value, -1.0), "the spin does not clamp -1 up to 0.05")
	panel.free()


func case_add_material_defers_chip_rebuild() -> void:
	var source: String = _source_of("slab_panel.gd")
	var add: int = source.find("func _add_material")
	expect(add != -1, "_add_material exists")
	expect(source.find("call_deferred(\"_refresh_material_chips\")", add) != -1,
		"Add Material defers chip rebuild so it does not free the emitting button")
	expect(source.find("queue_free()", source.find("func _refresh_material_chips")) != -1,
		"chip refresh retires rows with queue_free")
	expect(_source_of("slab_actions.gd").contains("func add_material"),
		"material array edits go through SlabActions for undo")


func case_add_material_keeps_plus_alive_during_pressed() -> void:
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		expect(false, "SlabSolid is built")
		return
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	root.add_child(solid)
	expect(solid.call("make_box", Vector3(2, 2, 2)) == 0, "material-chip box builds")
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	var add: Button = panel.find_child("add_material", true, false)
	expect(add != null, "Face mode shows Add Material when a solid is selected")
	if add == null:
		panel.free()
		solid.free()
		return
	var before: int = (solid.get("materials") as Array).size()
	add.pressed.emit()
	expect(is_instance_valid(add), "Add Material is not freed while emitting pressed")
	expect((solid.get("materials") as Array).size() == before + 1, "Add Material still appends a slot")
	panel.free()
	solid.free()


func case_material_undo_and_redo_refresh_the_palette() -> void:
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		expect(false, "SlabSolid is built")
		return
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	root.add_child(solid)
	expect(solid.call("make_box", Vector3(2, 2, 2)) == 0, "palette box builds")
	var selection := SlabSelection.new()
	var undo := SlabTestUndo.new()
	var actions := SlabActions.new(selection, undo)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	panel.bind_undo(undo)
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	actions.add_material()
	actions.add_material()
	panel.refresh()
	expect(_chip_count(panel) == 2, "two adds show two chips, got %d" % _chip_count(panel))
	expect(actions.material_slot == 1, "the new slot is active, got %d" % actions.material_slot)
	var first: Button = panel.find_child("material_0", true, false)
	expect(first != null, "the first chip exists")
	first.pressed.emit()
	panel.refresh()
	expect(actions.material_slot == 0, "clicking the first chip selects slot 0")
	undo.undo()
	panel.refresh()
	expect((solid.get("materials") as Array).size() == 1, "undo leaves one material, got %d" % (solid.get("materials") as Array).size())
	expect(_chip_count(panel) == 1, "the palette drops the undone chip, got %d" % _chip_count(panel))
	expect(actions.material_slot == 0, "the active slot is clamped or restored to 0, got %d" % actions.material_slot)
	undo.redo()
	panel.refresh()
	expect((solid.get("materials") as Array).size() == 2, "redo restores both materials, got %d" % (solid.get("materials") as Array).size())
	expect(_chip_count(panel) == 2, "redo restores the second chip, got %d" % _chip_count(panel))
	expect(panel.find_child("material_1", true, false) != null, "slot 1 is a chip again")
	panel.free()
	solid.free()


func case_status_wraps_a_long_recovery_message() -> void:
	var panel := _build_panel(1.0)
	var status: Label = panel.find_child("Status", true, false)
	expect(status != null, "the dock has a Status label")
	var copy: String = SlabActions.describe_error(SlabActions.ERR_NOT_CLOSED, "delete_faces")
	panel.set_status(copy)
	expect(status.text == copy, "the status keeps the full recovery copy")
	expect(status.tooltip_text == copy, "the tooltip keeps the full recovery copy")
	expect(status.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "the status wraps instead of clipping")
	expect(not status.clip_text, "the status does not clip")
	root.add_child(panel)
	status.size = Vector2(470.0, 16.0)
	expect(status.get_line_count() >= 2, "470 px of status wraps the delete copy, lines=%d" % status.get_line_count())
	panel.free()


func case_mouse_click_extrude_and_delete_run() -> void:
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		expect(false, "SlabSolid is built")
		return
	root.size = Vector2i(1280, 800)
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	root.add_child(solid)
	expect(solid.call("make_box", Vector3(4, 3, 4)) == 0, "click box builds")
	var top: int = 0
	var up := -2.0
	for id in PackedInt64Array(solid.call("get_faces")):
		var n: Vector3 = solid.call("face_normal", id)
		if n.y > up:
			up = n.y
			top = id
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var said: Array[String] = []
	actions.reported.connect(func(text: String) -> void: said.append(text))
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	root.add_child(panel)
	panel.size = Vector2(1226.0, 320.0)
	panel.resized.emit()
	selection.set_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([top]))
	expect(solid.call("inset_faces", PackedInt64Array([top]), 0.45) == 0, "inset before the click")
	actions.amount = -1.0
	await process_frame
	await process_frame
	var extrude: Button = _button_for(panel, "Extrude")
	expect(extrude != null and not extrude.disabled, "Extrude is enabled for a selected face")
	expect(not extrude.pressed.get_connections().is_empty(), "Extrude.pressed is connected to run")
	var extrude_rect: Rect2 = extrude.get_global_rect()
	expect(extrude_rect.size.x >= 40.0 and extrude_rect.size.y >= 24.0,
		"Extrude has a clickable rect, size=%s min=%s global=%s" % [
			extrude.size, extrude.get_combined_minimum_size(), extrude_rect
		])
	var status: Label = panel.find_child("Status", true, false)
	expect(status != null and not status.get_global_rect().intersects(extrude_rect),
		"Status does not cover Extrude, status=%s extrude=%s" % [
			status.get_global_rect() if status else Rect2(), extrude_rect
		])
	_hover(extrude)
	await process_frame
	var hovered: Control = panel.get_viewport().gui_get_hovered_control()
	expect(hovered == extrude, "viewport hover at Extrude is Extrude, got %s" % hovered)
	var hits := {"n": 0}
	extrude.pressed.connect(func() -> void: hits["n"] += 1)
	var before: int = solid.call("face_count")
	_mouse_click(extrude)
	expect(hits["n"] == 1, "a viewport mouse click fires Extrude.pressed, got %d size=%s rect=%s" % [
		hits["n"], extrude.size, extrude.get_global_rect()
	])
	expect(said.is_empty() or not said[0].contains("failed"),
		"mouse Extrude commits, got %s" % [said])
	expect(int(solid.call("face_count")) > before, "mouse Extrude still extrudes, faces %d after %d" % [
		solid.call("face_count"), before
	])
	var trash: Button = _button_for(panel, "Delete")
	expect(trash != null and not trash.disabled, "Delete is enabled for a selected face")
	var trash_rect: Rect2 = trash.get_global_rect()
	expect(trash_rect.size.x >= 40.0 and trash_rect.size.y >= 24.0,
		"Delete has a clickable rect, size=%s min=%s global=%s" % [
			trash.size, trash.get_combined_minimum_size(), trash_rect
		])
	said.clear()
	var trash_hits := {"n": 0}
	trash.pressed.connect(func() -> void: trash_hits["n"] += 1)
	_mouse_click(trash)
	expect(trash_hits["n"] == 1, "a viewport mouse click fires Delete.pressed, got %d rect=%s" % [
		trash_hits["n"], trash.get_global_rect()
	])
	expect(not said.is_empty() and said[0].contains("open solid"),
		"a mouse click on Delete reports the closed-solid copy, got %s" % [said])
	panel.free()
	solid.free()


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


func _expect_icon_fits(button: Button, name: String) -> void:
	var box: StyleBox = button.get_theme_stylebox("normal")
	var min_size: Vector2 = button.get_minimum_size()
	var inner_w: float = min_size.x - box.get_margin(SIDE_LEFT) - box.get_margin(SIDE_RIGHT)
	var inner_h: float = min_size.y - box.get_margin(SIDE_TOP) - box.get_margin(SIDE_BOTTOM)
	expect(inner_w >= float(button.icon.get_width()) and inner_h >= float(button.icon.get_height()),
		"%s inner size %.1fx%.1f fits a %dx%d icon" % [
			name, inner_w, inner_h, button.icon.get_width(), button.icon.get_height()
		])


func _expect_label_fits(button: Button, name: String) -> void:
	var needed: float = _label_width(button)
	expect(button.get_minimum_size().x + 0.5 >= needed,
		"%s min width %.1f covers the caption (need %.1f)" % [name, button.get_minimum_size().x, needed])


func _label_width(button: Button) -> float:
	var box: StyleBox = button.get_theme_stylebox("normal")
	var font: Font = button.get_theme_font("font")
	var font_size: int = button.get_theme_font_size("font_size")
	var text_w: float = font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var icon_w: float = float(button.icon.get_width()) if button.icon != null else 0.0
	var gap: float = float(button.get_theme_constant("h_separation")) if button.icon != null and button.text != "" else 0.0
	return box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) + icon_w + gap + text_w


func _first_command_row(panel: Node) -> HFlowContainer:
	var commands: Node = panel.find_child("Commands", true, false)
	if commands == null:
		return null
	for child in commands.get_children():
		if child is HFlowContainer:
			return child
	return null


func _chip_count(panel: Node) -> int:
	var n := 0
	var chips: Node = panel.find_child("MaterialChips", true, false)
	if chips == null:
		return 0
	for child in chips.get_children():
		if child is Button and String(child.name).begins_with("material_"):
			n += 1
	return n


func _mouse_click(control: Control) -> void:
	var rect: Rect2 = control.get_global_rect()
	var pos: Vector2 = rect.get_center()
	var vp: Viewport = control.get_viewport()
	if vp == null:
		return
	vp.push_input(_mouse_button(true, pos, pos))
	vp.push_input(_mouse_button(false, pos, pos))


func _hover(control: Control) -> void:
	var pos: Vector2 = control.get_global_rect().get_center()
	var vp: Viewport = control.get_viewport()
	if vp == null:
		return
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	vp.push_input(motion)


func _mouse_button(pressed: bool, position: Vector2, global_position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = position
	event.global_position = global_position
	return event


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
	call_deferred("_boot")


func _boot() -> void:
	await _run()


func _run() -> void:
	for case_name in _case_names():
		await Callable(self, case_name).call()
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
