@tool
extends RefCounted

enum Kind { EXTRUDE, INSET, BEVEL }

const MIN_AMOUNT := 0.001

var active := false
var kind := Kind.EXTRUDE
var amount := 0.5
var segments := 1
var solid: Node3D
var ids := PackedInt64Array()
var anchor := Vector3.ZERO
var axis := Vector3.UP
var tangent := Vector3.RIGHT
var preview_data := PackedByteArray()
var preview_lines := PackedVector3Array()
var result_ids := PackedInt64Array()
var error: int = OK
var _before := PackedByteArray()


func begin(next_kind: int, target: Node3D, selected_ids: PackedInt64Array,
		initial_amount: float, bevel_segments: int = 1) -> bool:
	cancel()
	if target == null or selected_ids.is_empty() or next_kind < Kind.EXTRUDE or next_kind > Kind.BEVEL:
		return false
	kind = next_kind
	solid = target
	ids = selected_ids.duplicate()
	amount = initial_amount if kind == Kind.EXTRUDE else maxf(MIN_AMOUNT, absf(initial_amount))
	segments = clampi(bevel_segments, 1, 16)
	tangent = Vector3.ZERO
	_before = solid.get("data")
	if not _make_frame():
		cancel()
		return false
	active = true
	refresh()
	return true


func geometry(length: float = 0.8) -> Dictionary:
	if not active:
		return {}
	var display_length := maxf(length, absf(amount))
	var display_axis := -axis if kind == Kind.EXTRUDE and amount < 0.0 else axis
	var tip := anchor + display_axis * display_length
	var lines := PackedVector3Array([anchor, tip])
	if kind == Kind.INSET:
		lines = PackedVector3Array([anchor - axis * display_length, anchor + axis * display_length])
	return {
		"kind": kind,
		"anchor": anchor,
		"axis": display_axis,
		"tangent": tangent,
		"tip": tip,
		"segments": lines,
		"amount": amount,
		"label": "%s  %.3f m" % [_name(), amount],
	}


func hit_test(camera: Camera3D, screen: Vector2, radius: float = 14.0) -> bool:
	if not active or camera == null:
		return false
	var shape := geometry()
	var line: PackedVector3Array = shape["segments"]
	for i in range(0, line.size(), 2):
		if _segment_distance(screen, camera.unproject_position(line[i]), camera.unproject_position(line[i + 1])) <= radius:
			return true
	return false


func drag_value(camera: Camera3D, press_screen: Vector2, current_screen: Vector2) -> float:
	if not active or camera == null:
		return amount
	var delta := _axis_travel(camera, current_screen, anchor, axis) - _axis_travel(camera, press_screen, anchor, axis)
	return delta


func set_amount(value: float) -> void:
	if not active:
		return
	amount = maxf(MIN_AMOUNT, absf(value)) if kind != Kind.EXTRUDE else value
	refresh()


func refresh() -> void:
	preview_data.clear()
	preview_lines.clear()
	result_ids.clear()
	error = ERR_INVALID_DATA
	if not active or not is_instance_valid(solid) or solid.get("data") != _before:
		if is_instance_valid(solid):
			solid.call("clear_display_preview")
		return
	var scratch: Node3D = ClassDB.instantiate("SlabSolid")
	if scratch == null:
		solid.call("clear_display_preview")
		return
	scratch.set("data", _before)
	if kind == Kind.EXTRUDE:
		error = int(scratch.call("extrude_faces", ids, amount))
	elif kind == Kind.INSET:
		error = int(scratch.call("inset_faces", ids, amount))
	else:
		var result: Dictionary = scratch.call("preview_bevel", ids, amount, segments)
		error = int(result.get("error", ERR_INVALID_DATA))
		preview_lines = result.get("segments", PackedVector3Array())
		preview_data = result.get("data", PackedByteArray())
	if kind != Kind.BEVEL:
		if error == OK:
			for edge in PackedInt64Array(scratch.call("get_edges")):
				preview_lines.append_array(scratch.call("edge_endpoints", edge))
		else:
			preview_lines = (scratch.call("get_edit_diagnostic") as Dictionary).get("segments", PackedVector3Array())
	if error == OK and preview_data.is_empty():
		preview_data = scratch.get("data")
	if error == OK and kind != Kind.BEVEL:
		result_ids = scratch.call("get_last_edited_faces")
	scratch.free()
	if error == OK and not preview_data.is_empty() and is_instance_valid(solid):
		if not bool(solid.call("set_display_preview", preview_data)):
			error = ERR_INVALID_DATA
	if error != OK and is_instance_valid(solid):
		solid.call("clear_display_preview")


func preview() -> Dictionary:
	return { "error": error, "data": preview_data, "segments": preview_lines,
		"geometry": geometry(), "amount": amount, "result_ids": result_ids }


func confirm(undo: Object = null) -> Dictionary:
	if active and (not is_instance_valid(solid) or solid.get("data") != _before):
		cancel()
		return {}
	if not active or error != OK or preview_data.is_empty() or not is_instance_valid(solid) or solid.get("data") != _before:
		return {}
	var target := solid
	var before := _before.duplicate()
	var after := preview_data.duplicate()
	var selected := result_ids.duplicate()
	target.set("data", after)
	if undo != null and before != after:
		undo.create_action("Slab %s" % _name(), UndoRedo.MERGE_DISABLE, target)
		undo.add_do_property(target, "data", after)
		undo.add_undo_property(target, "data", before)
		undo.commit_action(false)
	cancel()
	return { "solid": target, "before": before, "after": after, "result_ids": selected, "amount": amount }


func cancel() -> void:
	var target := solid
	active = false
	solid = null
	ids.clear()
	_before.clear()
	preview_data.clear()
	preview_lines.clear()
	result_ids.clear()
	tangent = Vector3.ZERO
	error = OK
	if is_instance_valid(target):
		target.call("clear_display_preview")


func _make_frame() -> bool:
	if kind == Kind.BEVEL:
		return _bevel_frame()
	var normal_sum := Vector3.ZERO
	var centre_sum := Vector3.ZERO
	var weight_sum := 0.0
	for face in ids:
		var corners: PackedVector3Array = solid.call("face_corners", face)
		if corners.size() < 3:
			return false
		var area_vector := Vector3.ZERO
		for i in corners.size():
			area_vector += corners[i].cross(corners[(i + 1) % corners.size()])
		var weight := maxf(area_vector.length() * 0.5, 0.0001)
		normal_sum += _world_normal(face) * weight
		centre_sum += solid.to_global(solid.call("face_centroid", face)) * weight
		weight_sum += weight
	if weight_sum <= 0.0 or normal_sum.length_squared() < 0.0001:
		return false
	anchor = centre_sum / weight_sum
	if kind == Kind.EXTRUDE:
		axis = normal_sum.normalized()
		tangent = _stable_tangent(axis)
		return true
	var midpoint := Vector3.ZERO
	var found_boundary := false
	for face in ids:
		for edge in PackedInt64Array(solid.call("face_edges", face)):
			var adjacent := PackedInt64Array(solid.call("edge_faces", edge))
			var internal := adjacent.size() == 2 and ids.has(adjacent[0]) and ids.has(adjacent[1])
			if internal:
				continue
			var ends: PackedVector3Array = solid.call("edge_endpoints", edge)
			if ends.size() == 2:
				midpoint = solid.to_global((ends[0] + ends[1]) * 0.5)
				tangent = (solid.to_global(ends[1]) - solid.to_global(ends[0])).normalized()
				found_boundary = true
				break
		if found_boundary:
			break
	if not found_boundary:
		return false
	axis = (midpoint - anchor).normalized()
	tangent = _stable_tangent(axis)
	return axis.length_squared() > 0.0001


func _bevel_frame() -> bool:
	var centre := Vector3.ZERO
	var normal := Vector3.ZERO
	for edge in ids:
		var ends: PackedVector3Array = solid.call("edge_endpoints", edge)
		if ends.size() < 2:
			return false
		centre += solid.to_global((ends[0] + ends[1]) * 0.5)
		if tangent == Vector3.ZERO:
			tangent = (solid.to_global(ends[1]) - solid.to_global(ends[0])).normalized()
		for face in PackedInt64Array(solid.call("edge_faces", edge)):
			normal += _world_normal(face)
	anchor = centre / float(ids.size())
	axis = normal.normalized()
	return axis.length_squared() > 0.0001


static func _stable_tangent(direction: Vector3) -> Vector3:
	var result := direction.cross(Vector3.FORWARD)
	if result.length_squared() < 0.001:
		result = direction.cross(Vector3.RIGHT)
	return result.normalized()


func _world_normal(face: int) -> Vector3:
	return (solid.global_transform.basis.inverse().transposed() * solid.call("face_normal", face)).normalized()


func _name() -> String:
	return "Extrude" if kind == Kind.EXTRUDE else ("Inset" if kind == Kind.INSET else "Bevel")


static func _axis_travel(camera: Camera3D, screen: Vector2, line_anchor: Vector3, line_axis: Vector3) -> float:
	var u := camera.project_ray_normal(screen)
	var w0 := camera.project_ray_origin(screen) - line_anchor
	var b := u.dot(line_axis)
	var denominator := u.dot(u) * line_axis.dot(line_axis) - b * b
	if absf(denominator) < 0.0000001:
		return 0.0
	return (u.dot(u) * line_axis.dot(w0) - b * u.dot(w0)) / denominator


static func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return point.distance_to(a + ab * t)
