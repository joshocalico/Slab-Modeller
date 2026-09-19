extends SceneTree
func _initialize() -> void:
	var scene: PackedScene = load("res://demo/relay_yard/paint_acceptance.tscn")
	var yard := scene.instantiate()
	root.add_child(yard)
	var wall = yard.get_node("Architecture/WestWall")
	var found := false
	for i in wall.materials.size():
		var mat: Material = wall.materials[i]
		if not mat is StandardMaterial3D or not mat.has_meta("slab_paint_png"):
			continue
		var img: Image = mat.albedo_texture.get_image()
		if img.is_compressed():
			img.decompress()
		var red := 0
		for y in img.get_height():
			for x in img.get_width():
				var color := img.get_pixel(x,y)
				if color.r > 0.6 and color.r > color.g * 2.0 and color.r > color.b * 2.0:
					red += 1
		var faces := 0
		for face in wall.get_faces():
			if wall.face_uv(face).slot == i:
				faces += 1
		print("SAVED_PAINT slot=%d red_pixels=%d assigned_faces=%d" % [i,red,faces])
		found = found or (red > 50 and faces > 0)
	print("SAVED_PAINT fresh_scene_reload=", found)
	quit(0 if found else 1)
