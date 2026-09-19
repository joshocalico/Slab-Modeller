extends Node3D

var collected := 0
var gate_open := false
var elapsed := 0.0
var markers: Array[Node3D] = []
var nearest: Node3D
var gate_start := Vector3.ZERO
@onready var player: CharacterBody3D = $Player
@onready var gate: Node3D = $Architecture/ExitGate
var title: Label
var hint: Label
var progress: Label

func _ready() -> void:
	gate_start = gate.position
	for item in $Relays.get_children():
		markers.append(item)
	var hud := CanvasLayer.new()
	add_child(hud)
	var plate := ColorRect.new()
	plate.color = Color(0.055, 0.10, 0.10, 0.88)
	plate.position = Vector2(24, 24)
	plate.size = Vector2(392, 112)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(plate)
	title = label(hud, Vector2(42, 36), 25, "RELAY YARD")
	title.modulate = Color("e8bd76")
	progress = label(hud, Vector2(42, 72), 16, "Recover the three relay cells")
	label(hud, Vector2(42, 100), 13, "WORKSHOP  /  GALLERY  /  LOOKOUT")
	var controls := label(hud, Vector2(24, 0), 14, "WASD move   ·   Mouse look   ·   Space jump   ·   E interact   ·   R reset   ·   Esc release")
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.offset_left = 24
	controls.offset_top = -38
	hint = label(hud, Vector2.ZERO, 20, "")
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -200
	hint.offset_right = 200
	hint.offset_top = -100
	hint.offset_bottom = -68
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cross := label(hud, Vector2.ZERO, 18, "+")
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.offset_left = -5
	cross.offset_top = -12

func label(parent: Node, at: Vector2, font: int, text: String) -> Label:
	var item := Label.new()
	item.text = text
	item.position = at
	item.add_theme_font_size_override("font_size", font)
	item.add_theme_color_override("font_color", Color("ece3ce"))
	item.add_theme_constant_override("outline_size", 3)
	item.add_theme_color_override("font_outline_color", Color("172729"))
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item

func _process(dt: float) -> void:
	elapsed += dt
	nearest = null
	var best := 2.2
	for relay in markers:
		if not relay.visible:
			continue
		relay.rotation.y += dt * 0.8
		var distance := (relay.global_position - (player.global_position + Vector3.UP)).length()
		if distance < best:
			best = distance
			nearest = relay
	if gate_open:
		gate.position = gate.position.lerp(gate_start + Vector3.UP * 5.0, 1.0 - exp(-dt * 2.0))
		if player.position.z > 25.3:
			title.text = "YARD RESTORED"
			progress.text = "All relays recovered · route complete"
			hint.text = "Thanks for exploring Relay Yard"
		else:
			hint.text = "Exit through the illuminated south gate"
	else:
		progress.text = "%d / 3 relay cells recovered" % collected
		hint.text = "E  ·  Recover relay cell" if nearest else ""
		if collected == 3:
			hint.text = "Return to the south gate"
			if player.position.distance_to(Vector3(16, 0, 23)) < 3:
				hint.text = "E  ·  Restore power and open gate"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if nearest != null:
			nearest.hide()
			collected += 1
		elif collected == 3 and player.position.distance_to(Vector3(16, 0, 23)) < 3:
			gate_open = true
