@tool
extends RefCounted

signal changed

enum Mode { OBJECT, VERTEX, EDGE, FACE }

const SOLID_CLASS := "SlabSolid"

const MODE_LABELS: Dictionary = {
	Mode.OBJECT: "Object",
	Mode.VERTEX: "Vertex",
	Mode.EDGE: "Edge",
	Mode.FACE: "Face",
}

const MODE_NOUNS: Dictionary = {
	Mode.OBJECT: ["solid", "solids"],
	Mode.VERTEX: ["vertex", "vertices"],
	Mode.EDGE: ["edge", "edges"],
	Mode.FACE: ["face", "faces"],
}

var mode: int = Mode.OBJECT:
	set(value):
		if value == mode or not MODE_LABELS.has(value):
			return
		mode = value
		ids = PackedInt64Array()
		changed.emit()

var objects: Array[Node3D] = []

var ids: PackedInt64Array = PackedInt64Array()

var solid: Node3D:
	get:
		return objects[0] if not objects.is_empty() else null
	set(value):
		set_objects([value] if value != null else [])


static func is_solid(node: Object) -> bool:
	return node != null and node.is_class(SOLID_CLASS)


static func owning_solid(node: Object) -> Node3D:
	var current: Node = node as Node
	while current != null:
		if is_solid(current):
			return current
		current = current.get_parent()
	return null


func set_objects(nodes: Array) -> void:
	var kept: Array[Node3D] = []
	for node in nodes:
		var solid: Node3D = owning_solid(node)
		if solid != null and not kept.has(solid):
			kept.append(solid)
	if kept == objects:
		return
	objects = kept
	ids = PackedInt64Array()
	changed.emit()


func set_ids(value: PackedInt64Array) -> void:
	if value == ids:
		return
	ids = value
	changed.emit()


func toggle_id(id: int, additive: bool) -> void:
	if not additive:
		set_ids(PackedInt64Array([id]) if id != 0 else PackedInt64Array())
		return
	var next := PackedInt64Array(ids)
	var at := next.find(id)
	if at == -1:
		next.append(id)
	else:
		next.remove_at(at)
	set_ids(next)


func clear_ids() -> void:
	set_ids(PackedInt64Array())


func count() -> int:
	return objects.size() if mode == Mode.OBJECT else ids.size()


func mode_label() -> String:
	return MODE_LABELS[mode]


func describe() -> String:
	if objects.is_empty():
		return "No solid selected."
	if mode == Mode.OBJECT:
		if objects.size() == 1:
			return "%s selected." % objects[0].name
		return "%d solids selected." % objects.size()
	var nouns: Array = MODE_NOUNS[mode]
	if ids.is_empty():
		return "No %s selected on %s." % [nouns[1], objects[0].name]
	var noun: String = nouns[0] if ids.size() == 1 else nouns[1]
	return "%d %s of %s." % [ids.size(), noun, objects[0].name]
