extends SceneTree

const ConstructionPanel := preload("res://addons/slab/slab_construction_panel.gd")
const Selection := preload("res://addons/slab/slab_selection.gd")
const Actions := preload("res://addons/slab/slab_actions.gd")
const Construction := preload("res://addons/slab/slab_construction.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", message)

func _button(parent: Node, label: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text == label: return child
		var found := _button(child, label)
		if found != null: return found
	return null

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	scene.add_child(solid)
	solid.call("make_box", Vector3(4, 4, 4))
	var cutter: Node3D = ClassDB.instantiate("SlabSolid")
	scene.add_child(cutter)
	cutter.call("make_box", Vector3(1, 1, 1))
	cutter.position = Vector3(1, 0, 1)
	var selection := Selection.new()
	selection.solid = solid
	var actions := Actions.new(selection)
	actions.bevel_amount = 0.1
	var undo := UndoRedo.new()
	var panel := ConstructionPanel.new()
	panel.setup(selection, actions, func(): return scene)
	panel.bind_undo(undo)
	root.add_child(panel)
	await process_frame
	_button(panel, "Construction").button_pressed = true
	await process_frame
	var before: PackedByteArray = solid.get("data")
	_button(panel, "Keep mesh · Start history").pressed.emit()
	await process_frame
	check(solid.has_meta(Construction.RECIPE_META) and solid.get("data") == before, "Start history UI preserves selected mesh")
	_button(panel, "Bevel minimum-corner X edge").pressed.emit()
	await process_frame
	check(solid.get_meta(Construction.RECIPE_META).steps.size() == 2 and solid.get("data") != before, "Add Bevel UI evaluates actual geometry")
	undo.undo()
	await process_frame
	check(solid.get("data") == before and solid.get_meta(Construction.RECIPE_META).steps.size() == 1, "UI addition Undo restores recipe and geometry")
	_button(panel, "Add Boolean").pressed.emit()
	await process_frame
	check(cutter.has_meta(Construction.UUID_META) and solid.get_meta(Construction.RECIPE_META).steps.size() == 2,
		"Boolean UI binds scene operand and appends recipe")
	undo.undo()
	await process_frame
	check(not cutter.has_meta(Construction.UUID_META) and solid.get_meta(Construction.RECIPE_META).steps.size() == 1,
		"Boolean Undo also removes newly allocated operand identity")
	_button(panel, "Add Linear Array").pressed.emit()
	await process_frame
	check(solid.get_child_count() == 2, "Array UI creates separate generated solids")
	undo.undo()
	await process_frame
	check(solid.get_child_count() == 0, "Array UI Undo removes outputs")
	undo.undo()
	await process_frame
	_button(panel, "Replace with Box").pressed.emit()
	await process_frame
	check(solid.get_meta(Construction.RECIPE_META).steps[0].parameters.method == &"make_box", "Replace primitive UI creates editable primitive source")
	undo.clear_history()
	panel.free()
	undo.free()
	scene.free()
	print("CONSTRUCTION_PANEL_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
