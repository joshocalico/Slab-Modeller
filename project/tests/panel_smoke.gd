extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")

const REQUIRED_KEYS: PackedStringArray = [
	"id", "label", "icon", "modes", "min_count", "tooltip", "shortcut", "handler",
]

var _fails := 0


func _init() -> void:
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var rows: Array[Dictionary] = actions.rows()

	_expect(rows.size() >= 30, "registry has at least 30 rows, got %d" % rows.size())

	var seen: Dictionary = {}
	var valid_modes: Array = SlabSelection.Mode.values()
	for row in rows:
		var id: String = row.get("id", "")
		for key in REQUIRED_KEYS:
			_expect(row.has(key), "row %s has key %s" % [id, key])
		_expect(not seen.has(id), "row id %s is unique" % id)
		seen[id] = true
		_expect(row["modes"] is Array and not row["modes"].is_empty(), "row %s lists at least one mode" % id)
		for mode in row["modes"]:
			_expect(valid_modes.has(mode), "row %s mode %s is a Mode value" % [id, mode])
		_expect(row["handler"] is Callable and row["handler"].is_valid(), "row %s handler is a valid Callable" % id)
		_expect(row["min_count"] is int and row["min_count"] >= 0, "row %s min_count is a count" % id)
		_expect(row["shortcut"] is int, "row %s shortcut is a keycode" % id)

	_expect(actions.find("extrude_faces").has("id"), "find returns the extrude row")
	_expect(actions.find("no_such_action").is_empty(), "find returns nothing for an unknown id")

	selection.mode = SlabSelection.Mode.FACE
	selection.set_ids(PackedInt64Array([11, 22, 33]))
	_expect(selection.ids.size() == 3, "face selection holds three ids")
	selection.mode = SlabSelection.Mode.EDGE
	_expect(selection.ids.is_empty(), "changing mode clears the ids")
	_expect(selection.count() == 0, "count follows the cleared ids")
	_expect(selection.solid == null, "a fresh selection has no solid")
	_expect(selection.describe() == "No solid selected.", "status line reads as plain words")

	var blocked: String = actions.disabled_reason(actions.find("extrude_faces"))
	_expect(blocked == "Extrude needs Face mode.", "wrong mode disables extrude, got %s" % blocked)

	print("panel_smoke rows=%d sections=%s" % [rows.size(), ", ".join(actions.sections())])
	_finish()


func _expect(ok: bool, what: String) -> void:
	if ok:
		return
	push_error("FAIL " + what)
	print("FAIL ", what)
	_fails += 1


func _finish() -> void:
	if _fails != 0:
		push_error(str(_fails) + " failures")
		quit(1)
	else:
		print("panel_smoke ok")
		quit(0)
