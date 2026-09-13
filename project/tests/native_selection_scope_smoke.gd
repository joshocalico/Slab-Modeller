extends SceneTree

const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var solid := ClassDB.instantiate("SlabSolid") as Node3D
	stage.add_child(solid)
	_check(solid.call("make_box", Vector3(2, 2, 2)) == OK, "fixture_box")
	await process_frame
	var mesh: Node = solid.get_node_or_null("Mesh")
	_check(mesh != null and not solid.get_children().has(mesh), "generated_mesh_is_internal")
	var light := OmniLight3D.new()
	solid.add_child(light)
	_check(solid.get_children().has(light), "authored_light_is_not_internal")

	var selection := SlabSelection.new()
	selection.set_editor_objects([solid])
	selection.mode = SlabSelection.Mode.FACE
	var face: int = solid.call("get_faces")[0]
	selection.set_ids(PackedInt64Array([face]))
	_check(selection.solid == solid and selection.ids == PackedInt64Array([face]), "direct_solid_selection")

	selection.set_editor_objects([mesh])
	_check(selection.solid == solid and selection.ids == PackedInt64Array([face]), "generated_mesh_keeps_solid_target")
	var before: PackedByteArray = solid.get("data")
	selection.set_editor_objects([light])
	_check(selection.solid == null and selection.ids.is_empty(), "authored_light_clears_stale_solid_and_faces")
	var actions := SlabActions.new(selection)
	actions.run("subdivide_faces")
	_check(solid.get("data") == before, "command_cannot_edit_stale_solid_after_light_selection")

	selection.set_editor_objects([solid])
	selection.set_ids(PackedInt64Array([face]))
	_check(selection.solid == solid and selection.ids == PackedInt64Array([face]), "direct_solid_selection_recovers")
	selection.set_editor_objects([mesh])
	_check(selection.solid == solid, "generated_mesh_selection_recovers")
	actions.run("subdivide_faces")
	_check(solid.get("data") != before, "subdivide_works_after_selecting_the_solid_again")
	print("native_selection_scope_smoke failures=", failures)
	stage.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	failures += 1
	push_error(label)
