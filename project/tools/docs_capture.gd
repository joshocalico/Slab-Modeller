extends SceneTree

const SlabPanel := preload("res://addons/slab/slab_panel.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")
const SlabActions := preload("res://addons/slab/slab_actions.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")

const VIEW := Vector2i(1280, 720)
const PANEL_VIEW := Vector2i(1280, 460)
const ROOM := Vector3(4, 3, 4)
const INSET := 0.45
const INWARD := -2.4

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
		_stage_room()
		_phase = 1
		_wait = 0
		return false
	if _wait < 8:
		return false
	if _phase == 1:
		_save("solid-box.png")
		_inset_top()
		_phase = 2
		_wait = 0
		return false
	if _phase == 2:
		_save("solid-inset.png")
		_extrude_in()
		_phase = 3
		_wait = 0
		return false
	if _phase == 3:
		_save("solid-room.png")
		_stage_extrude_demo()
		_phase = 4
		_wait = 0
		return false
	if _phase == 4:
		_save("solid-extrude.png")
		_stage_pair()
		_phase = 5
		_wait = 0
		return false
	if _phase == 5:
		_save("solid-pair.png")
		_stage_panel()
		_phase = 6
		_wait = 0
		return false
	if _phase == 6:
		_save("panel.png")
		print("docs_capture wrote ", _out)
		quit(0)
		return true
	return false


func _stage_room() -> void:
	_clear_root()
	_world = Node3D.new()
	root.add_child(_world)
	_add_camera(_world, Vector3(5.6, 5.8, 6.4), Vector3(2.0, 2.2, 2.0), 0.22)
	_add_lights(_world)
	_solid = _make_solid(ROOM, Color(0.62, 0.78, 0.98))
	_overlay_wires(_solid)


func _inset_top() -> void:
	var top: int = _top_face(_solid)
	var err: int = _solid.call("inset_faces", PackedInt64Array([top]), INSET)
	print("docs_capture inset ", err, " faces=", _solid.call("face_count"))
	_clear_overlays()
	_overlay_wires(_solid)
	_overlay_face(_solid, _top_face(_solid))


func _extrude_in() -> void:
	var inner: int = _top_face(_solid)
	var err: int = _solid.call("extrude_faces", PackedInt64Array([inner]), INWARD)
	print("docs_capture inward ", err, " faces=", _solid.call("face_count"))
	print("docs_capture floor ", _solid.call("face_centroid", _top_face(_solid)))
	_clear_overlays()
	_aim(Vector3(5.8, 5.2, 6.6), Vector3(2.0, 0.7, 2.0))
	_overlay_wires(_solid)


func _stage_extrude_demo() -> void:
	_clear_root()
	_world = Node3D.new()
	root.add_child(_world)
	_add_camera(_world, Vector3(3.6, 4.8, 6.2), Vector3(1.0, 1.8, 1.0), 0.35)
	_add_lights(_world)
	_solid = _make_solid(Vector3(2, 3, 2), Color(0.55, 0.72, 0.95))
	var top: int = _top_face(_solid)
	_solid.call("extrude_faces", PackedInt64Array([top]), 2.0)


func _stage_pair() -> void:
	_clear_root()
	_world = Node3D.new()
	root.add_child(_world)
	_add_camera(_world, Vector3(6.5, 5.5, 8.0), Vector3(1.5, 1.5, 1.0), 0.35)
	_add_lights(_world)
	_make_solid(Vector3(2, 3, 2), Color(0.55, 0.72, 0.95))
	var cutter: Node3D = _make_solid(Vector3(1.2, 2.2, 1.2), Color(0.92, 0.55, 0.28))
	cutter.position = Vector3(3.2, 0, 0)


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


func _make_solid(size: Vector3, color: Color) -> Node3D:
	var solid: Node3D = ClassDB.instantiate(SlabSelection.SOLID_CLASS)
	_world.add_child(solid)
	solid.call("make_box", size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.48
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.metallic = 0.0
	solid.set("material", mat)
	return solid


func _aim(eye: Vector3, look: Vector3) -> void:
	for child in _world.get_children():
		if child is Camera3D:
			child.look_at_from_position(eye, look, Vector3.UP)
			return


func _add_camera(world: Node3D, eye: Vector3, look: Vector3, ambient: float) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.18, 0.19, 0.21)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.ambient_light_energy = ambient
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 46.0
	camera.look_at_from_position(eye, look, Vector3.UP)
	camera.current = true


func _add_lights(world: Node3D) -> void:
	var key := DirectionalLight3D.new()
	world.add_child(key)
	key.light_energy = 1.35
	key.look_at_from_position(Vector3(8, 12, 3), Vector3(2, 0, 2), Vector3.UP)
	key.shadow_enabled = true
	var fill := DirectionalLight3D.new()
	world.add_child(fill)
	fill.light_energy = 0.28
	fill.look_at_from_position(Vector3(-3, 5, 7), Vector3(2, 1, 2), Vector3.UP)


func _overlay_wires(solid: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for edge in PackedInt64Array(solid.call("get_edges")):
		var ends: PackedVector3Array = solid.call("edge_endpoints", edge)
		st.add_vertex(ends[0])
		st.add_vertex(ends[1])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.93, 0.88, 0.72)
	mat.no_depth_test = true
	mat.render_priority = 1
	var mi := MeshInstance3D.new()
	mi.name = "DocsWires"
	mi.mesh = st.commit()
	mi.material_override = mat
	_world.add_child(mi)


func _overlay_face(solid: Node3D, face: int) -> void:
	var corners: PackedVector3Array = solid.call("face_corners", face)
	print("docs_capture highlight corners=", corners.size())
	if corners.size() < 3:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in corners.size():
		st.add_vertex(corners[i])
		st.add_vertex(corners[(i + 1) % corners.size()])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.62, 0.18)
	mat.no_depth_test = true
	mat.render_priority = 2
	var mi := MeshInstance3D.new()
	mi.name = "DocsFace"
	mi.mesh = st.commit()
	mi.material_override = mat
	_world.add_child(mi)


func _clear_overlays() -> void:
	if _world == null:
		return
	for child in _world.get_children():
		if child.name == "DocsWires" or child.name == "DocsFace":
			child.free()


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
