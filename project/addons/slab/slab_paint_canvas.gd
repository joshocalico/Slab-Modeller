@tool
extends Control

const SlabPaintUv := preload("res://addons/slab/slab_paint_uv.gd")
const SlabMetrics := preload("res://addons/slab/slab_metrics.gd")

signal painted_pixel(pixel: Vector2)
signal uv_dragged(delta_uv: Vector2, mode: int)
signal stroke_started
signal stroke_ended
signal stroke_cancelled

const ZOOM_MIN := 0.25
const ZOOM_MAX := 8.0

var _paint: RefCounted
var _metrics: RefCounted
var _brush := Vector2(-1, -1)
var _dragging := false
var _panning := false
var _uv_from := Vector2.ZERO
var _zoom: float = 1.0
var _pan := Vector2.ZERO
var _pan_from := Vector2.ZERO
var _pan_origin := Vector2.ZERO


func setup(paint: RefCounted, metrics: RefCounted = null) -> void:
	_paint = paint
	_metrics = metrics if metrics != null else SlabMetrics.at_scale(1.0)
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


func _paint_changed() -> void:
	if not _paint.stroke_active and not _paint.uv_drag_active:
		_dragging = false
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
			_pan_origin = _pan
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
			_pan = _pan_origin + (event.position - _pan_from)
			queue_redraw()
			accept_event()
			return
		if _dragging and _paint.is_pixel():
			if hits_image(event.position):
				painted_pixel.emit(_canvas_to_pixel(event.position))
			accept_event()
		elif _dragging and not _paint.is_pixel():
			if hits_image(event.position):
				var delta: Vector2 = _canvas_to_uv(event.position) - _uv_from
				uv_dragged.emit(delta, _paint.uv_mode_for(event))
			accept_event()
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		if not hits_image(event.position):
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
	var fitted := image_rect()
	if fitted.size.x <= 1.0 or fitted.size.y <= 1.0:
		return
	_draw_checker(fitted)
	var tex: Texture2D = _paint.texture() if _paint != null else null
	if tex != null:
		draw_texture_rect(tex, fitted, false)
	var uvs: PackedVector2Array = _paint.selected_uvs() if _paint != null else PackedVector2Array()
	if uvs.size() >= 2:
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


func _draw_checker(fitted: Rect2) -> void:
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
	var fitted := image_rect()
	return fitted.position + Vector2(uv.x * fitted.size.x, uv.y * fitted.size.y)


func _canvas_to_uv(pos: Vector2) -> Vector2:
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
