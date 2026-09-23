@tool
extends RefCounted

const Selection := preload("res://addons/slab/slab_selection.gd")
const PaintUv := preload("res://addons/slab/slab_paint_uv.gd")

signal changed
signal reported(message: String)

var active := false
var _solid: Node3D
var _undo: Object
var _before := PackedByteArray()
var _corners: Dictionary = {}
var _points: Dictionary = {}
var _pivot := Vector2.ZERO


# Face keys map to corner indices. An edge selects both of its endpoints.
static func selected_corners(solid: Node3D, mode: int, ids: PackedInt64Array) -> Dictionary:
	var result := {}
	if not is_instance_valid(solid):
		return result
	for id in ids:
		if mode == Selection.UVMode.UV_FACE:
			var info: Dictionary = solid.face_uv(id)
			if info.is_empty():
				continue
			var indices := PackedInt32Array()
			for i in info["points"].size():
				indices.append(i)
			result[id] = indices
		else:
			var corner: Dictionary = solid.uv_corner(id)
			if corner.is_empty():
				continue
			var face: int = corner["face"]
			var indices: PackedInt32Array = result.get(face, PackedInt32Array())
			var index: int = corner["corner"]
			if not indices.has(index):
				indices.append(index)
			if mode == Selection.UVMode.UV_EDGE:
				var next: int = (index + 1) % solid.face_uv(face)["points"].size()
				if not indices.has(next):
					indices.append(next)
			result[face] = indices
	return result


func begin(selection: RefCounted, undo: Object) -> bool:
	cancel()
	_solid = selection.solid
	_corners = selected_corners(_solid, selection.uv_mode, selection.get_uv_selection())
	if _corners.is_empty():
		return false
	_undo = undo
	_before = _solid.get("data")
	_points.clear()
	_pivot = Vector2.ZERO
	var count := 0
	for face in _corners:
		var points: PackedVector2Array = _solid.face_uv(face)["points"]
		_points[face] = points
		for index in _corners[face]:
			_pivot += points[index]
			count += 1
	_pivot /= float(count)
	active = true
	return true


# Delta is measured from the press, not the previous mouse event.
func drag(delta: Vector2, mode: int) -> void:
	if not active or not is_instance_valid(_solid):
		return
	var candidate := {}
	for face in _corners:
		var points: PackedVector2Array = _points[face].duplicate()
		for index in _corners[face]:
			if mode == 1:
				points[index] = _pivot + (points[index] - _pivot) * Vector2(maxf(.01, 1.0 + delta.x), maxf(.01, 1.0 + delta.y))
			elif mode == 2:
				points[index] = _pivot + (points[index] - _pivot).rotated(delta.x * PI)
			else:
				points[index] += delta
		candidate[face] = points
	var result := _candidate(_before, candidate)
	if result.has("data"):
		_solid.set("data", result["data"])
		changed.emit()
	else:
		reported.emit(result["error"])


func finish() -> void:
	if not active:
		return
	active = false
	if is_instance_valid(_solid):
		_record(_solid, _undo, _before, _solid.get("data"), "Slab Edit UV Elements")
	changed.emit()


func cancel() -> void:
	if active and is_instance_valid(_solid):
		_solid.set("data", _before)
	active = false
	changed.emit()


static func _candidate(before: PackedByteArray, points: Dictionary, pins: Dictionary = {}, pinned: bool = false, seam: int = 0) -> Dictionary:
	var scratch: Node3D = ClassDB.instantiate("SlabSolid")
	scratch.set("data", before)
	var error := 0
	for face in points:
		error = scratch.set_face_uv_points(face, points[face])
		if error != 0:
			break
	if error == 0:
		for face in pins:
			error = scratch.pin_uv_corners(face, pins[face], pinned)
			if error != 0:
				break
	if error == 0 and seam != 0:
		error = scratch.mark_uv_seams(PackedInt64Array([seam]), false)
	var result: Dictionary = {"data": scratch.get("data")} if error == 0 else {"error": "UV edit refused: mesh error %d." % error}
	scratch.free()
	return result


static func _record(solid: Node3D, undo: Object, before: PackedByteArray, after: PackedByteArray, label: String) -> void:
	if before == after or undo == null:
		return
	if undo is EditorUndoRedoManager:
		undo.create_action(label, UndoRedo.MERGE_DISABLE, solid)
	else:
		undo.create_action(label, UndoRedo.MERGE_DISABLE)
	undo.add_do_property(solid, "data", after)
	undo.add_undo_property(solid, "data", before)
	undo.commit_action(false)


static func _publish(solid: Node3D, undo: Object, result: Dictionary, label: String) -> String:
	if result.has("error"):
		return result["error"]
	var before: PackedByteArray = solid.get("data")
	solid.set("data", result["data"])
	_record(solid, undo, before, result["data"], label)
	return ""


static func pin(selection: RefCounted, undo: Object, pinned: bool) -> String:
	var solid: Node3D = selection.solid
	var corners := selected_corners(solid, selection.uv_mode, selection.get_uv_selection())
	if corners.is_empty():
		return "Select UV elements to pin or unpin."
	return _publish(solid, undo, _candidate(solid.get("data"), {}, corners, pinned), "Slab Pin UV" if pinned else "Slab Unpin UV")


static func _islands(solid: Node3D, selected: Dictionary) -> Array:
	var result: Array = []
	var seen := {}
	for face in selected:
		if seen.has(face):
			continue
		var island := PaintUv.island_faces(solid, PackedInt64Array([face]))
		result.append(island)
		for member in island:
			seen[member] = true
	return result


# Align entire islands; corner alignment would collapse selected UV polygons.
static func align(selection: RefCounted, undo: Object, axis: int, position: int) -> String:
	var solid: Node3D = selection.solid
	var selected := selected_corners(solid, selection.uv_mode, selection.get_uv_selection())
	if selected.is_empty():
		return "Select at least two UV islands to align."
	var islands := _islands(solid, selected)
	if islands.size() < 2:
		return "Select at least two UV islands to align."
	var bounds: Array[Vector2] = []
	var minimum := INF
	var maximum := -INF
	for island in islands:
		var lo := INF
		var hi := -INF
		for face in island:
			for point in solid.face_uv(face)["points"]:
				lo = minf(lo, point[axis])
				hi = maxf(hi, point[axis])
		bounds.append(Vector2(lo, hi))
		minimum = minf(minimum, lo)
		maximum = maxf(maximum, hi)
	var target := minimum if position < 0 else (maximum if position > 0 else (minimum + maximum) * .5)
	var points := {}
	for i in islands.size():
		var bound := bounds[i]
		var anchor := bound.x if position < 0 else (bound.y if position > 0 else (bound.x + bound.y) * .5)
		for face in islands[i]:
			var info: Dictionary = solid.face_uv(face)
			var loop: PackedVector2Array = info["points"].duplicate()
			for j in loop.size():
				if info["pins"][j] != 0 and absf(target - anchor) > .000001:
					return "Unpin the moving island before aligning it."
				loop[j][axis] += target - anchor
			points[face] = loop
	return _publish(solid, undo, _candidate(solid.get("data"), points), "Slab Align UV Islands")


static func stitch(selection: RefCounted, undo: Object) -> String:
	var solid: Node3D = selection.solid
	var ids: PackedInt64Array = selection.get_uv_selection()
	if not is_instance_valid(solid) or selection.uv_mode != Selection.UVMode.UV_EDGE or ids.size() != 2:
		return "Select the two sides of a shared mesh edge. The first side stays fixed."
	var a: Dictionary = solid.uv_corner(ids[0])
	var b: Dictionary = solid.uv_corner(ids[1])
	if a.is_empty() or b.is_empty():
		return "The selected UV edge no longer exists."
	var edge: int = solid.face_edges(a["face"])[a["corner"]]
	if edge != solid.face_edges(b["face"])[b["corner"]] or a["face"] == b["face"]:
		return "Stitch needs opposite UV sides of the same mesh edge."
	var moving := PaintUv.island_faces(solid, PackedInt64Array([b["face"]]))
	if moving.has(a["face"]):
		return "These edges already belong to the same island. Mark a seam to separate them first."
	var auv: PackedVector2Array = solid.face_uv(a["face"])["points"]
	var buv: PackedVector2Array = solid.face_uv(b["face"])["points"]
	var start: Vector2 = buv[b["corner"]]
	var end: Vector2 = buv[(b["corner"] + 1) % buv.size()]
	# Opposite half-edges wind in opposite directions on a legal solid.
	var dest: Vector2 = auv[(a["corner"] + 1) % auv.size()]
	var dest_end: Vector2 = auv[a["corner"]]
	if start.distance_to(end) < .000001 or dest.distance_to(dest_end) < .000001:
		return "Cannot stitch a collapsed UV edge."
	var scale := dest.distance_to(dest_end) / start.distance_to(end)
	var angle := (dest_end - dest).angle() - (end - start).angle()
	var points := {}
	for face in moving:
		var info: Dictionary = solid.face_uv(face)
		var loop: PackedVector2Array = info["points"].duplicate()
		for i in loop.size():
			var next := dest + (loop[i] - start).rotated(angle) * scale
			if info["pins"][i] != 0 and next.distance_to(loop[i]) > .000001:
				return "Unpin the moving island before stitching it."
			loop[i] = next
		points[face] = loop
	return _publish(solid, undo, _candidate(solid.get("data"), points, {}, false, edge), "Slab Stitch UV Islands")


static func _root(parents: Dictionary, id: int) -> int:
	while parents[id] != id:
		id = parents[id]
	return id


# A constrained harmonic relaxation. Shared UV corners move together, while
# seams, selection boundaries and pinned corners remain fixed.
static func relax(selection: RefCounted, undo: Object, iterations: int = 20) -> String:
	var solid: Node3D = selection.solid
	var selected := selected_corners(solid, selection.uv_mode, selection.get_uv_selection())
	if selected.is_empty():
		return "Select UV elements to relax."
	var records := {}
	var parents := {}
	var infos := {}
	var wanted := {}
	for face in solid.get_faces():
		var info: Dictionary = solid.face_uv(face)
		infos[face] = info
		for i in info["ids"].size():
			var id: int = info["ids"][i]
			parents[id] = id
			records[id] = {"uv": info["points"][i], "fixed": info["pins"][i] != 0, "face": face, "corner": i}
			wanted[id] = selected.has(face) and selected[face].has(i)
	var seams: PackedInt64Array = solid.get_uv_seams()
	for edge in solid.get_edges():
		var sides: PackedInt64Array = solid.edge_faces(edge)
		if sides.size() != 2:
			continue
		var af: int = sides[0]
		var bf: int = sides[1]
		var ai: int = solid.face_edges(af).find(edge)
		var bi: int = solid.face_edges(bf).find(edge)
		var a: Dictionary = infos[af]
		var b: Dictionary = infos[bf]
		var a0: int = a["ids"][ai]
		var a1: int = a["ids"][(ai + 1) % a["ids"].size()]
		var b0: int = b["ids"][bi]
		var b1: int = b["ids"][(bi + 1) % b["ids"].size()]
		var continuous: bool = not seams.has(edge) and records[a0]["uv"].distance_to(records[b1]["uv"]) < .00001 and records[a1]["uv"].distance_to(records[b0]["uv"]) < .00001
		if continuous:
			parents[_root(parents, b1)] = _root(parents, a0)
			parents[_root(parents, b0)] = _root(parents, a1)
		else:
			for id in [a0, a1, b0, b1]:
				records[id]["fixed"] = true
	var nodes := {}
	for id in records:
		var root := _root(parents, id)
		if not nodes.has(root):
			nodes[root] = {"uv": records[id]["uv"], "fixed": false, "neighbors": {}}
		nodes[root]["fixed"] = nodes[root]["fixed"] or records[id]["fixed"] or not wanted[id]
	for face in infos:
		var info: Dictionary = infos[face]
		var triangles: PackedInt32Array = info["triangles"]
		for i in range(0, triangles.size(), 3):
			for j in 3:
				var a := _root(parents, info["ids"][triangles[i + j]])
				var b := _root(parents, info["ids"][triangles[i + (j + 1) % 3]])
				if a != b:
					nodes[a]["neighbors"][b] = true
					nodes[b]["neighbors"][a] = true
	var movable := 0
	for id in nodes:
		if not nodes[id]["fixed"]:
			movable += 1
	if movable == 0:
		return "No interior UV vertices can move. Seams, pins and selection boundaries stay fixed."
	for step in clampi(iterations, 1, 100):
		var next := {}
		for id in nodes:
			var node: Dictionary = nodes[id]
			if node["fixed"] or node["neighbors"].is_empty():
				continue
			var mean := Vector2.ZERO
			for neighbor in node["neighbors"]:
				mean += nodes[neighbor]["uv"]
			next[id] = node["uv"].lerp(mean / float(node["neighbors"].size()), .5)
		for id in next:
			nodes[id]["uv"] = next[id]
	var points := {}
	for face in selected:
		var loop: PackedVector2Array = infos[face]["points"].duplicate()
		for i in loop.size():
			loop[i] = nodes[_root(parents, infos[face]["ids"][i])]["uv"]
		points[face] = loop
	return _publish(solid, undo, _candidate(solid.get("data"), points), "Slab Relax UV")
