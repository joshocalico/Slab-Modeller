extends SceneTree

const Bake = preload("res://addons/slab/slab_export_mesh.gd")
const Obj = preload("res://addons/slab/slab_export_obj.gd")
const Import = preload("res://addons/slab/slab_import_mesh.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var directory := "user://obj_bundle_regression"
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join("artwork.obj")
	var material := StandardMaterial3D.new()
	material.resource_name = "Paint"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var artwork := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	artwork.fill(Color(0.3, 0.6, 0.9, 0.5))
	material.albedo_texture = ImageTexture.create_from_image(artwork)
	var baked := Bake.new()
	baked.positions = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	baked.indices = PackedInt32Array([0, 1, 2])
	baked.uvs = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	baked.material_names = PackedStringArray(["Paint"])
	baked.materials = [material]
	baked.material_per_triangle = PackedInt32Array([0])
	check(Obj.write(path, baked) == OK, "initial OBJ bundle writes")
	var imported := Import.load_from_file(path)
	check(imported.error == OK, "alpha-texture OBJ imports")
	if imported.has("mesh"):
		var restored: StandardMaterial3D = imported.mesh.get_materials()[0]
		check(is_equal_approx(restored.albedo_color.a, 1.0), "scalar opacity remains one")
		check(restored.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "transparent PNG enables alpha blending with scalar opacity one")
		check(restored.albedo_texture.get_image().get_pixel(0, 0).is_equal_approx(artwork.get_pixel(0, 0)), "transparent pixel RGBA survives")
		imported.mesh.free()
	var mtl_path: String = directory.path_join("artwork.mtl")
	var mtl_text: String = FileAccess.get_file_as_string(mtl_path)
	var mtl := FileAccess.open(mtl_path, FileAccess.WRITE)
	mtl.store_string(mtl_text.replace("d 1.000000\n", "") + "d 1\n")
	mtl.close()
	imported = Import.load_from_file(path)
	check(imported.error == OK, "MTL with opacity after texture imports")
	if imported.has("mesh"):
		check(imported.mesh.get_materials()[0].transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "later d 1 preserves texture alpha")
		imported.mesh.free()
	var before: Dictionary = {}
	for name in DirAccess.get_files_at(directory):
		before[name] = FileAccess.get_file_as_bytes(directory.path_join(name))
	var permissions: int = FileAccess.get_unix_permissions(path)
	var chmod_error: int = FileAccess.set_unix_permissions(path, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_READ_OTHER)
	if chmod_error == OK:
		material.albedo_color = Color(1, 0, 0, 1)
		artwork.fill(Color(0, 1, 0, 0.25))
		material.albedo_texture = ImageTexture.create_from_image(artwork)
		check(Obj.write(path, baked) != OK, "unwritable existing OBJ reports failure")
		for name in before:
			check(FileAccess.get_file_as_bytes(directory.path_join(name)) == before[name], "failed export preserves existing dependency: %s" % name)
		check(DirAccess.get_files_at(directory).size() == before.size(), "failed export leaves no replacement textures")
		check(DirAccess.get_directories_at(directory).is_empty(), "failed export cleans staging directory")
		FileAccess.set_unix_permissions(path, permissions)
	else:
		print("Unix permission regression unavailable on this platform")
	# Simulate a staged entry point disappearing between preflight and installation.
	var staging: String = directory.path_join("forced-stage")
	DirAccess.make_dir_absolute(staging)
	var staged_file := FileAccess.open(staging.path_join("artwork.mtl"), FileAccess.WRITE)
	staged_file.store_string("replacement material")
	staged_file.close()
	staged_file = FileAccess.open(staging.path_join("new_texture.png"), FileAccess.WRITE)
	staged_file.store_string("replacement texture")
	staged_file.close()
	var result: Dictionary = Obj._replace_bundle(staging, directory, PackedStringArray(["new_texture.png", "artwork.mtl", "artwork.obj"]))
	check(result.error != OK and not result.get("recovery_needed", false), "late install failure rolls back successfully")
	Obj._remove_staging(staging)
	for name in before:
		check(FileAccess.get_file_as_bytes(directory.path_join(name)) == before[name], "rollback restores existing bundle file: %s" % name)
	check(not FileAccess.file_exists(directory.path_join("new_texture.png")), "rollback removes newly installed texture")
	material.albedo_color = Color.WHITE
	artwork.fill(Color.WHITE)
	material.albedo_texture = ImageTexture.create_from_image(artwork)
	check(Obj.write(path, baked) == OK, "writable bundle replaces successfully after failure")
	imported = Import.load_from_file(path)
	check(imported.error == OK, "opaque bundle imports")
	if imported.has("mesh"):
		check(imported.mesh.get_materials()[0].transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "fully opaque texture does not enable blending")
		imported.mesh.free()
	for name in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	print("OBJ bundle regressions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
