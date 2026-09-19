extends SceneTree

const DIR := "res://demo/relay_yard/"
var world: Node3D
var architecture: Node3D
var materials: Array[Material] = []
var solids := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("build")

func add(parent: Node, node: Node, label: String) -> Node:
	node.name = label
	parent.add_child(node, true)
	node.owner = world
	return node

func check(code: int, what: String) -> void:
	if code != OK:
		failures.append("%s: mesh error %d" % [what, code])

func finish_solid(node: Node3D, at: Vector3, slot: int) -> Node3D:
	node.position = at
	node.materials = materials
	check(node.set_face_material(node.get_faces(), slot), str(node.name) + " material")
	check(node.set_face_uv(node.get_faces(), Vector2.ONE * 0.65, Vector2.ZERO, 0), str(node.name) + " UV")
	solids += 1
	return node

func box(label: String, size: Vector3, at: Vector3, slot: int) -> Node3D:
	var node: Node3D = ClassDB.instantiate("SlabSolid")
	add(architecture, node, label)
	check(node.make_box(size), label)
	return finish_solid(node, at, slot)

func cylinder(label: String, radius: float, height: float, at: Vector3, slot: int) -> Node3D:
	var node: Node3D = ClassDB.instantiate("SlabSolid")
	add(architecture, node, label)
	check(node.make_cylinder(radius, height, 12), label)
	return finish_solid(node, at, slot)

func arch(label: String, width: float, depth: float, at: Vector3, slot: int) -> Node3D:
	var node: Node3D = ClassDB.instantiate("SlabSolid")
	add(architecture, node, label)
	check(node.make_arch(width, depth, 12, 0.35, PI), label)
	return finish_solid(node, at, slot)

func top_face(node: Node3D) -> int:
	for face in node.get_faces():
		if node.face_normal(face).y > 0.9:
			return face
	return 0

func subtract_box(host: Node3D, size: Vector3, at: Vector3, label: String) -> void:
	var cutter := box("Cut_" + label, size, at, 0)
	check(host.boolean_with(cutter, 1), label)
	architecture.remove_child(cutter)
	cutter.free()
	solids -= 1

func tricky_geometry() -> void:
	# A reflex footprint with two deep notches: useful for concave UV picking.
	var console: Node3D = ClassDB.instantiate("SlabSolid")
	add(architecture, console, "ConcaveControlConsole")
	var footprint := PackedVector3Array([
		Vector3(0,0,0), Vector3(4,0,0), Vector3(4,0,1),
		Vector3(1,0,1), Vector3(1,0,2.4), Vector3(4,0,2.4),
		Vector3(4,0,3.4), Vector3(0,0,3.4)])
	footprint.reverse()
	check(console.make_prism(footprint, 0.9), "C console prism")
	finish_solid(console, Vector3(23,0,13), 4)
	# Three windows cut into the same thin room wall, one oblique opening.
	var room: Node3D = architecture.get_node("Workshop_InsetRoom")
	var window_positions := [4.2, 6.2, 8.2]
	for z in window_positions:
		subtract_box(room, Vector3(1.2,0.85,1.1), Vector3(8.4,1.7,z), "workshop window %.1f" % z)
	var cutter_x := 2.0 if "--knife-edge" in OS.get_cmdline_user_args() else 1.5
	var diagonal := box("ObliqueWindowCutter", Vector3(1.4,0.8,1.4), Vector3(cutter_x,1.9,6), 0)
	diagonal.rotation.y = PI / 4
	check(room.boolean_with(diagonal, 1), "oblique workshop window")
	architecture.remove_child(diagonal)
	diagonal.free()
	solids -= 1
	# Intersecting segmented arches, genuinely united into one solid.
	var vault := arch("CrossVault", 4.0, 1.2, Vector3(2,2.2,16.4), 0)
	var cross := arch("CrossVaultOperand", 4.0, 1.2, Vector3(3.4,2.2,19), 0)
	cross.rotation.y = PI / 2
	check(vault.boolean_with(cross, 0), "cross vault union")
	architecture.remove_child(cross)
	cross.free()
	solids -= 1
	for at in [Vector3(2,0,16.4), Vector3(5.55,0,16.4), Vector3(3.4,0,15), Vector3(3.4,0,18.55)]:
		box("CrossVaultPier", Vector3(0.45,2.3,0.6), at, 1)
	# Sloped thin braces stress projection switching and tiny face selection.
	for z in [12.0,16.0,20.0]:
		var brace := box("SlopingBrace", Vector3(2.7,0.16,0.22), Vector3(24.8,0.7,z), 5)
		brace.rotation.z = deg_to_rad(40)

func sign_text(label: String, text: String, at: Vector3, font: int = 48) -> void:
	var sign := Label3D.new()
	add(world, sign, label)
	sign.position = at
	sign.text = text
	sign.font_size = font
	sign.pixel_size = 0.008
	sign.modulate = Color("e6cfa0")
	sign.outline_modulate = Color("253e3d")
	sign.outline_size = 8

func build() -> void:
	world = Node3D.new()
	world.name = "RelayYard"
	root.add_child(world)
	architecture = add(world, Node3D.new(), "Architecture")
	var names := ["limestone", "brick", "slate", "timber", "teal_steel", "hazard", "uv_grid"]
	for material_name in names:
		var mat := StandardMaterial3D.new()
		mat.resource_name = str(material_name).capitalize()
		mat.albedo_texture = load(DIR + "materials/" + material_name + ".svg")
		mat.roughness = 0.82
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mat.metallic = 0.4 if material_name == "teal_steel" else 0.0
		check(ResourceSaver.save(mat, DIR + "materials/" + material_name + ".tres"), "save material")
		materials.append(mat)
	box("CourtyardFoundation", Vector3(32, 0.5, 28), Vector3(0, -0.5, 0), 2)
	# Outer walls and entrance opening.
	box("NorthWall", Vector3(32, 4.5, 0.5), Vector3(0, 0, 0), 1)
	box("WestWall", Vector3(0.5, 4.5, 26), Vector3(0, 0, 0), 0)
	box("EastWall", Vector3(0.5, 5, 26), Vector3(31.5, 0, 0), 0)
	box("SouthWallLeft", Vector3(14, 3, 0.5), Vector3(0, 0, 25.5), 1)
	box("SouthWallRight", Vector3(14, 3, 0.5), Vector3(18, 0, 25.5), 1)
	box("ExitGate", Vector3(4, 2.8, 0.3), Vector3(14, 0, 25.55), 4)
	arch("ExitArch", 4.7, 0.65, Vector3(13.65, 2.5, 25.4), 0)
	for x in [2.0, 9.0, 16.0, 23.0, 30.0]:
		box("NorthButtress", Vector3(0.6, 5, 1.0), Vector3(x, 0, 0.4), 0)
		box("NorthCap", Vector3(0.95, 0.25, 1.2), Vector3(x - 0.175, 5, 0.3), 2)
	# True inset/extrude room, followed by a Boolean door through the front wall.
	var workshop := box("Workshop_InsetRoom", Vector3(7, 3.5, 7), Vector3(2, 0, 3), 1)
	var top := PackedInt64Array([top_face(workshop)])
	check(workshop.inset_faces(top, 0.35), "workshop inset")
	check(workshop.extrude_faces(top, -3.15), "workshop hollow")
	var cutter := box("TemporaryDoorCutter", Vector3(2, 2.6, 1.2), Vector3(4.5, 0.3, 9.1), 0)
	check(workshop.boolean_with(cutter, 1), "workshop door subtract")
	architecture.remove_child(cutter)
	cutter.free()
	solids -= 1
	for face in workshop.get_faces():
		if workshop.face_normal(face).y > 0.9:
			check(workshop.set_face_material(PackedInt64Array([face]), 2), "workshop floor")
	arch("WorkshopDoorArch", 2.7, 0.45, Vector3(4.15, 2.4, 9.7), 0)
	box("WorkshopDoorLeft", Vector3(0.35, 2.5, 0.5), Vector3(4.15, 0, 9.6), 0)
	box("WorkshopDoorRight", Vector3(0.35, 2.5, 0.5), Vector3(6.5, 0, 9.6), 0)
	# Low ramp at the room threshold keeps entry comfortably traversable.
	var ramp: Node3D = ClassDB.instantiate("SlabSolid")
	add(architecture, ramp, "WorkshopThresholdSteps")
	check(ramp.make_stair(Vector3(1.0, 0.35, 2.0), 2), "threshold")
	finish_solid(ramp, Vector3(4.5, 0, 10.8), 2)
	ramp.rotation.y = PI / 2
	# Elevated gallery reached by a long, readable stair run.
	var stairs: Node3D = ClassDB.instantiate("SlabSolid")
	add(architecture, stairs, "GalleryStair")
	check(stairs.make_stair(Vector3(9, 3.2, 3), 16), "gallery stairs")
	finish_solid(stairs, Vector3(13, 0, 4), 0)
	for face in stairs.get_faces():
		if stairs.face_normal(face).y > 0.9:
			check(stairs.set_face_material(PackedInt64Array([face]), 2), "stair treads")
	box("GalleryDeck", Vector3(8.5, 0.4, 8), Vector3(22, 2.8, 3), 3)
	box("LookoutWalkway", Vector3(3.2, 0.35, 9), Vector3(26, 2.85, 11), 3)
	box("LookoutDeck", Vector3(6, 0.45, 4), Vector3(23, 2.75, 19), 0)
	for x in [22.3, 29.7]:
		for z in [3.2, 10.3]:
			box("GalleryColumn", Vector3(0.5, 2.8, 0.5), Vector3(x, 0, z), 1)
	for z in [13.0, 17.0, 21.0]:
		box("WalkwaySupport", Vector3(0.5, 2.85, 0.5), Vector3(27, 0, z), 4)
	# Railings give parallax and directional texture tests.
	for z in [3.05, 10.8]:
		if z < 4:
			box("GalleryRail", Vector3(8.5, 0.14, 0.14), Vector3(22, 4.15, z), 4)
		else:
			box("GalleryRail", Vector3(4, 0.14, 0.14), Vector3(22, 4.15, z), 4)
			box("GalleryRail", Vector3(1.3, 0.14, 0.14), Vector3(29.2, 4.15, z), 4)
		for x in [22.2, 24.2, 26.2, 28.2, 30.2]:
			if z > 10 and x > 26 and x < 29.2:
				continue
			box("GalleryRailPost", Vector3(0.10, 1.0, 0.10), Vector3(x, 3.2, z), 4)
	for x in [26.0, 29.05]:
		box("WalkwayRail", Vector3(0.12, 0.12, 8), Vector3(x, 4.1, 11), 4)
		for z in [12.0, 15.0, 18.0]:
			box("WalkwayPost", Vector3(0.10, 1, 0.10), Vector3(x, 3.2, z), 4)
	# Courtyard machinery, arches, benches and a paint-test panel.
	for at in [Vector3(12, 0, 14), Vector3(20, 0, 15)]:
		box("MachinePlinth", Vector3(2.8, 0.3, 2.8), at - Vector3(0.4, 0, 0.4), 2)
		cylinder("RelayTank", 0.9, 2.4, at + Vector3(0, 0.3, 0), 4)
		cylinder("TankCollar", 1.0, 0.16, at + Vector3(0, 2.5, 0), 5)
	for z in [14.0, 20.0]:
		arch("WestArcade", 4, 0.55, Vector3(2, 2.2, z), 0)
		for x in [2.0, 5.55]:
			box("ArcadePier", Vector3(0.45, 2.3, 0.55), Vector3(x, 0, z), 1)
		box("BenchSeat", Vector3(2.4, 0.18, 0.65), Vector3(2.8, 0.8, z - 1), 3)
	for x in [10.0, 19.0]:
		box("RouteMarker", Vector3(0.35, 0.02, 7), Vector3(x, 0.01, 17), 5)
	var board := box("PainterTestBoard", Vector3(4, 2.2, 0.25), Vector3(10, 0.7, 1.2), 6)
	check(board.set_face_uv(board.get_faces(), Vector2(0.25, 0.5), Vector2.ZERO, 0), "test board UV")
	for i in range(6):
		var crate := box("TimberCrate", Vector3(0.9, 0.9, 0.9), Vector3(3 + (i % 3) * 1.0, 0.35 + (i / 3) * 0.9, 3.7), 3)
		crate.rotation.y = 0.06 * i
	tricky_geometry()
	sign_text("YardTitle", "RELAY YARD", Vector3(16, 3.8, 0.8), 80)
	sign_text("WorkshopSign", "01 / WORKSHOP", Vector3(5.5, 3.25, 10.3), 38)
	sign_text("GallerySign", "02 / GALLERY  →", Vector3(18, 1.5, 7.2), 42)
	sign_text("LookoutSign", "03 / LOOKOUT", Vector3(26, 4.1, 21), 38)
	sign_text("PainterSign", "SURFACE LAB / UV + PAINT", Vector3(12, 3.3, 1.5), 30)
	var relay_group := add(world, Node3D.new(), "Relays")
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("f8c35d")
	glow.emission_enabled = true
	glow.emission = Color("ffbd55")
	glow.emission_energy_multiplier = 2.5
	for at in [Vector3(7, 1.1, 6), Vector3(28, 4.0, 7), Vector3(26, 4.0, 21)]:
		var relay: Node3D = ClassDB.instantiate("SlabSolid")
		add(relay_group, relay, "RelayCell")
		check(relay.make_cylinder(0.22, 0.55, 6), "relay")
		relay.position = at
		relay.materials = [glow]
		relay.collision_enabled = false
	var env := WorldEnvironment.new()
	add(world, env, "WorldEnvironment")
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("a6b9b7")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c1d2d0")
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sun := DirectionalLight3D.new()
	add(world, sun, "Sun")
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color("ffe0ab")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	var player := CharacterBody3D.new()
	add(world, player, "Player")
	player.position = Vector3(16, 0.15, 21)
	player.set_script(load(DIR + "player.gd"))
	var shape := CollisionShape3D.new()
	add(player, shape, "CollisionShape3D")
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.3
	shape.shape.height = 1.7
	shape.position.y = 0.85
	var camera := Camera3D.new()
	add(player, camera, "Camera3D")
	camera.position = Vector3(0, 1.55, 0)
	camera.fov = 78
	camera.current = true
	world.set_script(load(DIR + "yard_game.gd"))
	var scene := PackedScene.new()
	check(scene.pack(world), "pack scene")
	if failures.is_empty():
		check(ResourceSaver.save(scene, DIR + "relay_yard.tscn"), "save scene")
	print("RELAY_YARD solids=%d materials=%d failures=%s" % [solids + 3, materials.size(), failures])
	quit(0 if failures.is_empty() else 1)
