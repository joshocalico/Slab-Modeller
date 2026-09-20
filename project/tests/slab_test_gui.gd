extends RefCounted

# Viewport mouse helpers so panel, topology, paint, and reopen smokes drive
# real GUI input instead of Button.pressed.emit().


static func mouse_button(pressed: bool, position: Vector2, global_position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = position
	event.global_position = global_position
	return event


static func hover(control: Control) -> void:
	if control == null:
		return
	var pos: Vector2 = control.get_global_rect().get_center()
	var vp: Viewport = control.get_viewport()
	if vp == null:
		return
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	vp.push_input(motion)


static func mouse_click(control: Control) -> void:
	if control == null:
		return
	var pos: Vector2 = control.get_global_rect().get_center()
	var vp: Viewport = control.get_viewport()
	if vp == null:
		return
	vp.push_input(mouse_button(true, pos, pos))
	vp.push_input(mouse_button(false, pos, pos))


static func ensure_scrolled(control: Control) -> void:
	if control == null:
		return
	var walk: Node = control.get_parent()
	while walk != null:
		if walk is ScrollContainer:
			(walk as ScrollContainer).ensure_control_visible(control)
			return
		walk = walk.get_parent()


static func click(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	ensure_scrolled(control)
	hover(control)
	mouse_click(control)
	return true
