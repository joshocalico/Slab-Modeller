extends CharacterBody3D

const SPEED := 5.0
const JUMP := 6.0
const GRAVITY := 19.0
var spawn := Vector3(16, 0.15, 21)
var pitch := 0.0
var movement_enabled := true
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	for pair in [["yard_left", KEY_A], ["yard_right", KEY_D], ["yard_forward", KEY_W], ["yard_back", KEY_S]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var binding := InputEventKey.new()
			binding.physical_keycode = pair[1]
			InputMap.action_add_event(pair[0], binding)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = 0.35

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * 0.0025
		pitch = clampf(pitch - event.relative.y * 0.0025, -1.4, 1.4)
		camera.rotation.x = pitch
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			movement_enabled = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_R:
			global_position = spawn
			velocity = Vector3.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		movement_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(dt: float) -> void:
	if not movement_enabled:
		velocity.x = 0
		velocity.z = 0
	else:
		var keys := Input.get_vector("yard_left", "yard_right", "yard_forward", "yard_back")
		var direction := global_basis * Vector3(keys.x, 0, keys.y).normalized()
		var speed := SPEED * (1.45 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if is_on_floor() and Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP
	if not is_on_floor():
		velocity.y -= GRAVITY * dt
	# Step onto the actual Slab stair treads; no hidden collision ramp.
	var horizontal := Vector3(velocity.x, 0, velocity.z) * dt
	if is_on_floor() and horizontal.length_squared() > 0.00001 and test_move(global_transform, horizontal):
		var lifted := global_transform.translated(Vector3.UP * 0.28)
		if not test_move(global_transform, Vector3.UP * 0.28) and not test_move(lifted, horizontal):
			global_position.y += 0.28
	move_and_slide()
	if global_position.y < -6:
		global_position = spawn
		velocity = Vector3.ZERO
