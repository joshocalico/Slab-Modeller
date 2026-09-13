extends "res://tests/panel_editor_smoke.gd"

# Captures the saved Signal Foundry roof without editing or saving any resource.
# scripts/godot --editor --path project --script res://tools/paint_docs_capture.gd
const SCENE := "res://demo/signal_foundry/signal_foundry.tscn"
const MATERIAL_OUT := "/tmp/slab-docs-paint-material.png"
const PIXEL_OUT := "/tmp/slab-docs-paint-pixel.png"


func _run() -> void:
	if not Engine.is_editor_hint():
		_fail("Requires --editor")
		return
	var editor := Engine.get_singleton("EditorInterface")
	while editor.get_resource_filesystem().is_scanning() or _plugin(root) == null:
		await process_frame
	await create_timer(1.0).timeout
	editor.open_scene_from_path(SCENE)
	editor.set_main_screen_editor("3D")
	var deadline := Time.get_ticks_msec() + 15000
	while editor.get_edited_scene_root() == null or editor.get_edited_scene_root().scene_file_path != SCENE:
		if Time.get_ticks_msec() > deadline:
			_fail("Signal Foundry did not remain current")
			return
		await process_frame
	var solid := editor.get_edited_scene_root().get_node("MaintenanceBayRoof") as Node3D
	var before_data: PackedByteArray = solid.get("data")
	var before_materials: Array = (solid.get("materials") as Array).duplicate()
	var before_material_ids := _material_ids(before_materials)
	var before_images := _material_images(before_materials)
	var plugin := _plugin(root)
	var history := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(solid))
	var before_version: int = history.get_version()
	editor.get_selection().clear()
	editor.get_selection().add_node(solid)
	editor.edit_node(solid)
	await create_timer(0.3).timeout
	var panel: Control = plugin.get("_panel")
	plugin.call("make_bottom_panel_item_visible", panel)
	var selection: RefCounted = plugin.get("_selection")
	selection.set_objects([solid])
	await _click(_mode(panel, 3))
	var top := 0
	var best_y := -INF
	for face in solid.call("get_faces"):
		var normal: Vector3 = solid.call("face_normal", face)
		var centre: Vector3 = solid.call("face_centroid", face)
		if normal.y > 0.9 and centre.y > best_y:
			best_y = centre.y
			top = face
	selection.set_ids(PackedInt64Array([top]))
	await _click(_button_named(panel, "Surface Paint"))
	await create_timer(0.4).timeout
	_check(panel.get("_paint").selected_uv_loops().size() == 1, "saved roof top face is active in Material/UV")
	await _write_panel(editor, panel, MATERIAL_OUT)
	await _click(_button_named(panel, "Pixel"))
	var inspector_scroll: ScrollContainer = panel.find_child("PaintInspector", true, false)
	var brush: Control = panel.get("_paint_brush")
	inspector_scroll.ensure_control_visible(brush)
	inspector_scroll.scroll_horizontal = 0
	await process_frame
	await process_frame
	await create_timer(0.4).timeout
	var brush_color: Control = panel.find_child("BrushColor", true, false)
	var brush_radius: Control = panel.find_child("brush_radius", true, false)
	var brush_opacity: Control = panel.find_child("brush_opacity", true, false)
	var inspector_rect := inspector_scroll.get_global_rect().grow(1.0)
	_check(brush.is_visible_in_tree() and inspector_rect.encloses(brush_color.get_global_rect())
		and inspector_rect.encloses(brush_radius.get_global_rect())
		and inspector_rect.encloses(brush_opacity.get_global_rect()),
		"Pixel capture shows the saved image with complete brush controls: inspector=%s color=%s radius=%s opacity=%s scroll=%s/%s" % [inspector_rect, brush_color.get_global_rect(), brush_radius.get_global_rect(), brush_opacity.get_global_rect(), inspector_scroll.scroll_vertical, inspector_scroll.get_v_scroll_bar().max_value])
	await _write_panel(editor, panel, PIXEL_OUT)
	_check(solid.get("data") == before_data, "capture preserves exact roof mesh and UV data")
	_check(_material_ids(solid.get("materials")) == before_material_ids
		and solid.get("materials") == before_materials, "capture preserves material slots and identities")
	_check(_material_images(solid.get("materials")) == before_images, "capture preserves exact saved image bytes")
	_check(history.get_version() == before_version, "capture creates no editor history")
	print("SLAB_PAINT_DOCS_CAPTURE ", JSON.stringify({"failures": failures,
		"material": MATERIAL_OUT, "pixel": PIXEL_OUT, "face": top}))
	quit(1 if failures else 0)


func _write_panel(editor: Object, panel: Control, path: String) -> void:
	RenderingServer.force_sync()
	RenderingServer.force_draw(true)
	await process_frame
	var image: Image = editor.get_base_control().get_viewport().get_texture().get_image()
	image = image.get_region(Rect2i(panel.get_global_rect()))
	var result := image.save_png(path)
	_check(result == OK and FileAccess.file_exists(path), "capture writes " + path)


func _material_ids(materials: Array) -> PackedInt64Array:
	var ids := PackedInt64Array()
	for material in materials:
		ids.append(material.get_instance_id() if material is Material else 0)
	return ids


func _material_images(materials: Array) -> Array[PackedByteArray]:
	var images: Array[PackedByteArray] = []
	for material in materials:
		var bytes := PackedByteArray()
		if material is StandardMaterial3D and material.albedo_texture != null:
			var image: Image = material.albedo_texture.get_image()
			if image != null and not image.is_empty():
				bytes = image.save_png_to_buffer()
		images.append(bytes)
	return images
