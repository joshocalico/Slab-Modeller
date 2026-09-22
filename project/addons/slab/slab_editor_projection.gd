@tool
extends Node

# Camera Preview attaches a scene camera's RID to an editor SubViewport without
# reparenting the Camera3D. Its projection methods still use the scene viewport's
# dimensions. Keep a non-rendering camera in the input viewport's coordinate space.
var _views: Dictionary = {}


static func input_view(source: Camera3D, views: Array, hovered: Control, focused: Control) -> SubViewport:
	for view: SubViewport in views:
		if view != null and source.get_viewport() == view:
			return view
	for control in [hovered, focused]:
		if control == null:
			continue
		for view: SubViewport in views:
			if view == null:
				continue
			# Godot's input surface and SubViewportContainer are siblings.
			var surface_root := view.get_parent().get_parent()
			if surface_root == control or surface_root.is_ancestor_of(control):
				return view
	return null


func camera_for(source: Camera3D, view: SubViewport) -> Camera3D:
	if source.get_viewport() == view:
		return source
	var id := view.get_instance_id()
	if not _views.has(id):
		var projection_view := SubViewport.new()
		projection_view.name = "PaintProjectionViewport"
		projection_view.disable_3d = true
		projection_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(projection_view)
		var camera := Camera3D.new()
		projection_view.add_child(camera)
		_views[id] = {"viewport": projection_view, "camera": camera}
	var entry: Dictionary = _views[id]
	entry.source = weakref(source)
	entry.target = weakref(view)
	var proxy_view: SubViewport = entry.viewport
	var proxy: Camera3D = entry.camera
	proxy_view.size = view.size
	proxy.global_transform = source.global_transform
	proxy.projection = source.projection
	proxy.keep_aspect = source.keep_aspect
	proxy.fov = source.fov
	proxy.size = source.size
	proxy.near = source.near
	proxy.far = source.far
	proxy.frustum_offset = source.frustum_offset
	proxy.h_offset = source.h_offset
	proxy.v_offset = source.v_offset
	return proxy


func refresh_camera(camera: Camera3D) -> Camera3D:
	for entry: Dictionary in _views.values():
		if entry.camera != camera:
			continue
		var source: Camera3D = entry.source.get_ref()
		var view: SubViewport = entry.target.get_ref()
		if source == null or view == null:
			return null
		return camera_for(source, view)
	return camera
