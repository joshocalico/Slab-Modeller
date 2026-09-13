extends SceneTree

const Gizmo := preload("res://addons/slab/gizmos/slab_solid_gizmo.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var base := { "anchor": Vector3.ZERO, "axis": Vector3.UP, "tangent": Vector3.RIGHT, "tip": Vector3(0, 1, 0),
		"segments": PackedVector3Array([Vector3.ZERO, Vector3(0, 1, 0)]), "amount": 0.4, "label": "Extrude  0.400 m" }
	var extrude := base.duplicate()
	extrude["kind"] = 0
	var inset := base.duplicate()
	inset["kind"] = 1
	var bevel := base.duplicate()
	bevel["kind"] = 2
	check(Gizmo.operation_handle_lines(extrude).size() == 6, "extrusion renders a shaft and two-sided arrowhead")
	check(Gizmo.operation_handle_lines(inset).size() == 10, "inset renders separated rails and width ticks at both ends")
	check(Gizmo.operation_handle_lines(bevel).size() >= 24, "bevel renders a width arc and three radial ticks")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(3, 3, 6), Vector3.ZERO, Vector3.UP)
	var label: Dictionary = Gizmo.operation_overlay_label(extrude, camera)
	check(label.get("text", "") == "Extrude  0.400 m" and label.get("screen", Vector2.ZERO).is_finite(),
		"overlay helper preserves numeric label and returns a finite screen anchor")
	var fill := Gizmo.overlay_material(Color(1.0, 0.62, 0.18, 0.14), true, false)
	check(is_equal_approx(fill.albedo_color.a, 0.14), "face tint preserves the requested alpha")
	check(fill.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and fill.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and not fill.no_depth_test,
		"face tint is explicitly transparent, unshaded and depth-aware")
	var handle := StandardMaterial3D.new()
	Gizmo.configure_overlay_material(handle, false, true)
	check(handle.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and handle.no_depth_test,
		"operation wire is explicitly opaque and visible through depth")
	camera.free()
	print("operation_handle_render_smoke: %d failures" % failures)
	quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("ok " if ok else "FAIL ", message)
