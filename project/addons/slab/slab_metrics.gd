@tool
extends RefCounted

const FONT_FLOOR := 12
const RADIUS_FLOOR_SCALE := 1.0

const SlabPick := preload("res://addons/slab/slab_pick.gd")

var _scale: float = 1.0


static func of(host: RefCounted) -> RefCounted:
	return at_scale(host.ui_scale() if host != null else 1.0)


static func at_scale(scale: float) -> RefCounted:
	var metrics := new()
	metrics._scale = scale
	return metrics


func scale() -> float:
	return _scale


func px(value: float) -> float:
	return value * _scale


func font(size_px: int) -> int:
	return maxi(FONT_FLOOR, int(round(float(size_px) * _scale)))


func pick_radius() -> float:
	return SlabPick.BASE_RADIUS * maxf(_scale, RADIUS_FLOOR_SCALE)
