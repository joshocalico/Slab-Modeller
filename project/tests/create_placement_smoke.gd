extends SceneTree

const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabCreatePlacement := preload("res://addons/slab/slab_create_placement.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabTestHost := preload("res://tests/slab_test_host.gd")
const SlabTestWorld := preload("res://tests/slab_test_world.gd")
const SlabViewport := preload("res://addons/slab/slab_viewport.gd")
const SlabTestUndo := preload("res://tests/slab_test_undo.gd")

var failures := 0


class PlacementActions:
	extends RefCounted
	var undo: RefCounted

	func _init(recorder: RefCounted) -> void:
		undo = recorder

	func commit_placed_create(_row: Dictionary, target: Node3D, parent: Node, transform: Transform3D) -> void:
		target.transform = transform
		undo.create_action("Place", UndoRedo.MERGE_DISABLE, parent)
		undo.add_do_method(parent, "add_child", target, true)
		undo.add_undo_method(parent, "remove_child", target)
		undo.commit_action()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not check(ClassDB.class_exists(SlabSelection.SOLID_CLASS), "SlabSolid is registered"):
		finish()
		return
	var world: RefCounted = SlabTestWorld.staged(self)
	var host: RefCounted = SlabTestHost.over(world.stage())
	var actions := SlabActions.new(SlabSelection.new())
	var placement := SlabCreatePlacement.new(host, actions)
	placement.reported.connect(func(message: String) -> void: print("placement: ", message))
	var row := actions.find("make_box")
	var initial_children: int = world.stage().get_child_count()
	check(placement.begin(row, actions.shapes.plan(&"make_box")), "box placement begins")
	var preview: Node3D = placement.preview()
	check(preview != null and preview.get_parent() == world.stage() and preview.owner == null,
		"preview is transient and unowned")
	check(not preview.visible and not placement.confirm(),
		"preview stays hidden and cannot commit before a valid viewport anchor")
	check(preview.call("get_local_aabb").size.is_equal_approx(Vector3(2, 2, 2)),
		"preview uses the chosen shape values")
	var floor_screen: Vector2 = world.camera().unproject_position(Vector3(4.13, 0, 1.86))
	var motion := InputEventMouseMotion.new()
	motion.position = floor_screen
	placement.handle(world.camera(), motion)
	var bounds: AABB = preview.call("get_local_aabb")
	var bottom_center := preview.to_global(Vector3(bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y, bounds.position.z + bounds.size.z * 0.5))
	check(bottom_center.is_equal_approx(Vector3(4.0, 0.0, 2.0)),
		"world-plane placement snaps the bottom centre to the half-metre grid")
	placement.cancel()
	check(not placement.active() and world.stage().get_child_count() == initial_children,
		"cancel removes the transient preview")

	check(placement.begin(row, actions.shapes.plan(&"make_box")), "surface placement begins")
	preview = placement.preview()
	world.box().position.y = 0.17
	var surface: Vector3 = world.box().to_global(world.box().call("face_centroid", world.top_face(world.box())))
	motion.position = world.camera().unproject_position(surface)
	placement.handle(world.camera(), motion)
	bounds = preview.call("get_local_aabb")
	bottom_center = preview.to_global(Vector3(bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y, bounds.position.z + bounds.size.z * 0.5))
	check(bottom_center.is_equal_approx(Vector3(1.0, 3.17, 1.0)),
		"surface placement preserves an off-grid support height and ignores its own preview")
	placement.cancel(false)
	world.box().position.y = 0.0

	var name_undo := SlabTestUndo.new()
	var name_actions := PlacementActions.new(name_undo)
	var named_placement := SlabCreatePlacement.new(host, name_actions)
	var stair_row := actions.find("make_stair")
	for expected_name in ["Stair", "Stair2"]:
		check(named_placement.begin(stair_row, actions.shapes.plan(&"make_stair")),
			"repeated Stair placement begins")
		named_placement.call("_place_at", Vector3.ZERO, false)
		var named_preview := named_placement.preview()
		check(named_preview.name == expected_name, "preview receives readable unique name %s" % expected_name)
		check(named_placement.confirm(), "named Stair placement commits")
	check(world.stage().get_node_or_null("Stair") != null and world.stage().get_node_or_null("Stair2") != null,
		"repeated placed shapes keep readable unique names")
	name_undo.undo()
	check(world.stage().get_node_or_null("Stair2") == null, "undo removes the second readable shape")
	name_undo.redo()
	check(world.stage().get_node_or_null("Stair2") != null, "redo restores the same readable unique name")
	world.stage().get_node("Stair").free()
	world.stage().get_node("Stair2").free()

	for entry in actions.shapes.entries():
		var shape_row := actions.find(entry["id"])
		if not check(placement.begin(shape_row, actions.shapes.plan(entry["id"])), "%s placement begins" % entry["label"]):
			continue
		preview = placement.preview()
		motion.position = floor_screen
		placement.handle(world.camera(), motion)
		bounds = preview.call("get_local_aabb")
		bottom_center = preview.to_global(Vector3(bounds.position.x + bounds.size.x * 0.5,
			bounds.position.y, bounds.position.z + bounds.size.z * 0.5))
		check(bottom_center.is_equal_approx(Vector3(4, 0, 2)),
			"%s shares the complete bottom-centre ground anchor" % entry["label"])
		placement.cancel(false)

	var transformed_root := Node3D.new()
	transformed_root.position = Vector3(17, 3, -9)
	transformed_root.rotation.y = 0.4
	root.add_child(transformed_root)
	var transformed_placement := SlabCreatePlacement.new(SlabTestHost.over(transformed_root), actions)
	check(transformed_placement.begin(row, actions.shapes.plan(&"make_box")), "transformed-parent placement begins")
	transformed_placement.call("_place_at", Vector3(4, 0, 2), false)
	preview = transformed_placement.preview()
	bounds = preview.call("get_local_aabb")
	bottom_center = preview.to_global(Vector3(bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y, bounds.position.z + bounds.size.z * 0.5))
	check(bottom_center.is_equal_approx(Vector3(4, 0, 2)),
		"parent-local transform preserves the requested world anchor")
	transformed_placement.cancel(false)
	transformed_root.free()

	check(placement.begin(row, actions.shapes.plan(&"make_box")), "stale-anchor placement begins")
	preview = placement.preview()
	placement.call("_place_at", Vector3(6, 0, 6), false)
	world.camera().look_at_from_position(Vector3(0, 5, 10), Vector3(0, 5, 0), Vector3.UP)
	motion.position = Vector2(640, 360)
	placement.handle(world.camera(), motion)
	check(not preview.visible and not placement.confirm(),
		"an invalid current ray hides the old preview and refuses its stale anchor")
	placement.cancel(false)

	var modal_actions := SlabActions.new(SlabSelection.new())
	var session := SlabViewport.new(host)
	session.bind_actions(modal_actions)
	modal_actions.request_create_placement(&"make_box")
	check(world.stage().get_child_count() == initial_children + 1,
		"panel create request starts one transient viewport preview")
	modal_actions.create_settings_changed.emit()
	check(world.stage().get_child_count() == initial_children,
		"changing shape settings cancels the old geometry preview")
	modal_actions.request_create_placement(&"make_box")
	session.state().request_mode(SlabSelection.Mode.VERTEX)
	check(world.stage().get_child_count() == initial_children,
		"mode change clears the transient creation preview")
	world.tear_down()
	finish()


func check(ok: bool, message: String) -> bool:
	if ok:
		return true
	failures += 1
	push_error("FAIL " + message)
	return false


func finish() -> void:
	print("create_placement_smoke: %d failures" % failures)
	quit(1 if failures else 0)
