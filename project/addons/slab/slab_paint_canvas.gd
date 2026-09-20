@tool
extends Control

const SlabPaintUv := preload("res://addons/slab/slab_paint_uv.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")
const SlabUVPick := preload("res://addons/slab/slab_uv_pick.gd")
const SlabSelection := preload("res://addons/slab/slab_selection.gd")

signal painted_pixel(pixel: Vector2)
signal uv_dragged(delta: Vector2, mode: int)
signal stroke_started
signal stroke_ended
signal stroke_cancelled
signal uv_element_picked(element_id: int, additive: bool)

const ZOOM_MIN := 0.25
const ZOOM_MAX := 8.0
const MAX_VISIBLE_TILES := 256
const UV_SCALE_MIN := 1.0e-9
const UV_SCALE_MAX := 1.0e12
const UV_MODIFIER_DRAG_PIXELS := 180.0

var _paint: RefCounted
var _metrics: RefCounted
var _selection: RefCounted
var _brush := Vector2(-1, -1)
var _uv_element_mode: bool = false
var _dragging := false
var _panning := false
var _uv_from := Vector2.ZERO
var _uv_drag_from := Vector2.ZERO
var _zoom: float = 1.0
var _pan := Vector2.ZERO
var _pan_from := Vector2.ZERO
var _pan_origin := Vector2.ZERO
var _uv_center := Vector2(0.5, 0.5)
var _uv_pixels_per_unit: float = 100.0
var _uv_pan := Vector2.ZERO
var _uv_signature: Array = []
var show_pixel_uv: bool = false:
	set(value):
		show_pixel_uv = value
		queue_redraw()


func setup(paint: RefCounted, metrics: RefCounted = null, selection: RefCounted = null) -> void:
	_paint = paint
	_metrics = metrics if metrics != null else SlabMetrics.at_scale(1.0)
	_selection = selection
	name = "PaintCanvas"
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(_metrics.px(160.0), _metrics.px(100.0))
	focus_mode = Control.FOCUS_CLICK
	if _paint != null and _paint.has_signal("image_changed"):
		if not _paint.image_changed.is_connected(queue_redraw):
			_paint.image_changed.connect(queue_redraw)
	if _paint != null and _paint.has_signal("changed"):
		if not _paint.changed.is_connected(_paint_changed):
			_paint.changed.connect(_paint_changed)
	if _selection != null and _selection.has_signal("uv_mode_changed"):
		if not _selection.uv_mode_changed.is_connected(queue_redraw):
			_selection.uv_mode_changed.connect(queue_redraw)
	if _selection != null and _selection.has_signal("uv_selection_changed"):
		if not _selection.uv_selection_changed.is_connected(queue_redraw):
			_selection.uv_selection_changed.connect(queue_redraw)


func bind_selection(selection: RefCounted) -> void:
	_selection = selection
	if _selection != null and _selection.has_signal("uv_mode_changed"):
		if not _selection.uv_mode_changed.is_connected(queue_redraw):
			_selection.uv_mode_changed.connect(queue_redraw)
	if _selection != null and _selection.has_signal("uv_selection_changed"):
		if not _selection.uv_selection_changed.is_connected(queue_redraw):
			_selection.uv_selection_changed.connect(queue_redraw)


func set_uv_element_mode(enabled: bool) -> void:
	_uv_element_mode = enabled
	queue_redraw()


func is_uv_element_mode() -> bool:
	return _uv_element_mode


func _paint_changed() -> void:
	if not _paint.stroke_active and not _paint.uv_drag_active:
		_dragging = false
	var signature := _mapping_signature()
	if signature != _uv_signature:
		_uv_signature = signature
		frame_uv.call_deferred()
	queue_redraw()


func frame_uv() -> void:
	if _paint == null or _paint.is_pixel():
		_zoom = 1.0
		_pan = Vector2.ZERO
		queue_redraw()
		return
	var loops: Array = _paint.selected_uv_loops()
	if loops.is_empty() or size.x < 2.0 or size.y < 2.0:
		return
	var bounds := _uv_loops_bounds(loops)
	# Fit actual extents, including islands much smaller than a texture tile.
	# A collapsed line uses its remaining dimension; a point gets a one-tile view.
	var fit_x := size.x / bounds.size.x if bounds.size.x > 0.0 else INF
	var fit_y := size.y / bounds.size.y if bounds.size.y > 0.0 else INF
	var fit := minf(fit_x, fit_y)
	if not is_finite(fit):
		fit = minf(size.x, size.y)
	_uv_center = bounds.get_center()
	_uv_pixels_per_unit = clampf(fit * 0.82, UV_SCALE_MIN, UV_SCALE_MAX)
	_uv_pan = Vector2.ZERO
	queue_redraw()


func image_rect() -> Rect2:
	var img: Image = _paint.image() if _paint != null else null
	if img == null or img.is_empty():
		return Rect2()
	var img_size := Vector2(img.get_width(), img.get_height())
	var fit: float = minf(size.x / img_size.x, size.y / img_size.y)
	var drawn: Vector2 = img_size * fit * _zoom
	var origin: Vector2 = (size - drawn) * 0.5 + _pan
	return Rect2(origin, drawn)


func pixel_scale() -> float:
	var img: Image = _paint.image() if _paint != null else null
	if img == null or img.is_empty():
		return 1.0
	return image_rect().size.x / float(img.get_width())


func canvas_to_pixel(pos: Vector2) -> Vector2:
	return _canvas_to_pixel(pos)


func hits_image(pos: Vector2) -> bool:
	if _paint != null and not _paint.is_pixel():
		return Rect2(Vector2.ZERO, size).has_point(pos)
	var fitted := image_rect()
	return fitted.size.x > 1.0 and fitted.size.y > 1.0 and fitted.has_point(pos)


func _gui_input(event: InputEvent) -> void:
	if _paint == null or not _paint.active:
		return
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		cancel()
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.12)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.12)
			accept_event()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			_panning = true
			_pan_from = event.position
			_pan_origin = _pan if _paint.is_pixel() else _uv_pan
		else:
			_panning = false
		accept_event()
		return
	if event is InputEventMouseMotion:
		if hits_image(event.position) and _paint.is_pixel():
			_brush = event.position
		else:
			_brush = Vector2(-1, -1)
		queue_redraw()
		if _panning:
			if _paint.is_pixel():
				_pan = _pan_origin + (event.position - _pan_from)
			else:
				_uv_pan = _pan_origin + (event.position - _pan_from)
			queue_redraw()
			accept_event()
			return
		if _dragging and _paint.is_pixel():
			if hits_image(event.position):
				painted_pixel.emit(_canvas_to_pixel(event.position))
			accept_event()
		elif _dragging and not _paint.is_pixel():
			if hits_image(event.position):
				var mode: int = _paint.uv_mode_for(event)
				# Move follows UV coordinates. Modifier sensitivity uses logical screen
				# distance so fitting or zooming the canvas cannot change it.
				var delta: Vector2 = _canvas_to_uv(event.position) - _uv_from
				if mode != _paint.UV_MOVE:
					delta = (event.position - _uv_drag_from) / _metrics.px(UV_MODIFIER_DRAG_PIXELS)
				uv_dragged.emit(delta, mode)
			accept_event()
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		if not hits_image(event.position):
			accept_event()
			return
		if is_uv_element_mode() and not _paint.is_pixel():
			var hit := _pick_uv_at(event.position)
			if not hit.is_empty():
				var additive: bool = event.shift_pressed
				uv_element_picked.emit(int(hit.get("id", 0)), additive)
			accept_event()
			return
		_dragging = true
		if _paint.is_pixel():
			_brush = event.position
			queue_redraw()
			stroke_started.emit()
			painted_pixel.emit(_canvas_to_pixel(event.position))
		else:
			_uv_from = _canvas_to_uv(event.position)
			_uv_drag_from = event.position
			_paint.begin_uv_drag()
		accept_event()
	else:
		var was_dragging := _dragging
		_dragging = false
		if was_dragging and _paint.is_pixel():
			stroke_ended.emit()
		elif was_dragging:
			_paint.end_uv_drag()
		accept_event()


func cancel() -> void:
	if _dragging:
		_dragging = false
		stroke_cancelled.emit()
		_paint.cancel_uv_drag()
	_panning = false


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.12, 0.12, 0.12))
	if _paint != null and not _paint.is_pixel():
		_draw_uv_workspace()
		return
	var fitted := image_rect()
	if fitted.size.x <= 1.0 or fitted.size.y <= 1.0:
		return
	_draw_checker(fitted)
	var tex: Texture2D = _paint.texture() if _paint != null else null
	if tex != null:
		draw_texture_rect(tex, fitted, false)
	var uvs: PackedVector2Array = _paint.selected_uvs() if _paint != null else PackedVector2Array()
	if show_pixel_uv and uvs.size() >= 2:
		var color := Color(0.95, 0.82, 0.28)
		if SlabPaintUv.crosses_wrap(uvs):
			color = Color(0.95, 0.45, 0.2)
		for loop in SlabPaintUv.tiled_loops(uvs):
			if loop.size() < 2:
				continue
			var pts := PackedVector2Array()
			for uv in loop:
				pts.append(_uv_to_canvas(uv))
			pts.append(pts[0])
			draw_polyline(pts, color, 2.0, true)
	if _brush.x >= 0.0 and _paint != null and _paint.is_pixel():
		draw_arc(_brush, _paint.brush_radius * pixel_scale(), 0.0, TAU, 32, Color(1, 1, 1, 0.85), 1.5)


func _draw_uv_workspace() -> void:
	var tex: Texture2D = _paint.texture()
	var a := _canvas_to_uv(Vector2.ZERO)
	var b := _canvas_to_uv(size)
	var x0 := int(floor(minf(a.x, b.x)))
	var x1 := int(ceil(maxf(a.x, b.x)))
	var y0 := int(floor(minf(a.y, b.y)))
	var y1 := int(ceil(maxf(a.y, b.y)))
	_draw_checker(Rect2(Vector2.ZERO, size))
	if tex != null and tex.get_width() > 0 and tex.get_height() > 0:
		var texture_size := Vector2(tex.get_width(), tex.get_height())
		draw_set_transform(_uv_to_canvas(Vector2.ZERO), 0.0,
			Vector2(_uv_pixels_per_unit / texture_size.x, _uv_pixels_per_unit / texture_size.y))
		draw_texture_rect(tex, Rect2(Vector2(x0, y0) * texture_size,
			Vector2(x1 - x0, y1 - y0) * texture_size), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var count := 0
	for y in range(y0, mini(y1, y0 + MAX_VISIBLE_TILES)):
		for x in range(x0, mini(x1, x0 + MAX_VISIBLE_TILES)):
			if count >= MAX_VISIBLE_TILES:
				break
			var tile := Rect2(_uv_to_canvas(Vector2(x, y)), Vector2(_uv_pixels_per_unit, _uv_pixels_per_unit))
			draw_rect(tile, Color(0.45, 0.45, 0.45, 0.7), false, 1.0)
			count += 1
		if count >= MAX_VISIBLE_TILES:
			break
	for uvs: PackedVector2Array in _paint.selected_uv_loops():
		if uvs.size() < 2:
			continue
		var pts := PackedVector2Array()
		for uv in uvs:
			pts.append(_uv_to_canvas(uv))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.95, 0.82, 0.28), 2.0, true)
	_draw_uv_element_selection()


func _draw_checker(fitted: Rect2) -> void:
	fitted = fitted.intersection(Rect2(Vector2.ZERO, size))
	if fitted.size.x <= 0.0 or fitted.size.y <= 0.0:
		return
	var cell: float = maxf(8.0, _metrics.px(8.0))
	var x0: int = int(floor(fitted.position.x / cell))
	var y0: int = int(floor(fitted.position.y / cell))
	var x1: int = int(ceil(fitted.end.x / cell))
	var y1: int = int(ceil(fitted.end.y / cell))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if (x + y) % 2 != 0:
				continue
			var cell_rect := Rect2(Vector2(x, y) * cell, Vector2(cell, cell)).intersection(fitted)
			if cell_rect.size.x > 0.0 and cell_rect.size.y > 0.0:
				draw_rect(cell_rect, Color(0.18, 0.18, 0.18))


func _uv_to_canvas(uv: Vector2) -> Vector2:
	if _paint != null and not _paint.is_pixel():
		return (uv - _uv_center) * _uv_pixels_per_unit + size * 0.5 + _uv_pan
	var fitted := image_rect()
	return fitted.position + Vector2(uv.x * fitted.size.x, uv.y * fitted.size.y)


func _canvas_to_uv(pos: Vector2) -> Vector2:
	if _paint != null and not _paint.is_pixel():
		return (pos - size * 0.5 - _uv_pan) / maxf(_uv_pixels_per_unit, UV_SCALE_MIN) + _uv_center
	var fitted := image_rect()
	if fitted.size.x < 0.001 or fitted.size.y < 0.001:
		return Vector2.ZERO
	return Vector2(
		clampf((pos.x - fitted.position.x) / fitted.size.x, 0.0, 1.0),
		clampf((pos.y - fitted.position.y) / fitted.size.y, 0.0, 1.0)
	)


func _canvas_to_pixel(pos: Vector2) -> Vector2:
	var img: Image = _paint.image() if _paint != null else null
	if img == null or img.is_empty():
		return Vector2.ZERO
	var uv: Vector2 = _canvas_to_uv(pos)
	return Vector2(uv.x * float(img.get_width()), uv.y * float(img.get_height()))


func _zoom_at(pos: Vector2, factor: float) -> void:
	if _paint != null and not _paint.is_pixel():
		var anchor := _canvas_to_uv(pos)
		_uv_pixels_per_unit = clampf(_uv_pixels_per_unit * factor, UV_SCALE_MIN, UV_SCALE_MAX)
		_uv_pan = pos - size * 0.5 - (anchor - _uv_center) * _uv_pixels_per_unit
		queue_redraw()
		return
	var uv: Vector2 = _canvas_to_uv(pos)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var img: Image = _paint.image() if _paint != null else null
	if img == null or img.is_empty():
		queue_redraw()
		return
	var img_size := Vector2(img.get_width(), img.get_height())
	var fit: float = minf(size.x / maxf(1.0, img_size.x), size.y / maxf(1.0, img_size.y))
	var drawn: Vector2 = img_size * fit * _zoom
	_pan = pos - Vector2(uv.x * drawn.x, uv.y * drawn.y) - (size - drawn) * 0.5
	queue_redraw()


func _mapping_signature() -> Array:
	if _paint == null or _paint.is_pixel():
		return ["pixel"]
	var solid: Node3D = _paint.get("_solid")
	var selection: RefCounted = _paint.get("_selection")
	var ids: PackedInt64Array = selection.ids if selection != null else PackedInt64Array()
	var signature: Array = [solid.get_instance_id() if solid != null else 0, ids]
	if solid != null:
		for face in ids:
			var attrs := SlabPaintUv.attrs_of(solid, face)
			# Reframe when mapping is rebuilt or restored, including Undo/Redo.
			# Placement stays excluded so editing it never moves the canvas view.
			signature.append([attrs.get("unwrapped"), attrs.get("u"), attrs.get("v"),
				attrs.get("origin"), attrs.get("axis")])
	return signature


static func _uv_bounds(uvs: PackedVector2Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for uv in uvs:
		lo = lo.min(uv)
		hi = hi.max(uv)
	return Rect2(lo, hi - lo)


static func _uv_loops_bounds(loops: Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for uvs: PackedVector2Array in loops:
		var bounds := _uv_bounds(uvs)
		lo = lo.min(bounds.position)
		hi = hi.max(bounds.end)
	return Rect2(lo, hi - lo)


func _draw_uv_element_selection() -> void:
	if not is_uv_element_mode() or _paint == null:
		return
	var solid: Node3D = _paint.get("_solid")
	var faces: PackedInt64Array = _selection.ids if _selection != null else PackedInt64Array()
	if solid == null or faces.is_empty():
		return
	
	var uv_mode: int = _selection.uv_mode
	var uv_selection: PackedInt64Array = _selection.get_uv_selection()
	var highlight_color := Color(0.2, 0.85, 0.95, 0.9)
	var vert_radius := maxf(4.0, _metrics.px(4.0))
	
	match uv_mode:
		SlabSelection.UVMode.UV_VERT:
			for id in uv_selection:
				var decoded := SlabUVPick._decode_uv_vert(id)
				var face: int = decoded["face"]
				var corner: int = decoded["corner"]
				var uvs := SlabPaintUv.face_uvs(solid, face)
				if corner < uvs.size():
					var canvas_pt := _uv_to_canvas(uvs[corner])
					draw_circle(canvas_pt, vert_radius, highlight_color)
			for face in faces:
				var uvs := SlabPaintUv.face_uvs(solid, face)
				for i in uvs.size():
					var canvas_pt := _uv_to_canvas(uvs[i])
					draw_arc(canvas_pt, vert_radius - 1.0, 0.0, TAU, 16, Color(0.6, 0.6, 0.6, 0.6), 1.0)
		SlabSelection.UVMode.UV_EDGE:
			for face in faces:
				var uvs := SlabPaintUv.face_uvs(solid, face)
				if uvs.size() < 2:
					continue
				for i in uvs.size():
					var canvas_a := _uv_to_canvas(uvs[i])
					var canvas_b := _uv_to_canvas(uvs[(i + 1) % uvs.size()])
					draw_line(canvas_a, canvas_b, Color(0.5, 0.5, 0.5, 0.5), 1.0)
			for id in uv_selection:
				var decoded := SlabUVPick._decode_uv_edge(id)
				var face: int = decoded["face"]
				var edge_index: int = decoded["edge_index"]
				var uvs := SlabPaintUv.face_uvs(solid, face)
				if uvs.size() > edge_index:
					var canvas_a := _uv_to_canvas(uvs[edge_index])
					var canvas_b := _uv_to_canvas(uvs[(edge_index + 1) % uvs.size()])
					draw_line(canvas_a, canvas_b, highlight_color, 3.0)
		SlabSelection.UVMode.UV_FACE:
			for id in uv_selection:
				var uvs := SlabPaintUv.face_uvs(solid, id)
				if uvs.size() < 3:
					continue
				var canvas_poly := PackedVector2Array()
				for uv in uvs:
					canvas_poly.append(_uv_to_canvas(uv))
				var fill_color := Color(highlight_color.r, highlight_color.g, highlight_color.b, 0.25)
				draw_colored_polygon(canvas_poly, fill_color)
				canvas_poly.append(canvas_poly[0])
				draw_polyline(canvas_poly, highlight_color, 2.5, true)


func _pick_uv_at(pos: Vector2) -> Dictionary:
	if _selection == null or _paint == null:
		return {}
	var solid: Node3D = _paint.get("_solid")
	var faces: PackedInt64Array = _selection.ids if _selection != null else PackedInt64Array()
	if solid == null or faces.is_empty():
		return {}
	var uv_to_canvas_func := func(uv: Vector2) -> Vector2: return _uv_to_canvas(uv)
	return SlabUVPick.pick_uv_element(solid, faces, _selection.uv_mode, pos, uv_to_canvas_func)


func uv_to_canvas(uv: Vector2) -> Vector2:
	return _uv_to_canvas(uv)
