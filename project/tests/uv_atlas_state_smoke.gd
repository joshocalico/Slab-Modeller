extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const PaintUv := preload("res://addons/slab/slab_paint_uv.gd")
const Undo := preload("res://tests/slab_test_undo.gd")
var failures := 0


func _initialize() -> void:
	var selection := Selection.new()
	var undo := Undo.new()
	var actions := Actions.new(selection, undo)
	var a := _solid()
	var b := _solid()
	var face_a: int = a.call("get_faces")[0]
	var face_b: int = b.call("get_faces")[0]
	selection.set_objects([a])
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([face_a]))
	actions.uv_pixels_per_meter = 64
	actions.uv_texture_resolution = 512
	check(actions._unwrap_target(a).begins_with("Unwrapped"), "unwrap A at 512")
	var length_a := _edge_length(a, face_a)
	var saved_a: PackedByteArray = a.get("data")
	selection.set_objects([b])
	selection.set_ids(PackedInt64Array([face_b]))
	actions.uv_texture_resolution = 2048
	check(actions._unwrap_target(b).begins_with("Unwrapped"), "unwrap B at 2048")
	selection.set_objects([a])
	selection.set_ids(PackedInt64Array([face_a]))
	check(actions._pack_target(a).begins_with("Packed"), "pack A after authoring B")
	check(is_equal_approx(_edge_length(a, face_a), length_a / 4.0), "A keeps its own pixel density")
	check(a.call("face_uv", face_a).texture_resolution == 2048, "pack stores destination resolution")
	undo.undo()
	check(a.get("data") == saved_a, "Undo restores mapping and resolution")
	check(a.call("face_uv", face_a).texture_resolution == 512, "Undo restores A source atlas")
	var reopened := _solid()
	reopened.set("data", saved_a)
	selection.set_objects([reopened])
	selection.set_ids(PackedInt64Array([face_a]))
	var fresh_actions := Actions.new(selection)
	fresh_actions.uv_texture_resolution = 1024
	check(fresh_actions._pack_target(reopened).begins_with("Packed"), "pack works in fresh session")
	check(is_equal_approx(_edge_length(reopened, face_a), length_a / 2.0), "reload preserves source density")
	# Version 3 is the same payload without the per-face resolution tail.
	var legacy := saved_a.duplicate()
	legacy[4] = 3
	legacy.resize(legacy.size() - int(a.call("face_count")) * 4)
	reopened.set("data", legacy)
	check(reopened.call("face_uv", face_a).texture_resolution == 0, "old scene loads unknown source resolution")
	check(fresh_actions._pack_target(reopened).begins_with("Packed"), "old scene can pack")
	check(is_equal_approx(_edge_length(reopened, face_a), length_a), "old scene defaults to current atlas without rescaling")
	a.free()
	b.free()
	reopened.free()
	print("uv_atlas_state_smoke: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _solid() -> Node3D:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	root.add_child(solid)
	solid.call("make_box", Vector3.ONE)
	return solid


func _edge_length(solid: Node3D, face: int) -> float:
	var uvs := PaintUv.face_uvs(solid, face)
	return uvs[0].distance_to(uvs[1])


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
