@tool
extends RefCounted

## Keybind profiles for Slab modelling shortcuts.
## Profiles remap command chords only; mode keys (1-4) and modal Esc/Enter remain fixed.

signal profile_changed(profile: int)

enum Profile {
	SLAB = 0,
	FAMILIAR_UMX = 1,
	FAMILIAR_BLENDER = 2,
}

const PROFILE_LABELS: Dictionary = {
	Profile.SLAB: "Slab (default)",
	Profile.FAMILIAR_UMX: "Familiar (UMX-ish)",
	Profile.FAMILIAR_BLENDER: "Familiar (Blender-ish)",
}

const SETTINGS_KEY := "slab/keyboard_profile"

const GODOT_SYSTEM_CHORDS: Array[Dictionary] = [
	{ "chord": "Ctrl+S", "keycode": KEY_S, "ctrl": true, "action": "Save" },
	{ "chord": "Ctrl+Z", "keycode": KEY_Z, "ctrl": true, "action": "Undo" },
	{ "chord": "Ctrl+Shift+Z", "keycode": KEY_Z, "ctrl": true, "shift": true, "action": "Redo" },
	{ "chord": "Ctrl+Y", "keycode": KEY_Y, "ctrl": true, "action": "Redo" },
	{ "chord": "Ctrl+C", "keycode": KEY_C, "ctrl": true, "action": "Copy" },
	{ "chord": "Ctrl+V", "keycode": KEY_V, "ctrl": true, "action": "Paste" },
	{ "chord": "Ctrl+X", "keycode": KEY_X, "ctrl": true, "action": "Cut" },
]

const SLAB_SHORTCUTS: Dictionary = {
	"extrude_faces": KEY_E,
	"inset_faces": KEY_I,
	"bevel_edges": KEY_B,
	"insert_loop": KEY_L,
	"dissolve_edges": KEY_X,
	"subdivide_faces": KEY_U,
	"merge_faces": KEY_M,
	"select_all": KEY_A,
	"select_none": KEY_D,
	"weld_vertices": KEY_J,
	"collapse_vertices": KEY_Y,
	"connect_vertices": KEY_K,
	"connect_edges": KEY_K,
}

const UMX_SHORTCUTS: Dictionary = {
	"extrude_faces": KEY_E,
	"inset_faces": KEY_I,
	"bevel_edges": KEY_B,
	"insert_loop": KEY_L,
	"dissolve_edges": KEY_BACKSPACE,
	"subdivide_faces": KEY_S,
	"merge_faces": KEY_M,
	"select_all": KEY_A,
	"select_none": KEY_D,
	"weld_vertices": KEY_W,
	"collapse_vertices": KEY_C,
	"connect_vertices": KEY_J,
	"connect_edges": KEY_J,
}

const BLENDER_SHORTCUTS: Dictionary = {
	"extrude_faces": KEY_E,
	"inset_faces": KEY_I,
	"bevel_edges": KEY_B,
	"insert_loop": KEY_R,
	"dissolve_edges": KEY_X,
	"subdivide_faces": KEY_W,
	"merge_faces": KEY_M,
	"select_all": KEY_A,
	"select_none": KEY_D,
	"weld_vertices": KEY_J,
	"collapse_vertices": KEY_Y,
	"connect_vertices": KEY_K,
	"connect_edges": KEY_K,
}

const PROFILE_SHORTCUTS: Dictionary = {
	Profile.SLAB: SLAB_SHORTCUTS,
	Profile.FAMILIAR_UMX: UMX_SHORTCUTS,
	Profile.FAMILIAR_BLENDER: BLENDER_SHORTCUTS,
}

var _profile: int = Profile.SLAB
var _settings: Object = null


static func label_of(profile: int) -> String:
	return PROFILE_LABELS.get(profile, "Unknown")


func bind_editor_settings(settings: Object) -> void:
	_settings = settings
	_load()


func profile() -> int:
	return _profile


func set_profile(profile: int) -> void:
	if _profile == profile:
		return
	_profile = profile
	_save()
	profile_changed.emit(_profile)


func shortcut_for(command_id: String) -> int:
	var shortcuts: Dictionary = PROFILE_SHORTCUTS.get(_profile, SLAB_SHORTCUTS)
	return shortcuts.get(command_id, SLAB_SHORTCUTS.get(command_id, 0))


func command_for_shortcut(keycode: int) -> String:
	var shortcuts: Dictionary = PROFILE_SHORTCUTS.get(_profile, SLAB_SHORTCUTS)
	for command_id in shortcuts:
		if shortcuts[command_id] == keycode:
			return command_id
	return ""


func conflicts_with_godot() -> Array[String]:
	var shortcuts: Dictionary = PROFILE_SHORTCUTS.get(_profile, SLAB_SHORTCUTS)
	var conflicts: Array[String] = []
	for chord_info in GODOT_SYSTEM_CHORDS:
		var keycode: int = chord_info["keycode"]
		for command_id in shortcuts:
			if shortcuts[command_id] == keycode:
				var ctrl: bool = chord_info.get("ctrl", false)
				var shift: bool = chord_info.get("shift", false)
				if not ctrl and not shift:
					conflicts.append("%s (%s) conflicts with Godot %s" % [
						OS.get_keycode_string(keycode),
						command_id,
						chord_info["action"]
					])
	return conflicts


func all_profile_labels() -> Array[String]:
	var labels: Array[String] = []
	for p in Profile.values():
		labels.append(PROFILE_LABELS[p])
	return labels


func _load() -> void:
	if _settings == null:
		return
	if _settings.has_setting(SETTINGS_KEY):
		_profile = clampi(int(_settings.get_setting(SETTINGS_KEY)), 0, Profile.size() - 1)


func _save() -> void:
	if _settings == null:
		return
	_settings.set_setting(SETTINGS_KEY, _profile)
