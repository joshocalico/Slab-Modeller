extends CharacterBody3D

## First-person walker for editor-placed Signal Foundry instances.
## Origin is the feet. Instance the packed scene, put the origin on a floor, Play.
##
## Move: WASD (physical). Look: mouse, arrows, or numpad 8/2/4/6.
## Jump: Space. Sprint: Shift. Release mouse: Esc. Recapture: left click.
## T toggles auto-run (walk forward without holding W; T, S, Esc, or R stop it).
## Q / E yaw 15° left / right per tap. R restores the transform from `_ready`.

const SPEED := 5.0
const SPRINT := 1.45
const JUMP := 6.0
const GRAVITY := 19.0
const MOUSE_SENS := 0.0025
const LOOK_SPEED := 2.2
const PITCH_LIMIT := 1.4
const COYOTE := 0.12
const JUMP_BUFFER := 0.12
const STEP_HEIGHT := 0.28
const FALL_RESET_Y := -6.0
const YAW_STEP := deg_to_rad(15.0)

var spawn_transform := Transform3D.IDENTITY
var spawn_pitch := 0.0
var pitch := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var auto_run := false

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_bind_action("foundry_left", KEY_A)
	_bind_action("foundry_right", KEY_D)
	_bind_action("foundry_forward", KEY_W)
	_bind_action("foundry_back", KEY_S)
	_bind_action("foundry_jump", KEY_SPACE)
	_bind_action("foundry_reset", KEY_R)
	_bind_action("foundry_autorun", KEY_T)
	_bind_action("foundry_yaw_left", KEY_Q)
	_bind_action("foundry_yaw_right", KEY_E)
	_bind_action("foundry_look_left", KEY_LEFT)
	_bind_action("foundry_look_right", KEY_RIGHT)
	_bind_action("foundry_look_up", KEY_UP)
	_bind_action("foundry_look_down", KEY_DOWN)
	_bind_action("foundry_look_left", KEY_KP_4)
	_bind_action("foundry_look_right", KEY_KP_6)
	_bind_action("foundry_look_up", KEY_KP_8)
	_bind_action("foundry_look_down", KEY_KP_2)
	floor_snap_length = 0.35
	spawn_transform = global_transform
	spawn_pitch = camera.rotation.x
	pitch = spawn_pitch
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -PITCH_LIMIT, PITCH_LIMIT)
		camera.rotation.x = pitch
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if event.keycode == KEY_ESCAPE:
			auto_run = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_R or code == KEY_R:
			_reset_to_spawn()
		elif code == KEY_T:
			auto_run = not auto_run
		elif code == KEY_S:
			auto_run = false
		elif code == KEY_Q:
			rotation.y += YAW_STEP
		elif code == KEY_E:
			rotation.y -= YAW_STEP
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(dt: float) -> void:
	if Input.is_action_just_pressed("foundry_reset"):
		_reset_to_spawn()
		return

	if Input.is_action_pressed("foundry_back"):
		auto_run = false

	var look := Input.get_vector("foundry_look_left", "foundry_look_right", "foundry_look_up", "foundry_look_down")
	if look != Vector2.ZERO:
		rotation.y -= look.x * LOOK_SPEED * dt
		pitch = clampf(pitch - look.y * LOOK_SPEED * dt, -PITCH_LIMIT, PITCH_LIMIT)
		camera.rotation.x = pitch

	if is_on_floor():
		coyote = COYOTE
	else:
		coyote = maxf(0.0, coyote - dt)

	if Input.is_action_just_pressed("foundry_jump"):
		jump_buffer = JUMP_BUFFER
	else:
		jump_buffer = maxf(0.0, jump_buffer - dt)

	var keys := Input.get_vector("foundry_left", "foundry_right", "foundry_forward", "foundry_back")
	if auto_run:
		keys.y = -1.0
	var wish := Vector3(keys.x, 0, keys.y)
	var direction := (global_basis * wish).normalized() if wish.length_squared() > 0.0 else Vector3.ZERO
	var speed := SPEED * (SPRINT if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if jump_buffer > 0.0 and coyote > 0.0:
		velocity.y = JUMP
		jump_buffer = 0.0
		coyote = 0.0
	elif not is_on_floor():
		velocity.y -= GRAVITY * dt

	var horizontal := Vector3(velocity.x, 0, velocity.z) * dt
	if is_on_floor() and horizontal.length_squared() > 0.00001 and test_move(global_transform, horizontal):
		var lift := Vector3.UP * STEP_HEIGHT
		if not test_move(global_transform, lift) and not test_move(global_transform.translated(lift), horizontal):
			global_position.y += STEP_HEIGHT
	move_and_slide()
	if global_position.y < FALL_RESET_Y:
		_reset_to_spawn()


func _reset_to_spawn() -> void:
	global_transform = spawn_transform
	pitch = spawn_pitch
	camera.rotation.x = pitch
	velocity = Vector3.ZERO
	coyote = 0.0
	jump_buffer = 0.0
	auto_run = false


func _bind_action(action: String, code: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var binding := InputEventKey.new()
	binding.physical_keycode = code
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == code:
			return
	InputMap.action_add_event(action, binding)
