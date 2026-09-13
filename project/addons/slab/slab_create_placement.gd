@tool
extends RefCounted

const SlabPick := preload("res://addons/slab/slab_pick.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")

signal preview_changed(solid: Node3D)
signal reported(message: String)

var _host: RefCounted
var _actions: RefCounted
var _solid: Node3D
var _row: Dictionary = {}
var _anchor := Vector3.ZERO
var _has_anchor := false
var _prototype_color := Color.WHITE
var _collision_enabled := true


func _init(host: RefCounted, actions: RefCounted) -> void:
	_host = host
	_actions = actions


func active() -> bool:
	return _solid != null and is_instance_valid(_solid)


func preview() -> Node3D:
	return _solid if active() else null


func begin(row: Dictionary, plan: Dictionary) -> bool:
	cancel(false)
	var root: Node = _host.scene_root() if _host != null else null
	if root == null:
		reported.emit("Open a scene before placing a solid.")
		return false
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		reported.emit("SlabSolid is not built yet.")
		return false
	var candidate := ClassDB.instantiate(SlabSelection.SOLID_CLASS) as Node3D
	if candidate == null:
		reported.emit("SlabSolid is not built yet.")
		return false
	candidate.name = str(plan.get("create", row.get("label", "Solid")))
	var method: String = plan.get("method", "")
	if method == "" or not candidate.has_method(method):
		candidate.free()
		reported.emit("%s is not built yet." % row.get("label", "Shape"))
		return false
	var err: int = candidate.callv(method, plan.get("args", []))
	if err != OK:
		candidate.free()
		reported.emit("%s failed." % row.get("label", "Shape"))
		return false
	_collision_enabled = bool(candidate.get("collision_enabled"))
	_prototype_color = candidate.get("prototype_color")
	candidate.set("collision_enabled", false)
	candidate.set("prototype_color", Color(0.86, 0.72, 0.34))
	root.add_child(candidate, true)
	_row = row.duplicate()
	_solid = candidate
	_has_anchor = false
	_solid.visible = false
	preview_changed.emit(_solid)
	reported.emit("Place %s: move over a horizontal Slab surface or the world ground plane, then click or press Enter. Escape cancels." % row.get("label", "shape"))
	return true


func handle(camera: Camera3D, event: InputEvent) -> bool:
	if not active():
		return false
	if event is InputEventMouseMotion:
		_update_anchor(camera, event.position)
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_update_anchor(camera, event.position)
		confirm()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			confirm()
			return true
		if event.keycode == KEY_ESCAPE:
			cancel()
			return true
	return false


func confirm() -> bool:
	if not active():
		return false
	if not _has_anchor:
		reported.emit("Move over a Slab surface or the world ground plane before placing the shape.")
		return false
	var target := _solid
	var parent := target.get_parent()
	var transform := target.transform
	target.set("prototype_color", _prototype_color)
	target.set("collision_enabled", _collision_enabled)
	parent.remove_child(target)
	_solid = null
	_has_anchor = false
	preview_changed.emit(null)
	_actions.commit_placed_create(_row, target, parent, transform)
	_row = {}
	return true


func cancel(report := true) -> void:
	if not active():
		return
	var target := _solid
	_solid = null
	_has_anchor = false
	_row = {}
	if target.get_parent() != null:
		target.get_parent().remove_child(target)
	target.free()
	preview_changed.emit(null)
	if report:
		reported.emit("Create cancelled.")


func _update_anchor(camera: Camera3D, screen: Vector2) -> void:
	if camera == null or not active():
		return
	_invalidate_anchor()
	var hit := SlabPick.pick_world_hit(_host.scene_root(), camera, screen, _solid)
	if not hit.is_empty():
		var hit_solid: Node3D = hit.get("solid")
		var face: int = int(hit.get("id", 0))
		if hit_solid != null and face != 0:
			var local_normal: Vector3 = hit_solid.call("face_normal", face)
			var world_normal := (hit_solid.global_transform.basis.inverse().transposed() * local_normal).normalized()
			if world_normal.y > 0.99999:
				_place_at(hit.get("world", _anchor), true)
				return
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if absf(direction.y) <= 0.000001:
		return
	var distance := -origin.y / direction.y
	if distance >= 0.0:
		_place_at(origin + direction * distance, false)


func _invalidate_anchor() -> void:
	_has_anchor = false
	if active():
		_solid.visible = false
		preview_changed.emit(_solid)


func _place_at(world: Vector3, surface_hit: bool) -> void:
	if not active():
		return
	_anchor = _snap(world, surface_hit)
	var aabb: AABB = _solid.call("get_local_aabb")
	var bottom_center := Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y,
		aabb.position.z + aabb.size.z * 0.5)
	var parent := _solid.get_parent() as Node3D
	var desired := Transform3D(Basis.IDENTITY, _anchor - bottom_center)
	_solid.transform = parent.global_transform.affine_inverse() * desired if parent != null else desired
	_has_anchor = true
	_solid.visible = true
	preview_changed.emit(_solid)


func _snap(point: Vector3, preserve_height: bool) -> Vector3:
	var step := 0.5
	if active() and _solid.get("grid_step") != null:
		step = maxf(float(_solid.get("grid_step")), 0.0001)
	return Vector3(snappedf(point.x, step), point.y if preserve_height else snappedf(point.y, step),
		snappedf(point.z, step))
