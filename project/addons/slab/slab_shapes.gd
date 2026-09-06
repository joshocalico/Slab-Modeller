@tool
extends RefCounted

const ARC_MIN_DEG := 15.0
const ARC_MAX_DEG := 360.0 - ARC_MIN_DEG

const PARAMS: Dictionary = {
	&"size_x": { "label": "Width", "about": "Width in metres", "min": 0.05, "max": 64.0, "step": 0.05, "default": 2.0, "phrase": "%s m wide" },
	&"size_y": { "label": "Height", "about": "Height in metres", "min": 0.05, "max": 64.0, "step": 0.05, "default": 2.0, "phrase": "%s m tall" },
	&"size_z": { "label": "Depth", "about": "Depth in metres", "min": 0.05, "max": 64.0, "step": 0.05, "default": 2.0, "phrase": "%s m deep" },
	&"stair_steps": { "label": "Steps", "about": "Number of steps in the run", "min": 1.0, "max": 32.0, "step": 1.0, "default": 8.0, "phrase": "%s steps" },
	&"cylinder_sides": { "label": "Sides", "about": "Number of sides around the cylinder", "min": 3.0, "max": 32.0, "step": 1.0, "default": 16.0, "phrase": "%s sides" },
	&"arch_segments": { "label": "Segments", "about": "Number of segments along the arch", "min": 4.0, "max": 32.0, "step": 1.0, "default": 8.0, "phrase": "%s segments" },
	&"arch_thickness": { "label": "Thickness", "about": "Band thickness in metres", "min": 0.05, "max": 8.0, "step": 0.05, "default": 0.25, "phrase": "%s m thick" },
	&"arch_arc": { "label": "Arc", "about": "Sweep in degrees, centered on the crown", "min": ARC_MIN_DEG, "max": ARC_MAX_DEG, "step": 5.0, "default": 180.0, "phrase": "%s degrees of arc" },
}

const CATALOG: Dictionary = {
	&"make_box": {
		"label": "Box", "icon": "BoxMesh", "tooltip": "Creates a box solid at the scene origin.",
		"params": [&"size_x", &"size_y", &"size_z"], "derives": "",
	},
	&"make_plane": {
		"label": "Plane", "icon": "PlaneMesh", "tooltip": "Creates a flat slab.",
		"params": [&"size_x", &"size_z"], "derives": "Thickness is the solid's grid step.",
	},
	&"make_stair": {
		"label": "Stair", "icon": "Stair", "tooltip": "Creates a straight run of steps.",
		"params": [&"size_x", &"size_y", &"size_z", &"stair_steps"], "derives": "",
	},
	&"make_cylinder": {
		"label": "Cylinder", "icon": "CylinderMesh", "tooltip": "Creates a cylinder.",
		"params": [&"size_x", &"size_y", &"cylinder_sides"], "derives": "Width is the diameter.",
	},
	&"make_arch": {
		"label": "Arch", "icon": "CapsuleMesh", "tooltip": "Creates an arch.",
		"params": [&"size_x", &"size_z", &"arch_segments", &"arch_thickness", &"arch_arc"],
		"derives": "Height follows Width and Arc.",
	},
	&"make_poly_shape": {
		"label": "Poly Shape", "icon": "PrismMesh", "tooltip": "Extrudes a square outline into a prism.",
		"params": [&"size_x", &"size_y", &"size_z"], "derives": "",
	},
	&"make_sweep": {
		"label": "Curve Sweep", "icon": "Curve3D", "tooltip": "Sweeps a corridor profile along a path.",
		"params": [&"size_x", &"size_y", &"size_z"], "derives": "Depth sets the path length.",
	},
}

var _values: Dictionary[StringName, float] = {}


func _init() -> void:
	for key in PARAMS:
		_values[key] = float(PARAMS[key]["default"])


func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in CATALOG:
		var entry: Dictionary = CATALOG[id]
		out.append({ "id": id, "label": entry["label"], "icon": entry["icon"], "tooltip": entry["tooltip"] })
	return out


func plan(id: StringName) -> Dictionary:
	match id:
		&"make_box":
			return _built("make_box", "Box", [size()])
		&"make_plane":
			return _built("make_plane", "Plane", [Vector2(width(), depth())])
		&"make_stair":
			return _built("make_stair", "Stair", [size(), int_of(&"stair_steps")])
		&"make_cylinder":
			return _built("make_cylinder", "Cylinder", [width() * 0.5, height(), int_of(&"cylinder_sides")])
		&"make_arch":
			return _arch_plan()
		&"make_poly_shape":
			return _built("make_prism", "PolyShape", [_square_outline(), height()])
		&"make_sweep":
			return _built("make_sweep", "Sweep", [_sweep_path(), Vector2(width(), height()), false])
	return {}


func fields() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in PARAMS:
		out.append(_field(key))
	return out


func fields_for(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not CATALOG.has(id):
		return out
	for key in CATALOG[id]["params"]:
		out.append(_field(key))
	return out


func _field(key: StringName) -> Dictionary:
	var param: Dictionary = PARAMS[key]
	return {
		"key": key,
		"label": param["label"],
		"min": param["min"],
		"max": param["max"],
		"step": param["step"],
		"value": _values[key],
		"tooltip": _field_tooltip(key),
	}


func set_value(key: StringName, value: float) -> void:
	if not PARAMS.has(key):
		return
	var param: Dictionary = PARAMS[key]
	_values[key] = clampf(value, param["min"], param["max"])


func describe(id: StringName) -> String:
	if not CATALOG.has(id):
		return ""
	var entry: Dictionary = CATALOG[id]
	var bits := PackedStringArray()
	for key in entry["params"]:
		bits.append(PARAMS[key]["phrase"] % _number(value_of(key)))
	var text: String = ", ".join(bits) + "."
	var derives: String = entry["derives"]
	return text if derives == "" else "%s %s" % [text, derives]


func value_of(key: StringName) -> float:
	return _values.get(key, 0.0)


func int_of(key: StringName) -> int:
	return int(round(value_of(key)))


func size() -> Vector3:
	return Vector3(width(), height(), depth())


func width() -> float:
	return value_of(&"size_x")


func height() -> float:
	return value_of(&"size_y")


func depth() -> float:
	return value_of(&"size_z")


func _built(method: String, create: String, args: Array) -> Dictionary:
	return { "method": method, "args": args, "create": create }


func _number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return String.num(value, 2)


func _arch_plan() -> Dictionary:
	if value_of(&"arch_thickness") * 2.0 >= width():
		return { "status": "Arch thickness has to stay under half the width." }
	return _built("make_arch", "Arch", [
		width(), depth(), int_of(&"arch_segments"), value_of(&"arch_thickness"), deg_to_rad(value_of(&"arch_arc")),
	])


func _field_tooltip(key: StringName) -> String:
	var about: String = PARAMS[key]["about"]
	var users: Array[String] = []
	var others: Array[String] = []
	for id in CATALOG:
		var entry: Dictionary = CATALOG[id]
		if entry["params"].has(key):
			users.append(entry["label"])
		else:
			others.append(entry["label"])
	if others.is_empty():
		return "%s. Every Create button uses it." % about
	if users.size() == 1:
		return "%s. Only %s uses it." % [about, users[0]]
	var verb: String = "ignores" if others.size() == 1 else "ignore"
	return "%s. Used by %s. %s %s it." % [about, _list(users), _list(others), verb]


func _list(labels: Array[String]) -> String:
	if labels.size() == 1:
		return labels[0]
	var last: String = labels[-1]
	return "%s and %s" % [", ".join(labels.slice(0, -1)), last]


func _square_outline() -> PackedVector3Array:
	var half_x: float = width() * 0.5
	var half_z: float = depth() * 0.5
	return PackedVector3Array([
		Vector3(-half_x, 0.0, -half_z),
		Vector3(half_x, 0.0, -half_z),
		Vector3(half_x, 0.0, half_z),
		Vector3(-half_x, 0.0, half_z),
	])


func _sweep_path() -> PackedVector3Array:
	var length: float = depth() * 2.0
	return PackedVector3Array([
		Vector3.ZERO,
		Vector3(0.0, 0.0, length * 0.5),
		Vector3(length * 0.5, 0.0, length),
	])
