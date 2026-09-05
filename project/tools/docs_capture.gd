extends SceneTree

const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")

const VIEW := Vector2i(1280, 720)
const PANEL_VIEW := Vector2i(1280, 460)

var _out := ""
var _world: Node3D
var _solid: Node3D
var _phase := 0
var _wait := 0


func _initialize() -> void:
	_out = OS.get_environment("SLAB_DOCS_ASSETS")
	if _out == "":
		_out = ProjectSettings.globalize_path("res://").path_join("../website/public/img")
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = VIEW
	DisplayServer.window_set_size(VIEW)
	if not ClassDB.class_exists(SlabSelection.SOLID_CLASS):
		push_error("SlabSolid missing. Build the extension first.")
		quit(1)


func _process(_dt: float) -> bool:
	_wait += 1
	if _phase == 0:
		_stage_box()
		_phase = 1
		_wait = 0
		return false
	if _phase == 1 and _wait >= 6:
		_save("solid-box.png")
		_extrude_top()
		_phase = 2
		_wait = 0
		return false
	if _phase == 2 and _wait >= 6:
		_save("solid-extrude.png")
		_carve_cavity()
		_phase = 3
		_wait = 0
		return false
	if _phase == 3 and _wait >= 6:
		_save("solid-pair.png")
		_stage_panel()
		_phase = 4
		_wait = 0
		return false
	if _phase == 4 and _wait >= 6:
		_save("panel.png")
		print("docs_capture wrote ", _out)
		quit(0)
		return true
	return false


func _stage_box() -> void:
	_clear_root()
	_world = Node3D.new()
	root.add_child(_world)
	_add_camera(_world, Vector3(3.6, 4.8, 6.2), Vector3(1.0, 1.8, 1.0))
	_add_light(_world)
	_solid = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	_world.add_child(_solid)
	_solid.call("make_box", Vector3(2, 3, 2))
	_solid.call("set_prototype_color", Color(0.55, 0.72, 0.95))


func _extrude_top() -> void:
	var top: int = _top_face(_solid)
	_solid.call("extrude_faces", PackedInt64Array([top]), 2.0)


func _carve_cavity() -> void:
	_clear_root()
	_world = Node3D.new()
	root.add_child(_world)
	_add_camera(_world, Vector3(6.5, 5.5, 8.0), Vector3(1.5, 1.5, 1.0))
	_add_light(_world)
	var host: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	_world.add_child(host)
	host.call("make_box", Vector3(2, 3, 2))
	host.call("set_prototype_color", Color(0.55, 0.72, 0.95))
	var cutter: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	_world.add_child(cutter)
	cutter.position = Vector3(3.2, 0, 0)
	cutter.call("make_box", Vector3(1.2, 2.2, 1.2))
	cutter.call("set_prototype_color", Color(0.92, 0.55, 0.28))
	_solid = host


func _stage_panel() -> void:
	_clear_root()
	root.size = PANEL_VIEW
	DisplayServer.window_set_size(PANEL_VIEW)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var selection := SlabSelection.new()
	var actions := SlabActions.new(selection)
	var panel: Control = SlabPanel.new()
	panel.setup(selection, actions, SlabMetrics.at_scale(1.0))
	root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	selection.mode = SlabSelection.Mode.FACE


func _add_camera(world: Node3D, eye: Vector3, look: Vector3) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.18, 0.19, 0.21)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.64)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.look_at_from_position(eye, look, Vector3.UP)
	camera.current = true


func _add_light(world: Node3D) -> void:
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.look_at_from_position(Vector3(4, 8, 6), Vector3(1, 1, 1), Vector3.UP)
	light.shadow_enabled = true


func _top_face(solid: Node3D) -> int:
	var best: int = 0
	var up := -2.0
	for id in PackedInt64Array(solid.call("get_faces")):
		var n: Vector3 = solid.call("face_normal", id)
		if n.y > up:
			up = n.y
			best = id
	return best


func _save(file_name: String) -> void:
	var tex: ViewportTexture = root.get_viewport().get_texture()
	if tex == null:
		push_error("no viewport texture for " + file_name)
		return
	var img: Image = tex.get_image()
	if img == null:
		push_error("no image for " + file_name)
		return
	var path: String = _out.path_join(file_name)
	var err: int = img.save_png(path)
	if err != OK:
		push_error("save_png %s failed %d" % [path, err])
		return
	print("docs_capture ", file_name, " ", img.get_width(), "x", img.get_height())


func _clear_root() -> void:
	for child in root.get_children():
		child.free()
	_world = null
	_solid = null
