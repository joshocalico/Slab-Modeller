@tool
extends RefCounted

const SlabElementXform := preload("res://addons/slab/slab_element_xform.gd")
const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")

signal preview_changed(preview: Dictionary)
signal reported(text: String)

enum Mode { NONE, VERTEX, FACE }

var active := false
var mode: int = Mode.NONE
var oppose_face_normals := true

var _selection: RefCounted
var _host: RefCounted
var _source: Node3D
var _source_ids := PackedInt64Array()
var _source_mode: int = SlabSelection.Mode.OBJECT
var _source_anchor_world := Vector3.ZERO
var _source_anchor_vertex: int = 0
var _source_face: int = 0
var _before_data := PackedByteArray()
var _before_transform := Transform3D.IDENTITY
var _preview: Dictionary = {}


func _init(selection: RefCounted, host: RefCounted) -> void:
	_selection = selection
	_host = host
	if _selection != null and _selection.has_signal("changed"):
		_selection.changed.connect(_selection_changed)


func begin_vertex_snap() -> bool:
	cancel()
	if _selection.solid == null or _selection.ids.is_empty() or _selection.mode == SlabSelection.Mode.OBJECT:
		_report("Snap to Vertex needs selected vertices, edges, or faces.")
		return false
	_source = _selection.solid
	_source_ids = PackedInt64Array(_selection.ids)
	_source_mode = _selection.mode
	var source_vertices: PackedInt64Array = SlabElementXform.vertices(_source, _source_mode, _source_ids)
	if source_vertices.is_empty():
		_report("Snap to Vertex needs a selection containing at least one vertex.")
		return false
	_source_anchor_vertex = source_vertices[0]
	_before_data = _source.get("data")
	_before_transform = _source.transform
	_source_anchor_world = _source.to_global(_source.call("vertex_position", _source_anchor_vertex))
	active = true
	mode = Mode.VERTEX
	_report("Snap to Vertex: point at a vertex on another solid. Click applies; Escape cancels.")
	return true


func begin_face_align(source_face: int = 0) -> bool:
	cancel()
	var face: int = source_face if source_face != 0 else (_selection.ids[0] if _selection.mode == SlabSelection.Mode.FACE and not _selection.ids.is_empty() else 0)
	if _selection.solid == null or face == 0 or (_selection.solid.call("face_uv", face) as Dictionary).is_empty():
		_report("Align Face needs one source face.")
		return false
	_source = _selection.solid
	_source_face = face
	_before_transform = _source.transform
	_before_data = _source.get("data")
	active = true
	mode = Mode.FACE
	_report("Align Face: point at a face on another solid. Click applies; Escape cancels.")
	return true


func preview() -> Dictionary:
	return _preview.duplicate(true)


func refresh() -> void:
	if not active or _preview.is_empty():
		return
	var target: Node3D = _preview.get("target")
	var target_id: int = _preview.get("target_id", 0)
	if mode == Mode.VERTEX:
		target_vertex(target, target_id)
	else:
		target_face(target, target_id)


func target_vertex(target: Node3D, vertex: int) -> bool:
	if not _source_unchanged() or mode != Mode.VERTEX or not _valid_other(target):
		return false
	var local: Vector3 = target.call("vertex_position", vertex)
	if local == Vector3.ZERO and not _has_id(target.call("get_vertices"), vertex):
		return false
	var target_world := target.to_global(local)
	var delta_world := target_world - _source_anchor_world
	var delta_local := _source.global_transform.basis.inverse() * delta_world
	_preview = {
		"mode": Mode.VERTEX,
		"source": _source,
		"target": target,
		"target_id": vertex,
		"source_anchor_id": _source_anchor_vertex,
		"delta_local": delta_local,
		"lines": PackedVector3Array([_source.to_local(_source_anchor_world), _source.to_local(target_world)]),
	}
	_emit_preview()
	return true


func target_face(target: Node3D, face: int) -> bool:
	if not _source_unchanged() or mode != Mode.FACE or not _valid_other(target):
		return false
	if (target.call("face_uv", face) as Dictionary).is_empty():
		return false
	var source_normal := (_source.global_transform.basis * (_source.call("face_normal", _source_face) as Vector3)).normalized()
	var target_normal := (target.global_transform.basis * (target.call("face_normal", face) as Vector3)).normalized()
	var wanted := -target_normal if oppose_face_normals else target_normal
	if source_normal.is_zero_approx() or wanted.is_zero_approx():
		return false
	var turn := Basis(Quaternion(source_normal, wanted))
	var desired_global := _source.global_transform
	desired_global.basis = turn * desired_global.basis
	var source_local_centroid: Vector3 = _source.call("face_centroid", _source_face)
	var rotated_centroid := desired_global * source_local_centroid
	var target_centroid := target.to_global(target.call("face_centroid", face))
	desired_global.origin += target_centroid - rotated_centroid
	var desired_local := desired_global
	if _source.get_parent() is Node3D:
		desired_local = (_source.get_parent() as Node3D).global_transform.affine_inverse() * desired_global
	_preview = {
		"mode": Mode.FACE,
		"source": _source,
		"target": target,
		"target_id": face,
		"transform": desired_local,
		"global_transform": desired_global,
		"lines": _face_outline_in_source(target, face),
	}
	_emit_preview()
	return true


func handle(camera: Camera3D, event: InputEvent) -> int:
	if not active:
		return 0
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel()
		_report("Snap / Align cancelled.")
		return 1
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel()
		_report("Snap / Align cancelled.")
		return 1
	if not is_instance_valid(camera):
		return 1
	if event is InputEventMouseMotion:
		_pick_target(camera, event.position)
		return 1
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick_target(camera, event.position)
		confirm()
		return 1
	return 1


func confirm() -> bool:
	if not _source_unchanged() or _preview.is_empty():
		cancel()
		return false
	var undo: Object = _host.undo()
	if undo == null:
		_report("Snap / Align needs editor undo.")
		return false
	var before_data := _before_data.duplicate()
	if mode == Mode.VERTEX:
		var vertices: PackedInt64Array = SlabElementXform.vertices(_source, _source_mode, _source_ids)
		var err: int = _source.call("move_vertices", vertices, _preview["delta_local"])
		if err != OK:
			_report("Snap to Vertex was refused.")
			return false
		var after: PackedByteArray = _source.get("data")
		undo.create_action("Slab Snap to Vertex", UndoRedo.MERGE_DISABLE, _source)
		undo.add_do_property(_source, "data", after)
		undo.add_undo_property(_source, "data", before_data)
		undo.commit_action(false)
	else:
		var after_transform: Transform3D = _preview["transform"]
		_source.transform = after_transform
		undo.create_action("Slab Align Face", UndoRedo.MERGE_DISABLE, _source)
		undo.add_do_property(_source, "transform", after_transform)
		undo.add_undo_property(_source, "transform", _before_transform)
		undo.commit_action(false)
	cancel()
	_report("Snap / Align applied. Undo restores the source.")
	return true


func cancel() -> void:
	active = false
	mode = Mode.NONE
	_source = null
	_source_ids.clear()
	_source_face = 0
	_source_anchor_vertex = 0
	_before_data.clear()
	_preview.clear()
	if _selection != null:
		_selection.preview_solid = null
		_selection.preview_lines = PackedVector3Array()
		_selection.hover_changed.emit()
	preview_changed.emit({})


func _pick_target(camera: Camera3D, screen: Vector2) -> void:
	var target := SlabPick.pick_solid(_host.scene_root(), camera, screen)
	if not _valid_other(target):
		_preview.clear()
		_emit_preview()
		return
	if mode == Mode.VERTEX:
		var vertex: int = SlabPick.pick(target, SlabSelection.Mode.VERTEX, camera, screen, 16.0)
		if vertex != 0:
			target_vertex(target, vertex)
	else:
		var face: int = SlabPick.pick(target, SlabSelection.Mode.FACE, camera, screen)
		if face != 0:
			target_face(target, face)


func _emit_preview() -> void:
	if _selection != null:
		_selection.preview_solid = _source
		_selection.preview_lines = _preview.get("lines", PackedVector3Array())
		_selection.hover_changed.emit()
	preview_changed.emit(preview())


func _source_unchanged() -> bool:
	return active and is_instance_valid(_source) and _source.get("data") == _before_data and _source.transform == _before_transform


func _valid_other(target: Node3D) -> bool:
	return target != null and is_instance_valid(target) and target != _source and target.is_class("SlabSolid")


func _face_outline_in_source(target: Node3D, face: int) -> PackedVector3Array:
	var corners: PackedVector3Array = target.call("face_corners", face)
	var out := PackedVector3Array()
	for i in corners.size():
		out.append(_source.to_local(target.to_global(corners[i])))
		out.append(_source.to_local(target.to_global(corners[(i + 1) % corners.size()])))
	return out


func _has_id(ids: PackedInt64Array, wanted: int) -> bool:
	return ids.find(wanted) != -1


func _report(message: String) -> void:
	reported.emit(message)


func _selection_changed() -> void:
	if not active:
		return
	if _selection.solid != _source or _selection.mode != _source_mode or _selection.ids != _source_ids:
		cancel()
		_report("Snap / Align cancelled because the source selection changed.")
