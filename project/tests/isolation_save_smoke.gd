extends SceneTree

const Selection := preload("res://addons/slab/slab_selection.gd")
var failures := 0


func _initialize() -> void:
	var scene := Node3D.new()
	scene.name = "IsolationScene"
	root.add_child(scene)
	var parent := _solid(scene, scene, "Parent")
	var target := _solid(parent, scene, "Target")
	var other := _solid(scene, scene, "Other")
	var hidden := _solid(scene, scene, "IntentionallyHidden")
	hidden.visible = false
	var selection := Selection.new()
	selection.set_objects([target])
	check(selection.enter_isolation(scene), "enter isolation")
	check(target.is_visible_in_tree(), "nested selected solid remains visible")
	check(not parent.get_node("Mesh").visible, "ancestor geometry is hidden")
	check(not other.visible and not hidden.visible, "other solids are hidden")

	# This is the pre-save boundary used by EditorPlugin._apply_changes.
	selection.suspend_isolation_for_save()
	selection.suspend_isolation_for_save()
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "pack isolated scene")
	selection.resume_isolation_after_save()
	selection.resume_isolation_after_save()
	check(selection.isolated and not other.visible, "editor remains isolated after save")
	check(target.is_visible_in_tree(), "selected descendant remains visible after save")
	var reopened := packed.instantiate()
	check(reopened.get_node("Other").visible, "reopen restores original visible solid")
	check(not reopened.get_node("IntentionallyHidden").visible, "reopen preserves intentional hiding")
	check(reopened.get_node("Parent").visible, "reopen preserves ancestor visibility")
	reopened.free()

	selection.exit_isolation()
	check(other.visible and parent.get_node("Mesh").visible, "exit restores editor visibility")
	check(not hidden.visible, "exit keeps intentionally hidden solid hidden")
	selection.enter_isolation(scene)
	selection.suspend_isolation_for_save()
	selection.exit_isolation()
	selection.resume_isolation_after_save()
	check(other.visible and not selection.isolated, "queued resume cannot re-isolate after teardown")
	selection.enter_isolation(scene)
	other.free()
	selection.exit_isolation()
	check(not hidden.visible, "deleted hidden node does not break cleanup")
	_test_uv_targets(selection, parent, target)
	scene.free()
	print("isolation_save_smoke: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _test_uv_targets(selection: Selection, a: Node3D, b: Node3D) -> void:
	selection.set_objects([a])
	selection.mode = Selection.Mode.FACE
	selection.set_ids(PackedInt64Array([1]))
	selection.set_uv_selection(PackedInt64Array([7]))
	selection.set_ids(PackedInt64Array([1]))
	check(selection.uv_selection_count() == 1, "unchanged face target retains UV selection")
	selection.set_ids(PackedInt64Array([2]))
	check(selection.uv_selection_count() == 0, "changing selected faces clears UV selection")
	selection.set_uv_selection(PackedInt64Array([7]))
	selection.set_objects([b])
	check(selection.uv_selection_count() == 0, "changing solids clears UV selection")
	selection.set_uv_selection(PackedInt64Array([7]))
	selection.mode = Selection.Mode.EDGE
	check(selection.uv_selection_count() == 0, "changing modelling mode clears UV selection")


func _solid(parent: Node, owner: Node, label: String) -> Node3D:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.name = label
	parent.add_child(solid)
	solid.owner = owner
	solid.call("make_box", Vector3.ONE)
	return solid


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
