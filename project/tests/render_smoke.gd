extends SceneTree

const OUT := "/tmp/arena-slab-kernel/slab-render.png"
var _frames := 0
var _block: Node3D


func _initialize() -> void:
	var world := Node3D.new()
	world.name = "RenderSmoke"
	root.add_child(world)

	var camera := Camera3D.new()
	world.add_child(camera)
	camera.look_at_from_position(Vector3(6, 8, 10), Vector3(1, 1.5, 1), Vector3.UP)
	camera.current = true

	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.look_at_from_position(Vector3(4, 8, 6), Vector3(1, 1, 1), Vector3.UP)

	if not ClassDB.class_exists("SlabSolid"):
		push_error("SlabSolid missing")
		quit(1)
		return
	_block = ClassDB.instantiate("SlabSolid")
	world.add_child(_block)
	_block.call("make_box", Vector3(2, 3, 2))
	_block.call("set_prototype_color", Color(0.25, 0.72, 1.0))
	_block.position = Vector3.ZERO


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	var vp := root.get_viewport()
	if vp == null:
		push_error("no viewport")
		quit(2)
		return true
	var tex := vp.get_texture()
	if tex == null:
		push_error("no viewport texture")
		quit(2)
		return true
	var img := tex.get_image()
	if img == null:
		push_error("no image")
		quit(2)
		return true
	img.save_png(OUT)
	var w := img.get_width()
	var h := img.get_height()
	if w < 8 or h < 8:
		push_error("tiny image %sx%s" % [w, h])
		quit(3)
		return true
	var first := img.get_pixel(0, 0)
	var distinct := 0
	var x := 0
	while x < w:
		var y := 0
		while y < h:
			if img.get_pixel(x, y) != first:
				distinct += 1
			y += 16
		x += 16
	print("render_smoke png=", OUT, " ", w, "x", h, " distinct_from_corner=", distinct)
	if distinct < 8:
		push_error("framebuffer is a flat color")
		quit(4)
		return true
	print("render_smoke ok")
	quit(0)
	return true
