extends AnimatableBody3D

## Physics-safe shuttle for editor-authored SlabSolid children.
## At runtime, their existing collision is adopted by this AnimatableBody3D.

@export var local_travel := Vector3(0, 0, 5)
@export_range(0.1, 120.0, 0.1) var travel_duration := 3.0
@export_range(0.0, 30.0, 0.1) var endpoint_pause := 0.5
@export var starts_forward := true
@export var shuttle_enabled := true

var start_transform := Transform3D.IDENTITY
var elapsed := 0.0
var direction := 1.0
var pause_left := 0.0
var adopted_shapes := 0


func _ready() -> void:
	sync_to_physics = true
	start_transform = transform
	direction = 1.0 if starts_forward else -1.0
	_adopt_slab_collisions(self, Transform3D.IDENTITY)
	if adopted_shapes == 0:
		push_warning("MovingPlatform needs an editor-authored SlabSolid child with collision enabled.")


func _physics_process(delta: float) -> void:
	if not shuttle_enabled:
		return
	if pause_left > 0.0:
		pause_left = maxf(0.0, pause_left - delta)
		return
	elapsed += delta * direction
	if elapsed >= travel_duration:
		elapsed = travel_duration
		direction = -1.0
		pause_left = endpoint_pause
	elif elapsed <= 0.0:
		elapsed = 0.0
		direction = 1.0
		pause_left = endpoint_pause
	var weight := smoothstep(0.0, 1.0, elapsed / travel_duration)
	transform = start_transform.translated_local(local_travel * weight)


func _adopt_slab_collisions(node: Node, relative: Transform3D) -> void:
	for child in node.get_children():
		if child.is_class("SlabSolid"):
			var body: StaticBody3D = child.get_node_or_null("__body")
			var source: CollisionShape3D = body.get_node_or_null("__shape") if body != null else null
			if source != null and source.shape != null and not source.disabled:
				var carrier_shape := CollisionShape3D.new()
				carrier_shape.name = "CarrierShape%d" % adopted_shapes
				carrier_shape.transform = relative * child.transform * body.transform * source.transform
				carrier_shape.shape = source.shape
				add_child(carrier_shape)
				source.disabled = true
				adopted_shapes += 1
		_adopt_slab_collisions(child, relative * child.transform)
