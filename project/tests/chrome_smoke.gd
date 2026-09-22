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
const SlabTestGui := preload("res://tests/slab_test_gui.gd")

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


func case_transform_previews_use_the_public_solid_mesh() -> void:
	var gizmo_source := _source_of("slab_solid_gizmo.gd")
	expect(gizmo_source.contains('solid.call("build_mesh")'), "array and align ghosts acquire geometry from SlabSolid.build_mesh")
	expect(not gizmo_source.contains('get_node_or_null("__mesh")'), "ghost previews do not guess a private child name")


func case_bevel_modal_exposes_exact_controls() -> void:
	var selection := SlabSelection.new()
	selection.mode = SlabSelection.Mode.EDGE
	var actions := SlabActions.new(selection)
	actions.operation_active = true
	selection.operation_preview = {"kind": 2}
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	expect(panel.find_child("HandleAmount", true, false) != null, "Bevel modal exposes exact Amount")
	expect(panel.find_child("bevel_segments", true, false) != null, "Bevel modal exposes Segments")
	expect(_button_for(panel, "Apply") != null and _button_for(panel, "Cancel") != null, "Bevel modal exposes Apply and Cancel")
	expect(not panel.get_node("ModelBody").visible, "active operation hides unrelated modelling commands")
	expect(not panel.get_node("SelectionControls").visible, "active operation hides unrelated pivot and axis controls")
	actions.operation_active = false
	selection.operation_preview = {}
	actions.operation_state_changed.emit()
	expect(panel.get_node("ModelBody").visible and panel.get_node("SelectionControls").visible,
		"ending the operation restores modelling and selection controls")
	panel.free()


func case_isolate_button_exists_and_toggles() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	root.add_child(panel)
	var isolate_row: Control = panel.find_child("IsolateSelection", true, false)
	var isolate_solids: Button = panel.find_child("IsolateSolids", true, false)
	var isolate_faces: Button = panel.find_child("IsolateFaces", true, false)
	var isolate_label: Label = panel.find_child("IsolateLabel", true, false)
	expect(isolate_row != null, "Isolate control exists in SelectionControls")
	expect(isolate_label != null and isolate_label.text == "Isolate", "Isolate label reads Isolate")
	expect(isolate_solids != null and isolate_solids.text == "Solids", "Solids segment exists")
	expect(isolate_faces != null and isolate_faces.text == "Faces", "Faces segment exists")
	expect(isolate_solids.toggle_mode and isolate_faces.toggle_mode, "Isolate segments are toggles")
	expect(isolate_solids.disabled and isolate_faces.disabled, "Isolate segments disabled without selection")
	if ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		var scene := Node3D.new()
		root.add_child(scene)
		var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
		solid.name = "IsolateTest"
		solid.call("make_box", Vector3.ONE)
		scene.add_child(solid)
		selection.set_objects([solid])
		selection.settings_changed.emit()
		await process_frame
		expect(not isolate_solids.disabled, "Solids segment is enabled with selection")
		expect(not isolate_solids.button_pressed, "Solids segment starts unpressed")
		selection.enter_isolation(scene)
		selection.settings_changed.emit()
		await process_frame
		expect(isolate_solids.button_pressed, "Solids segment shows pressed during isolation")
		expect(not isolate_faces.button_pressed, "Faces segment stays independent of solid Isolate")
		selection.exit_isolation()
		selection.settings_changed.emit()
		await process_frame
		expect(not isolate_solids.button_pressed, "Solids segment unpressed after exit")
		var top: int = 0
		for face in solid.call("get_faces"):
			if solid.call("face_normal", face).y > 0.9:
				top = face
				break
		selection.mode = SlabSelection.Mode.FACE
		selection.set_ids(PackedInt64Array([top]))
		selection.enter_face_isolation()
		await process_frame
		expect(isolate_faces.button_pressed, "Faces segment shows pressed during face isolation")
		expect(not isolate_solids.button_pressed, "Solids segment stays off while Faces is on")
		selection.exit_face_isolation()
		await process_frame
		expect(not isolate_faces.button_pressed, "Faces segment unpressed after exit")
		scene.free()
	panel.free()


func case_soft_select_button_exists_and_toggles() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	root.add_child(panel)
	var soft_btn: Button = panel.find_child("SoftSelect", true, false)
	var soft_opts: HBoxContainer = panel.find_child("SoftSelectOptions", true, false)
	expect(soft_btn != null, "Soft Select button exists in SelectionControls")
	expect(soft_btn.text == "Soft Select", "Soft Select button text is 'Soft Select'")
	expect(soft_btn.toggle_mode, "Soft Select button is a toggle")
	expect(soft_btn.disabled, "Soft Select button disabled in Object mode")
	expect(soft_opts != null and not soft_opts.visible, "Soft Select options hidden initially")
	selection.mode = SlabSelection.Mode.FACE
	selection.settings_changed.emit()
	await process_frame
	expect(not soft_btn.disabled, "Soft Select button enabled in Face mode")
	expect(not soft_btn.button_pressed, "Soft Select button starts unpressed")
	selection.set_soft_select(true)
	selection.settings_changed.emit()
	await process_frame
	expect(soft_btn.button_pressed, "Soft Select button pressed when enabled")
	expect(soft_opts.visible, "Soft Select options visible when enabled")
	var radius: SpinBox = soft_opts.find_child("SoftRadius", true, false)
	var falloff: OptionButton = soft_opts.find_child("SoftFalloff", true, false)
	expect(radius != null, "Soft Select has Radius spin")
	expect(falloff != null, "Soft Select has Falloff option")
	selection.set_soft_select(false)
	selection.settings_changed.emit()
	await process_frame
	expect(not soft_btn.button_pressed, "Soft Select button unpressed when disabled")
	expect(not soft_opts.visible, "Soft Select options hidden when disabled")
	selection.mode = SlabSelection.Mode.OBJECT
	selection.settings_changed.emit()
	await process_frame
	expect(soft_btn.disabled, "Soft Select disabled when returning to Object mode")
	expect(soft_btn.tooltip_text.contains("Vertex"), "Object mode tooltip mentions element modes")
	panel.free()


func case_loop_cut_controls_preserve_edge_settings() -> void:
	var panel := _build_panel(1.0, SlabSelection.Mode.EDGE)
	root.add_child(panel)
	var actions: RefCounted = panel.get("_actions")
	var apply: Button = panel.find_child("LoopApply", true, false)
	var cancel: Button = panel.find_child("LoopCancel", true, false)
	var action_group: HBoxContainer = panel.find_child("LoopActions", true, false)
	expect(apply != null and cancel != null and action_group != null and not action_group.visible,
		"Loop Cut controls stay hidden outside a preview")
	expect(apply.get_parent() == action_group and cancel.get_parent() == action_group,
		"Loop Cut Apply and Cancel wrap together as one settings item")
	actions.loop_active = true
	actions.loop_can_apply = false
	actions.loop_state_changed.emit()
	expect(action_group.visible and apply.disabled and not cancel.disabled,
		"a candidate-less Loop Cut disables Apply and keeps Cancel available")
	expect(panel.find_child("loop_count", true, false).visible and panel.find_child("loop_position", true, false).visible,
		"Loop Cut keeps Cuts and Centre visible")
	expect(panel.find_child("ModelBody", true, false).visible and _button_for(panel, "Bevel") != null,
		"Loop Cut keeps ordinary Edge commands visible")
	actions.loop_can_apply = true
	actions.loop_state_changed.emit()
	expect(not apply.disabled and apply.focus_mode == Control.FOCUS_ALL and cancel.focus_mode == Control.FOCUS_ALL,
		"a valid Loop Cut enables keyboard-focusable Apply and Cancel")
	panel.free()


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
	var spins: Array[SpinBox] = _spins(panel.find_child("CreateFields", true, false))
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


func case_plane_offset_preserves_precise_input() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	actions.plane_active = true
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	var field: Node = panel.find_child("plane_offset", true, false)
	expect(field != null, "Plane Cut exposes its offset field")
	if field != null:
		var spin: SpinBox = _spins(field)[0]
		spin.value = sqrt(2.0)
		spin.value_changed.emit(spin.value)
		expect(absf(actions.plane_offset - sqrt(2.0)) < 0.000001,
			"typed plane offset retains sub-lattice precision instead of rounding to centimetres")
	panel.free()


func case_array_settings_expose_exact_linear_and_radial_values() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	actions.array_active = true
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	expect(panel.find_child("array_linear", true, false) is Button and panel.find_child("array_radial", true, false) is Button, "Array exposes visible Linear and Radial mode buttons")
	expect(panel.find_child("array_count", true, false) != null, "Array exposes total instance count")
	expect(panel.find_child("array_step_x", true, false) != null, "Linear Array exposes exact X step")
	var step_y: SpinBox = _spins(panel.find_child("array_step_y", true, false))[0]
	step_y.value = 3.25
	step_y.value_changed.emit(step_y.value)
	expect(is_equal_approx(actions.array_linear_step.y, 3.25), "Linear Y step keeps typed precision")
	actions.array_mode = SlabActions.ARRAY_RADIAL
	panel._refresh_settings()
	expect(panel.find_child("array_center_x", true, false) != null, "Radial Array exposes centre")
	expect(panel.find_child("array_axis_z", true, false) != null, "Radial Array exposes axis")
	expect(panel.find_child("array_angle", true, false) != null, "Radial Array exposes angle")
	expect(panel.find_child("array_rotate", true, false) is CheckButton, "Radial Array exposes copy rotation")
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


func case_compact_toolbar_preserves_commands_and_profile_selection() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	for mode in [SlabSelection.Mode.VERTEX, SlabSelection.Mode.EDGE, SlabSelection.Mode.FACE]:
		selection.mode = mode
		var primary: HFlowContainer = panel.find_child("PrimaryCommands", true, false)
		expect(primary != null, "component mode exposes one wrapping command toolbar")
		for section in actions.command_sections_for(mode):
			if section["heading"] == SlabActions.SECTION_SELECTION:
				continue
			for row in section["rows"]:
				var button: Button = primary.get_node_or_null(str(row["id"]))
				expect(button != null, "%s remains discoverable in the primary toolbar" % row["id"])
				if button != null:
					expect(button.disabled == not actions.disabled_reason(row).is_empty(),
						"toolbar preserves %s availability" % row["id"])
		var disclosure: Button = panel.find_child("SectionSelection", true, false)
		expect(not disclosure.button_pressed, "Selection remains collapsed on first use")
	var bevel: Button = panel.find_child("bevel_edges", true, false)
	var extrude: Button = panel.find_child("extrude_faces", true, false)
	expect(bevel.get_parent() == extrude.get_parent(), "Face Bevel sits beside the other Face actions")
	expect(not panel.find_child("SettingsColumn", true, false).visible,
		"Face mode releases the empty settings column")
	var status: Label = panel.get_node("Status")
	expect(status.visible and status.text.contains("Select a solid") and not status.text.contains("No solid selected"),
		"empty state gives one instruction rather than repeating header identity")
	var menu: MenuButton = panel.find_child("ShortcutsMenu", true, false)
	expect(menu != null and menu.text == "Shortcuts" and menu.focus_mode == Control.FOCUS_ALL
		and not menu.accessibility_name.is_empty(), "shortcut profiles have a compact keyboard-accessible menu")
	var popup := menu.get_popup()
	popup.id_pressed.emit(2)
	expect(actions.keybind_profiles.profile() == 2, "menu selection updates the active keyboard profile")
	for index in popup.item_count:
		expect(popup.is_item_checked(index) == (index == 2), "only the chosen keyboard profile is checked")
	actions.keybind_profiles.set_profile(0)
	expect(popup.is_item_checked(0) and not popup.is_item_checked(2), "external profile changes refresh menu checks")
	selection.mode = SlabSelection.Mode.OBJECT
	expect(panel.find_child("SettingsColumn", true, false).visible, "Object mode restores creation settings")
	panel.free()


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
	expect(_spins(panel.find_child("Settings", true, false)).is_empty(), "Face mode leaves UV fields to UV workspace")
	expect(is_equal_approx(panel.custom_minimum_size.y, SlabPanel.PANEL_HEIGHT),
		"the dock stays compact, got %s" % panel.custom_minimum_size.y)
	expect(_label_for(panel, "Face") == null and _label_for(panel, "Edge") == null
		and panel.find_child("SectionSelection", true, false) != null,
		"Face actions share one toolbar and retain the Selection disclosure")
	expect(panel.find_child("SectionUV", true, false) == null and panel.find_child("MaterialChips", true, false) == null,
		"Face mode does not duplicate UV workspace material and UV controls")
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
	root.add_child(panel)
	var uv_toggle: Button = panel.find_child("UVWorkspace", true, false)
	expect(uv_toggle != null and uv_toggle.text == "UV", "the dock has UV workspace button")
	var paint_toggle: Button = panel.find_child("PaintWorkspace", true, false)
	expect(paint_toggle != null and paint_toggle.text == "Paint", "the dock has Paint workspace button")
	expect(panel.find_child("PaintCanvas", true, false) != null, "the dock has a texture canvas")
	expect(panel.find_child("PaintBody", true, false) != null, "the dock has a paint workspace")
	expect(not panel.find_child("PaintBody", true, false).visible, "paint starts closed")
	paint.enter()
	await process_frame
	await process_frame
	expect(panel.find_child("PaintBody", true, false).visible, "UV workspace shows the workspace")
	expect(not panel.find_child("ModelBody", true, false).visible, "modeling commands hide while painting")
	expect(panel.custom_minimum_size.y > SlabPanel.PANEL_HEIGHT, "the paint dock is taller than the model strip")
	expect(uv_toggle != null and paint_toggle != null,
		"header has distinct UV and Paint workspace buttons")
	expect(_button_for(panel, "Make Unique") != null, "Make Unique is labeled")
	var uv_controls: Control = panel.find_child("PaintUvControls", true, false)
	expect(uv_controls != null and uv_controls.visible, "Material/UV shows precise placement controls")
	expect(uv_controls.custom_minimum_size.y >= SlabPanel.PAINT_UV_ROW_HEIGHT,
		"precise placement reserves room for fields above its scrollbar")
	for key in ["paint_uv_repeat_u", "paint_uv_repeat_v", "paint_uv_offset_u", "paint_uv_offset_v", "paint_uv_rotation"]:
		var field: Node = panel.find_child(key, true, false)
		expect(field != null and _spins(field).size() == 1, "%s has one numeric field" % key)
		if field != null and not _spins(field).is_empty():
			expect(_spins(field)[0].focus_mode == Control.FOCUS_ALL, "%s is keyboard focusable" % key)
	expect(_button_for(panel, "Apply UV") != null and _button_for(panel, "Reset UV") != null,
		"precise placement has clear Apply UV and Reset UV actions")
	expect(panel.find_child("BrushColor", true, false) != null, "brush color sits next to the canvas")
	expect(panel.custom_minimum_size.y >= preload("res://addons/slab/slab_paint.gd").PAINT_HEIGHT
		and is_equal_approx(panel.custom_minimum_size.y, panel.get_combined_minimum_size().y),
		"the paint dock minimum matches its bounded workspace")
	expect(panel.find_child("PaintPalette", true, false) is ScrollContainer,
		"the material palette scrolls in one strip")
	expect(panel.find_child("PaintPalette", true, false).custom_minimum_size.y <= 40.5,
		"the named palette is a 40px strip")
	var canvas: Control = panel.find_child("PaintCanvas", true, false)
	expect(canvas.custom_minimum_size.y >= SlabPanel.PAINT_CANVAS_MIN_HEIGHT
		and panel.get_combined_minimum_size().y >= canvas.custom_minimum_size.y,
		"the paint dock derives enough height for a usable canvas, got canvas=%s dock=%s" % [
			canvas.custom_minimum_size.y, panel.get_combined_minimum_size().y])
	var material_minimum := panel.get_combined_minimum_size().y
	expect(panel.find_child("PaintUvHint", true, false) != null
		and String(panel.find_child("PaintUvHint", true, false).text).contains("rotates"),
		"UV modifiers have a compact hint")
	expect(panel.find_child("PaintMaterialPickerWrap", true, false) != null,
		"the material picker has a dedicated action-row slot")
	expect(panel.find_child("PaintActions", true, false) != null
		and panel.find_child("PaintActions", true, false).get_combined_minimum_size().y > SlabPanel.PAINT_PICKER_HEIGHT,
		"paint actions naturally reserve the buttons and native resource picker")
	expect(_source_of("slab_solid_gizmo.gd").contains("_paint_hides_albedo"),
		"UV workspace drops the opaque face fill")
	expect(_source_of("slab_solid_gizmo.gd").contains("PAINT_EDGE"),
		"UV workspace keeps an on-top face outline")
	var unique_off: Button = _button_for(panel, "Make Unique")
	expect(unique_off != null and unique_off.disabled, "Make Unique stays off until a face is selected")
	expect(panel.current_workspace() == panel.Workspace.UV, "workspace is UV after paint.enter")
	paint.tool = preload("res://addons/slab/slab_paint.gd").Tool.PIXEL
	panel.call("_on_paint_changed")
	await process_frame
	await process_frame
	expect(panel.current_workspace() == panel.Workspace.PAINT or paint.tool == preload("res://addons/slab/slab_paint.gd").Tool.PIXEL,
		"Paint workspace uses pixel tool")
	expect(not uv_controls.visible, "Paint workspace hides UV placement fields and keeps the canvas workspace")
	expect(is_equal_approx(panel.get_combined_minimum_size().y, material_minimum),
		"UV and Paint workspaces keep one paint workspace minimum, got %s after %s" % [panel.get_combined_minimum_size().y, material_minimum])
	paint.tool = preload("res://addons/slab/slab_paint.gd").Tool.MATERIAL_UV
	panel.call("_on_paint_changed")
	await process_frame
	expect(is_equal_approx(panel.get_combined_minimum_size().y, material_minimum),
		"returning to UV workspace keeps the paint workspace minimum")
	paint.exit()
	await process_frame
	expect(panel.find_child("ModelBody", true, false).visible, "closing paint restores modeling")
	expect(is_equal_approx(panel.get_combined_minimum_size().y, SlabPanel.PANEL_HEIGHT),
		"closing paint restores the modelling minimum")
	panel.free()
	var scaled_selection := SlabSelection.new()
	var scaled_actions := SlabActions.new(scaled_selection)
	var scaled_paint := preload("res://addons/slab/slab_paint.gd").new()
	scaled_paint.bind(scaled_selection, scaled_actions, SlabTestUndo.new())
	var scaled_panel := SlabPanel.new()
	scaled_panel.setup(scaled_selection, scaled_actions, SlabMetrics.at_scale(1.5))
	scaled_panel.bind_paint(scaled_paint)
	root.add_child(scaled_panel)
	scaled_paint.tool = preload("res://addons/slab/slab_paint.gd").Tool.PIXEL
	scaled_paint.enter()
	await process_frame
	await process_frame
	var scaled_canvas: Control = scaled_panel.find_child("PaintCanvas", true, false)
	var scaled_pixel_minimum := scaled_panel.get_combined_minimum_size().y
	expect(is_equal_approx(scaled_canvas.custom_minimum_size.y, SlabPanel.PAINT_CANVAS_MIN_HEIGHT * 1.5)
		and scaled_panel.get_combined_minimum_size().y >= scaled_canvas.custom_minimum_size.y,
		"paint canvas and derived dock minimum follow 1.5x editor scale")
	scaled_paint.tool = preload("res://addons/slab/slab_paint.gd").Tool.MATERIAL_UV
	scaled_panel.call("_on_paint_changed")
	await process_frame
	await process_frame
	expect(is_equal_approx(scaled_panel.get_combined_minimum_size().y, scaled_pixel_minimum),
		"Paint-first entry reserves the UV workspace minimum at 1.5x scale, got %s after %s" % [scaled_panel.get_combined_minimum_size().y, scaled_pixel_minimum])
	scaled_panel.free()


func case_paint_left_dock_stays_beside_the_canvas() -> void:
	root.size = Vector2i(1280, 800)
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var paint: RefCounted = preload("res://addons/slab/slab_paint.gd").new()
	paint.bind(selection, actions, SlabTestUndo.new())
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	panel.bind_paint(paint)
	root.add_child(panel)
	panel.theme = ThemeDB.get_default_theme()
	panel.size = Vector2(1226, preload("res://addons/slab/slab_paint.gd").PAINT_HEIGHT)
	paint.tool = preload("res://addons/slab/slab_paint.gd").Tool.PIXEL
	paint.enter()
	await process_frame
	await process_frame
	_expect_paint_dock_clear_of_canvas(panel, "Paint")
	var flatten: Button = panel.find_child("PaintFlatten", true, false)
	var color: ColorPickerButton = panel.find_child("BrushColor", true, false)
	expect(flatten != null and flatten.is_visible_in_tree(), "Paint exposes Flatten")
	expect(color != null and color.is_visible_in_tree(), "Paint exposes brush Color")
	if flatten != null:
		flatten.custom_minimum_size.x = 240.0
	if color != null:
		color.custom_minimum_size.x = 240.0
	panel.call("_refresh_paint_chrome")
	await process_frame
	await process_frame
	var inspector: Control = panel.find_child("PaintInspector", true, false)
	expect(inspector.size.x + 0.5 >= 240.0,
		"the paint dock grows with Flatten and Color instead of clipping them, got %s" % inspector.size.x)
	_expect_paint_dock_clear_of_canvas(panel, "wide Paint fields")
	paint.tool = preload("res://addons/slab/slab_paint.gd").Tool.MATERIAL_UV
	panel.call("_on_paint_changed")
	await process_frame
	await process_frame
	expect(is_equal_approx(inspector.custom_minimum_size.x, SlabPanel.UV_DOCK_MIN_WIDTH),
		"UV keeps the Mapping dock width, got %s" % inspector.custom_minimum_size.x)
	expect(panel.find_child("PaintMapping", true, false).visible
		and panel.find_child("PaintUnwrap", true, false).visible
		and panel.find_child("PaintPack", true, false).visible
		and panel.find_child("PaintFitUv", true, false).visible,
		"UV still exposes Mapping, Unwrap, Pack, and Fit UV")
	expect(not _rects_overlap(inspector.get_global_rect(), panel.find_child("PaintCanvas", true, false).get_global_rect()),
		"UV dock stays beside the canvas")
	paint.tool = preload("res://addons/slab/slab_paint.gd").Tool.PIXEL
	panel.call("_on_paint_changed")
	await process_frame
	await process_frame
	_expect_paint_dock_clear_of_canvas(panel, "Paint after UV")
	paint.exit()
	await process_frame
	expect(panel.find_child("ModelBody", true, false).visible, "leaving Paint restores the modelling dock")
	expect(is_equal_approx(panel.get_combined_minimum_size().y, SlabPanel.PANEL_HEIGHT),
		"leaving Paint restores the modelling height")
	expect(panel.find_child("SoftSelect", true, false) != null, "Soft Select is still on the modelling dock")
	expect(panel.find_child("OperationHandles", true, false) != null, "Op Card host stays on the modelling dock")
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
	var chips: HFlowContainer = panel.find_child("CreateChips", true, false) as HFlowContainer
	expect(chips != null, "Object mode has CreateChips flow")
	var labels: PackedStringArray = PackedStringArray()
	for child in chips.get_children():
		if child is Button:
			labels.append(String(child.get_meta("slab_label", "")))
	expect(labels.has("Stair"), "CreateChips lists Stair, got %s" % [labels])
	expect(labels.find("Stair") == 2, "Stair stays the third shape chip after Box and Plane, got %s" % [labels])
	var stair: Button = _button_for(panel, "Stair")
	expect(stair.icon != null, "Stair has a glyph")
	panel.focus_create(&"make_stair")
	expect(panel.find_child("stair_steps", true, false) != null, "focusing Stair shows Steps")
	expect(panel.find_child("arch_arc", true, false) == null, "Stair focus hides Arch's Arc")
	panel.free()


func case_create_icons_sit_above_the_settings() -> void:
	var panel := _build_panel(1.0)
	var create_strip: Node = panel.find_child("CreateStrip", true, false)
	var settings: Node = panel.find_child("Settings", true, false)
	expect(create_strip != null and settings != null, "the dock has CreateStrip and Settings")
	expect(create_strip.get_parent() == settings.get_parent(),
		"CreateStrip and Settings share the SettingsColumn")
	expect(create_strip.get_index() < settings.get_index(),
		"CreateStrip sits above the Settings block")
	var stair: Button = _button_for(panel, "Stair")
	var create_chips: Node = panel.find_child("CreateChips", true, false)
	expect(stair.get_parent() == create_chips,
		"Stair lives in CreateChips inside CreateStrip")
	panel.free()


func case_command_labels_fit_and_wrap() -> void:
	var panel := _build_panel(1.0)
	var chips: HFlowContainer = panel.find_child("CreateChips", true, false) as HFlowContainer
	expect(chips != null, "Object mode lays shape chips in CreateChips flow")
	var flow: HFlowContainer = _first_command_row(panel)
	expect(flow != null, "Object mode lays commands in a wrapping flow")
	for label in ["Box", "Cylinder"]:
		var button: Button = _button_for(panel, label)
		expect(button != null, "%s is on the Object dock" % label)
		expect(button.get_parent() == chips, "%s is in CreateChips" % label)
		expect(not button.clip_text, "%s does not clip its caption" % label)
		_expect_label_fits(button, label)
	for label in ["Mirror X", "Mirror Y", "Mirror Z", "Center Pivot", "Snap To Grid"]:
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
	for label in ["Extrude", "Inset", "Select Coplanar", "Select Boundary"]:
		var button: Button = _button_for(face, label)
		expect(button != null, "%s is on the Face dock" % label)
		expect(not button.clip_text, "%s does not clip its caption" % label)
		_expect_label_fits(button, label)
	face.free()
	var edge := _build_panel(1.0, SlabSelection.Mode.EDGE)
	var loop: Button = _button_for(edge, "Loop Cut")
	expect(loop != null and not loop.clip_text, "Loop Cut does not clip its caption")
	_expect_label_fits(loop, "Loop Cut")
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
		if button.has_meta("slab_mode") or button.has_meta("slab_label") or button.name == "UVWorkspace" or button.name == "PaintWorkspace":
			expected.append(button)
	for button in expected:
		expect(button.focus_mode == Control.FOCUS_ALL, "%s is reachable by keyboard focus" % button.name)
		expect(button.accessibility_name != "", "%s has an accessible name" % button.name)

	var box: Button = panel.find_child("make_box", true, false)
	var uv_button: Button = panel.find_child("UVWorkspace", true, false)
	expect(box != null and box.accessibility_name == "Box", "Create Box has its visible accessible name")
	expect(uv_button != null and uv_button.accessibility_name == "UV workspace", "UV workspace has its visible accessible name")
	if box != null:
		box.grab_focus()
		expect(root.get_viewport().gui_get_focus_owner() == box, "Create Box accepts keyboard focus")
	if uv_button != null:
		uv_button.grab_focus()
		expect(root.get_viewport().gui_get_focus_owner() == uv_button, "UV workspace accepts keyboard focus")
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


func case_preview_controls_follow_the_modelling_context() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	var previews: Control = panel.find_child("OperationHandles", true, false)
	var settings: Control = panel.find_child("Settings", true, false)
	expect(not previews.visible, "Object mode has no element previews")
	selection.mode = SlabSelection.Mode.VERTEX
	expect(not previews.visible and not settings.visible, "Vertex mode has no unused amount or preview controls")
	selection.mode = SlabSelection.Mode.FACE
	expect(not previews.visible and not settings.visible, "Face mode hides settings until a face is selected")
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	root.add_child(solid)
	expect(solid.call("make_box", Vector3(2, 2, 2)) == 0, "context box builds")
	selection.set_objects([solid])
	selection.set_ids(PackedInt64Array([solid.call("get_faces")[0]]))
	expect(not previews.visible and not settings.visible, "face selection keeps secondary settings collapsed")
	expect(not previews.visible and not settings.visible, "face selection keeps UV settings in UV workspace")
	selection.operation_preview = {"kind": 1}
	actions.operation_active = true
	actions.operation_state_changed.emit()
	expect(not settings.visible and panel.find_child("HandleAmount", true, false).visible,
		"an active preview exposes one amount field")
	actions.operation_active = false
	actions.operation_state_changed.emit()
	expect(not settings.visible, "leaving preview keeps duplicate Face settings hidden")
	panel.free()
	solid.free()


func case_settings_follow_available_dock_width() -> void:
	root.size = Vector2i(1400, 800)
	var panel := _build_panel(1.0)
	root.add_child(panel)
	panel.size = Vector2(1200, 360)
	for i in 3: await process_frame
	var body: BoxContainer = panel.find_child("ModelBody", true, false)
	var commands: Control = panel.find_child("Commands", true, false).get_parent()
	var settings_column: Control = panel.find_child("SettingsColumn", true, false)
	expect(not body.vertical and settings_column.position.x >= commands.size.x,
		"wide docks place settings column beside commands")
	panel.size.x = 760
	for i in 3: await process_frame
	expect(body.vertical and settings_column.position.y >= commands.position.y + commands.size.y,
		"narrow docks stack settings column below commands")
	panel.free()


func case_object_settings_are_for_the_next_shape() -> void:
	var panel := _build_panel(1.0)
	var create_strip: Control = panel.find_child("CreateStrip", true, false)
	expect(create_strip != null and create_strip.visible, "Object mode shows CreateStrip above SettingsScroll")
	var create_fields: Control = panel.find_child("CreateFields", true, false)
	expect(create_fields != null and create_fields.get_child_count() > 0, "CreateStrip has dimension fields for default shape")
	var cylinder: Button = panel.find_child("make_cylinder", true, false)
	cylinder.mouse_entered.emit()
	var field_count_before: int = create_fields.get_child_count()
	expect(create_fields.get_child_count() == field_count_before, "hovering a shape does not replace creation fields")
	cylinder.pressed.emit()
	expect(panel.find_child("cylinder_sides", true, false) != null, "Cylinder focus shows Cylinder-specific fields")
	expect(panel.find_child("CreateShape", true, false) != null, "shape settings have an explicit Create action")
	panel.free()


func case_mouse_shape_choice_updates_before_notifying_consumers() -> void:
	root.size = Vector2i(1280, 800)
	var panel := _build_panel(1.0)
	root.add_child(panel)
	panel.size = Vector2(1226.0, 320.0)
	panel.resized.emit()
	await process_frame
	await process_frame
	var stair: Button = panel.find_child("make_stair", true, false)
	var observed := {"has_stair_fields": false, "pressed": false}
	panel.get("_actions").create_settings_changed.connect(func() -> void:
		observed.has_stair_fields = panel.find_child("stair_steps", true, false) != null
		observed.pressed = stair.button_pressed
	)
	_mouse_click(stair)
	expect(observed.has_stair_fields and observed.pressed,
		"mouse Stair choice updates pressed state and settings before notifying consumers")
	expect(panel.find_child("stair_steps", true, false) != null,
		"mouse Stair choice displays Stair fields")
	panel.free()


func case_boolean_operands_are_named_and_swappable() -> void:
	var selection := SlabSelection.new()
	var target: Node3D = ClassDB.instantiate("SlabSolid")
	target.name = "PowerHouse"
	var cutter: Node3D = ClassDB.instantiate("SlabSolid")
	cutter.name = "PowerHouseDoorCutter"
	root.add_child(target)
	root.add_child(cutter)
	selection.set_objects([target, cutter])
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	root.add_child(panel)
	panel.size = Vector2(300, 320)
	await process_frame
	await process_frame
	var context: Label = panel.find_child("SelectionContext", true, false)
	expect(context != null and context.text == "2 solids selected", "the header keeps compact multi-solid context")
	expect(context.custom_minimum_size.x == 0.0 and context.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
		"selection context yields width and ellipsizes in narrow docks")
	var operands: Control = panel.find_child("BooleanOperands", true, false)
	expect(operands != null, "two selected solids expose Boolean operands")
	var labels: Array[Node] = operands.find_children("*", "Label", true, false)
	expect(panel.find_child("SettingsTitle", true, false).text == "Boolean operands", "Boolean roles have their own settings heading")
	expect(labels.size() == 2 and labels[0].text == "Target: PowerHouse"
		and labels[1].text == "Second solid: PowerHouseDoorCutter", "Boolean operand roles show exact node names")
	expect(operands.size.x >= 240.0 and labels[1].autowrap_mode != TextServer.AUTOWRAP_OFF,
		"long Boolean names get a full-width wrapping block")
	var swap: Button = panel.find_child("SwapBooleanOperands", true, false)
	expect(swap != null and not swap.clip_text, "Swap operands fits the compact settings column")
	swap.pressed.emit()
	expect(selection.objects == [cutter, target], "Swap reverses the Boolean operand order")
	cutter.name = "RenamedDoorCutter"
	operands = panel.find_child("BooleanOperands", true, false)
	labels = operands.find_children("*", "Label", true, false)
	expect(labels[0].text == "Target: RenamedDoorCutter", "renaming a selected operand updates its role without reselection")
	selection.set_objects([target])
	target.name = "PowerHouseRoofFaceWithAnIntentionallyLongAuthoringName"
	await process_frame
	expect(context.text == target.name and context.tooltip_text == target.name
		and context.get_combined_minimum_size().x <= 1.0,
		"long selection names stay complete in the tooltip without adding a text-width minimum")
	target.name = "RenamedRoom"
	expect(not panel.get_node("Status").visible, "renaming a selected solid does not repeat its identity in status")
	expect(context.text == "RenamedRoom" and context.tooltip_text == "RenamedRoom",
		"renaming the selected solid updates permanent header context")
	actions.reported.emit("Current report")
	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([1, 2]))
	expect(context.text == "2 faces · RenamedRoom" and not panel.get_node("Status").visible,
		"element selection updates header context and clears superseded feedback")
	actions.reported.emit("Current report")
	cutter.name = "UnselectedCutter"
	expect(panel.get_node("Status").text == "Current report" and context.text == "2 faces · RenamedRoom",
		"feedback does not obscure selection context and unselected renames do not erase it")
	selection.set_objects([])
	expect(context.text == "No solid selected", "clearing selection updates permanent header context")
	panel.free()
	target.free()
	cutter.free()


func case_face_distance_accepts_a_negative_extrude() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel := SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	selection.mode = SlabSelection.Mode.FACE
	var value := {"amount": 0.0}
	actions.operation_amount_changed.connect(func(v: float) -> void: value.amount = v)
	var amount: SpinBox = panel.find_child("HandleAmount", true, false)
	expect(amount.min_value < 0.0, "Face distance allows inward values, min %s" % amount.min_value)
	amount.value = -1.0
	amount.value_changed.emit(amount.value)
	expect(is_equal_approx(value.amount, -1.0), "typing -1 keeps -1, got %s" % value.amount)
	expect(is_equal_approx(amount.value, -1.0), "the spin does not clamp -1 up to 0.05")
	panel.free()


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


func case_mouse_click_extrude_and_refused_merge_run() -> void:
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
	var session := preload("res://addons/slab/slab_viewport.gd").new(preload("res://tests/slab_test_host.gd").over(root))
	var selection: RefCounted = session.state()
	var actions := SlabActions.new(selection)
	session.bind_actions(actions)
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
	actions.extrude_amount = -1.0
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
	expect(actions.operation_active and int(solid.call("face_count")) == before, "mouse Extrude starts a preview without changing geometry")
	await process_frame
	await process_frame
	_mouse_click(_button_for(panel, "Apply"))
	expect(hits["n"] == 1, "a viewport mouse click fires Extrude.pressed, got %d size=%s rect=%s" % [
		hits["n"], extrude.size, extrude.get_global_rect()
	])
	expect(said.is_empty() or not said[0].contains("failed"),
		"mouse Extrude commits, got %s" % [said])
	expect(int(solid.call("face_count")) > before, "mouse Extrude still extrudes, faces %d after %d" % [
		solid.call("face_count"), before
	])
	var other := 0
	for face_id in solid.call("get_faces"):
		if absf(solid.call("face_normal", face_id).y) < 0.1:
			other = face_id
			break
	selection.set_ids(PackedInt64Array([top, other]))
	await process_frame
	await process_frame
	var merge: Button = _button_for(panel, "Merge")
	expect(merge != null and not merge.disabled, "Merge is enabled for two selected faces")
	said.clear()
	var merge_hits := {"n": 0}
	merge.pressed.connect(func() -> void: merge_hits["n"] += 1)
	var before_refusal: PackedByteArray = solid.get("data")
	_mouse_click(merge)
	expect(merge_hits["n"] == 1, "a viewport mouse click fires Merge.pressed")
	expect(solid.get("data") == before_refusal and not said.is_empty() and said[0].contains("flat surface"),
		"refused Merge preserves geometry and explains the selection constraint, got %s" % [said])
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
	SlabTestGui.mouse_click(control)


func _hover(control: Control) -> void:
	SlabTestGui.hover(control)


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


func _rects_overlap(a: Rect2, b: Rect2) -> bool:
	return a.grow(-1.0).intersects(b.grow(-1.0))


func _expect_paint_dock_clear_of_canvas(panel: Control, label: String) -> void:
	var inspector: Control = panel.find_child("PaintInspector", true, false)
	var canvas: Control = panel.find_child("PaintCanvas", true, false)
	expect(inspector != null and canvas != null, "%s has a paint dock and canvas" % label)
	if inspector == null or canvas == null:
		return
	expect(canvas.get_global_rect().position.x + 0.5 >= inspector.get_global_rect().end.x,
		"%s canvas starts after the dock, dock=%s canvas=%s" % [label, inspector.get_global_rect(), canvas.get_global_rect()])
	expect(not _rects_overlap(inspector.get_global_rect(), canvas.get_global_rect()),
		"%s dock does not sit under the canvas, dock=%s canvas=%s" % [label, inspector.get_global_rect(), canvas.get_global_rect()])
	for child_name in ["PaintFlatten", "BrushColor", "brush_radius", "brush_opacity"]:
		var control: Control = panel.find_child(child_name, true, false) as Control
		expect(control != null and control.is_visible_in_tree(), "%s shows %s" % [label, child_name])
		if control == null:
			continue
		var field := control.get_global_rect()
		var dock := inspector.get_global_rect()
		expect(control.size.x + 0.5 >= control.get_combined_minimum_size().x,
			"%s %s is not clipped, size=%s min=%s" % [label, child_name, control.size, control.get_combined_minimum_size()])
		expect(field.position.x + 0.5 >= dock.position.x and field.end.x <= dock.end.x + 1.0,
			"%s %s stays in the dock column, control=%s dock=%s" % [label, child_name, field, dock])
		expect(not _rects_overlap(field, canvas.get_global_rect()),
			"%s %s is not under the canvas, control=%s canvas=%s" % [label, child_name, field, canvas.get_global_rect()])
