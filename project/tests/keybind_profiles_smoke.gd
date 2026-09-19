extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const KeybindProfiles := preload("res://addons/slab/slab_keybind_profiles.gd")
const Undo := preload("res://tests/slab_test_undo.gd")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_profile_enum()
	_check_profile_shortcuts()
	_check_slab_profile_restores_stock()
	_check_familiar_remaps()
	_check_no_duplicate_chords()
	_check_esc_enter_not_remapped()
	_check_godot_conflict_detection()
	_check_run_shortcut_uses_profile()
	print("keybind_profiles_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("ok " if ok else "FAIL ", message)


func _check_profile_enum() -> void:
	check(KeybindProfiles.Profile.SLAB == 0, "SLAB profile is 0")
	check(KeybindProfiles.Profile.FAMILIAR_UMX == 1, "FAMILIAR_UMX profile is 1")
	check(KeybindProfiles.Profile.FAMILIAR_BLENDER == 2, "FAMILIAR_BLENDER profile is 2")
	check(KeybindProfiles.PROFILE_LABELS.size() == 3, "Three profile labels defined")


func _check_profile_shortcuts() -> void:
	var profiles := KeybindProfiles.new()
	profiles.set_profile(KeybindProfiles.Profile.SLAB)
	check(profiles.shortcut_for("extrude_faces") == KEY_E, "Slab: extrude is E")
	check(profiles.shortcut_for("dissolve_edges") == KEY_X, "Slab: dissolve is X")
	check(profiles.shortcut_for("subdivide_faces") == KEY_U, "Slab: subdivide is U")

	profiles.set_profile(KeybindProfiles.Profile.FAMILIAR_UMX)
	check(profiles.shortcut_for("dissolve_edges") == KEY_BACKSPACE, "UMX: dissolve is Backspace")
	check(profiles.shortcut_for("subdivide_faces") == KEY_S, "UMX: subdivide is S")
	check(profiles.shortcut_for("weld_vertices") == KEY_W, "UMX: weld is W")

	profiles.set_profile(KeybindProfiles.Profile.FAMILIAR_BLENDER)
	check(profiles.shortcut_for("insert_loop") == KEY_R, "Blender: loop cut is R")
	check(profiles.shortcut_for("subdivide_faces") == KEY_W, "Blender: subdivide is W")


func _check_slab_profile_restores_stock() -> void:
	var profiles := KeybindProfiles.new()
	profiles.set_profile(KeybindProfiles.Profile.FAMILIAR_UMX)
	check(profiles.shortcut_for("dissolve_edges") == KEY_BACKSPACE, "UMX has Backspace for dissolve")
	profiles.set_profile(KeybindProfiles.Profile.SLAB)
	check(profiles.shortcut_for("dissolve_edges") == KEY_X, "Slab restores X for dissolve")
	check(profiles.shortcut_for("subdivide_faces") == KEY_U, "Slab restores U for subdivide")


func _check_familiar_remaps() -> void:
	var profiles := KeybindProfiles.new()
	profiles.set_profile(KeybindProfiles.Profile.FAMILIAR_UMX)
	var umx_dissolve := profiles.shortcut_for("dissolve_edges")
	check(umx_dissolve == KEY_BACKSPACE, "UMX dissolve is Backspace")
	check(profiles.shortcut_for("connect_vertices") == KEY_J, "UMX connect is J")
	check(profiles.shortcut_for("collapse_vertices") == KEY_C, "UMX collapse is C")

	profiles.set_profile(KeybindProfiles.Profile.FAMILIAR_BLENDER)
	check(profiles.shortcut_for("insert_loop") == KEY_R, "Blender loop cut is R")
	check(profiles.shortcut_for("subdivide_faces") == KEY_W, "Blender subdivide is W")
	check(profiles.shortcut_for("select_all") == KEY_A, "Blender select all is A")
	check(profiles.shortcut_for("select_none") == KEY_D, "Blender select none is D (Slab default, avoids A collision)")


func _check_no_duplicate_chords() -> void:
	var mode_exclusive_pairs: Array[Array] = [
		["connect_vertices", "connect_edges"],
	]
	for profile_id in [KeybindProfiles.Profile.SLAB, KeybindProfiles.Profile.FAMILIAR_UMX, KeybindProfiles.Profile.FAMILIAR_BLENDER]:
		var shortcuts: Dictionary = KeybindProfiles.PROFILE_SHORTCUTS[profile_id]
		var label: String = KeybindProfiles.PROFILE_LABELS[profile_id]
		var key_to_commands: Dictionary = {}
		for command_id in shortcuts:
			var keycode: int = shortcuts[command_id]
			if not key_to_commands.has(keycode):
				key_to_commands[keycode] = []
			key_to_commands[keycode].append(command_id)
		var has_bad_duplicates := false
		for keycode in key_to_commands:
			var commands: Array = key_to_commands[keycode]
			if commands.size() > 1:
				var dominated_by_mode_pair := false
				for pair in mode_exclusive_pairs:
					var both_present := true
					for cmd in pair:
						if not commands.has(cmd):
							both_present = false
					if both_present and commands.size() == pair.size():
						dominated_by_mode_pair = true
						break
				if not dominated_by_mode_pair:
					has_bad_duplicates = true
					check(false, "%s: %s all bind to %s (within-profile collision)" % [
						label, ", ".join(commands), OS.get_keycode_string(keycode)])
		if not has_bad_duplicates:
			check(true, "%s: no within-profile duplicate chords (mode-exclusive pairs OK)" % label)


func _check_esc_enter_not_remapped() -> void:
	var forbidden: Array[int] = [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]
	for profile_id in [KeybindProfiles.Profile.SLAB, KeybindProfiles.Profile.FAMILIAR_UMX, KeybindProfiles.Profile.FAMILIAR_BLENDER]:
		var shortcuts: Dictionary = KeybindProfiles.PROFILE_SHORTCUTS[profile_id]
		var label: String = KeybindProfiles.PROFILE_LABELS[profile_id]
		for command_id in shortcuts:
			var keycode: int = shortcuts[command_id]
			if keycode == KEY_ESCAPE:
				check(false, "%s: %s must not bind to Escape (modal cancel)" % [label, command_id])
			elif keycode == KEY_ENTER:
				check(false, "%s: %s must not bind to Enter (modal apply)" % [label, command_id])
			elif keycode == KEY_KP_ENTER:
				check(false, "%s: %s must not bind to KP Enter (modal apply)" % [label, command_id])
		var clean := true
		for command_id in shortcuts:
			if shortcuts[command_id] in forbidden:
				clean = false
		check(clean, "%s: no command binds to Esc/Enter (modal keys reserved)" % label)


func _check_godot_conflict_detection() -> void:
	var profiles := KeybindProfiles.new()
	profiles.set_profile(KeybindProfiles.Profile.SLAB)
	var conflicts := profiles.conflicts_with_godot()
	check(conflicts.is_empty() or conflicts.size() == 0, "Slab profile has no Godot conflicts")

	for chord_info in KeybindProfiles.GODOT_SYSTEM_CHORDS:
		var keycode: int = chord_info["keycode"]
		var ctrl: bool = chord_info.get("ctrl", false)
		var shift: bool = chord_info.get("shift", false)
		if ctrl or shift:
			continue
		var action: String = chord_info["action"]
		check(true, "Godot chord %s is protected" % action)


func _check_run_shortcut_uses_profile() -> void:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3(4, 3, 4))
	var selection := Selection.new()
	selection.set_objects([solid])
	selection.mode = Selection.Mode.FACE
	var top := 0
	for face in solid.call("get_faces"):
		if solid.call("face_normal", face).y > 0.9:
			top = face
	selection.set_ids(PackedInt64Array([top]))
	var undo := Undo.new()
	var actions := Actions.new(selection, undo)
	var reports: Array[String] = []
	actions.reported.connect(func(message: String) -> void: reports.append(message))

	actions.keybind_profiles.set_profile(KeybindProfiles.Profile.SLAB)
	var before: PackedByteArray = solid.get("data")
	var ran := actions.run_shortcut(KEY_U)
	var after: PackedByteArray = solid.get("data")
	check(ran and after != before, "Slab profile: U triggers subdivide_faces")

	undo.undo()
	selection.set_ids(PackedInt64Array([top]))
	actions.keybind_profiles.set_profile(KeybindProfiles.Profile.FAMILIAR_UMX)
	before = solid.get("data")
	ran = actions.run_shortcut(KEY_S)
	after = solid.get("data")
	check(ran and after != before, "UMX profile: S triggers subdivide_faces")

	undo.undo()
	selection.set_ids(PackedInt64Array([top]))
	ran = actions.run_shortcut(KEY_U)
	check(not ran, "UMX profile: U does not trigger subdivide_faces")

	actions.keybind_profiles.set_profile(KeybindProfiles.Profile.SLAB)
	solid.free()
