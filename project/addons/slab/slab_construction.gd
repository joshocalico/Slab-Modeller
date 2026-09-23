@tool
extends RefCounted

const Step := preload("res://addons/slab/slab_construction_step.gd")
const Recipe := preload("res://addons/slab/slab_construction_recipe.gd")
const RECIPE_META := "slab_construction_recipe"
const UUID_META := "slab_construction_uuid"
const OUTPUT_META := "slab_construction_output"
const MAX_OUTPUTS := 1024

# Explicit registration, used when binding an operand. Callers can include this
# metadata change in their own selection/binding Undo action.
static func ensure_uuid(node: Node) -> String:
	if not node.has_meta(UUID_META):
		node.set_meta(UUID_META, Step.new_uuid())
	return str(node.get_meta(UUID_META))

static func from_primitive(target: Node3D, method: StringName, args: Array) -> Resource:
	var recipe := Recipe.new()
	if target.has_meta(UUID_META): recipe.node_uuid = str(target.get_meta(UUID_META))
	recipe.base_materials.assign(_materials_for(target))
	var source := Step.new()
	source.parameters = {"method": method, "args": args.duplicate(true)}
	recipe.steps.append(source)
	return recipe

static func from_mesh(target: Node3D) -> Resource:
	var recipe := Recipe.new()
	if target.has_meta(UUID_META): recipe.node_uuid = str(target.get_meta(UUID_META))
	recipe.base_materials.assign(_materials_for(target))
	var source := Step.new()
	source.kind = Step.Kind.MESH_SOURCE
	source.parameters = {"data": target.get("data")}
	recipe.steps.append(source)
	return recipe

# This is an explicit manual-edit barrier, not a fake replayable topology step.
# Upstream changes must be rebound before crossing the checkpoint.
static func checkpoint(target: Node3D) -> Resource:
	var previous = (target.get_meta(RECIPE_META) if target.has_meta(RECIPE_META) else null)
	if previous == null: return null
	var candidate = previous.copy_recipe()
	var step := Step.new()
	step.kind = Step.Kind.CHECKPOINT
	step.input_fingerprint = Step.fingerprint(previous.cached_data)
	step.parameters = {"data": target.get("data"), "materials": target.get("materials").duplicate()}
	candidate.steps.append(step)
	return candidate

func evaluate(candidate: Resource, scene_root: Node, target: Node3D, operand_bindings: Dictionary = {}) -> Dictionary:
	if not candidate is Recipe or scene_root == null or not scene_root.is_inside_tree() or target == null or not target.is_inside_tree():
		return _failure("Construction needs a recipe and an attached scene target.")
	var registry: Dictionary = {}
	var pending: Array[Node] = [scene_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node.has_meta(UUID_META):
			var uuid := str(node.get_meta(UUID_META))
			if registry.has(uuid): return _failure("Duplicate construction operand identity: " + uuid)
			registry[uuid] = node
	for uuid in operand_bindings:
		var operand = operand_bindings[uuid]
		if not is_instance_valid(operand) or not operand is Node3D or not scene_root.is_ancestor_of(operand):
			return _failure("Operand binding is outside the edited scene.")
		if registry.has(uuid) and registry[uuid] != operand: return _failure("Duplicate operand binding.")
		if operand.has_meta(UUID_META) and str(operand.get_meta(UUID_META)) != uuid: return _failure("Operand binding identity changed.")
		registry[uuid] = operand
	# Scratch solids need a SceneTree for boolean_with's global transforms, but
	# they are never owned by the edited scene and cannot enter its saved data.
	var scratch := Node3D.new()
	scratch.name = "ConstructionEvaluation"
	scratch.visible = false
	scene_root.get_tree().root.add_child(scratch)
	var result := _evaluate(candidate, target, registry, [], scratch)
	scratch.free()
	return result

func _evaluate(recipe: Resource, target: Node3D, registry: Dictionary, visiting: Array, scratch: Node3D) -> Dictionary:
	if not recipe is Recipe:
		return _failure("Operand construction metadata is not a recipe.")
	if target.has_meta(UUID_META) and str(target.get_meta(UUID_META)) != recipe.node_uuid:
		return _failure("Recipe identity does not match its target.")
	if recipe.schema_version != Recipe.VERSION or recipe.evaluator_version != 1:
		return _failure("Unsupported construction recipe version.")
	if recipe.node_uuid.is_empty() or visiting.has(recipe.node_uuid):
		return _failure("Construction operand cycle detected.")
	var chain := visiting.duplicate()
	chain.append(recipe.node_uuid)
	if recipe.steps.is_empty(): return _failure("Construction needs a source step.")
	var ids: Dictionary = {}
	var instances: Array[Dictionary] = []
	for index in recipe.steps.size():
		var step: Resource = recipe.steps[index]
		if step == null or step.id.is_empty() or ids.has(step.id): return _failure("Construction step identities must be unique.")
		ids[step.id] = true
		if index == 0 and (not step.enabled or step.kind not in [Step.Kind.PRIMITIVE, Step.Kind.MESH_SOURCE]):
			return _failure("The enabled source must stay first.", step.id)
		if index > 0 and step.kind in [Step.Kind.PRIMITIVE, Step.Kind.MESH_SOURCE]:
			return _failure("A source cannot replace an intermediate result.", step.id)
		if not step.enabled: continue
		var problem := _validate_step(step)
		if not problem.is_empty(): return _failure(problem, step.id)
		if index == 0:
			var source := _new_solid(scratch)
			var error: int = OK
			if step.kind == Step.Kind.PRIMITIVE:
				error = source.callv(step.parameters.method, step.parameters.args)
			else:
				source.set("data", step.parameters.data)
			if error != OK or source.call("face_count") == 0: return _failure("Source could not build a valid solid.", step.id)
			instances.append({"id": "primary", "transform": Transform3D.IDENTITY,
				"data": source.get("data"), "materials": recipe.base_materials.duplicate()})
			continue
		if step.kind in [Step.Kind.ARRAY_LINEAR, Step.Kind.ARRAY_RADIAL]:
			if instances.size() * int(step.parameters.count) > MAX_OUTPUTS: return _failure("Array exceeds the construction output limit.", step.id)
			var sources := instances.duplicate(true)
			for entry in sources:
				for copy_index in range(1, int(step.parameters.count)):
					var copy: Dictionary = entry.duplicate(true)
					copy.id = "%s/%s/%s/%d" % [recipe.node_uuid, entry.id, step.id, copy_index]
					var xform: Transform3D = entry.transform
					if step.kind == Step.Kind.ARRAY_LINEAR:
						xform.origin += step.parameters.step * copy_index
					else:
						var turn := Basis((step.parameters.axis as Vector3).normalized(), deg_to_rad(float(step.parameters.angle) * copy_index))
						xform.origin = step.parameters.center + turn * (xform.origin - step.parameters.center)
						if step.parameters.get("rotate", true): xform.basis = turn * xform.basis
					copy.transform = xform
					instances.append(copy)
			continue
		var operand: Node3D = null
		var operand_result: Dictionary = {}
		if step.kind == Step.Kind.BOOLEAN:
			operand = registry.get(step.operand_uuid)
			if operand == null or not operand.is_class("SlabSolid"): return _failure("Boolean operand is missing: " + step.operand_uuid, step.id)
			if operand == target or chain.has(step.operand_uuid): return _failure("Construction operand cycle detected.", step.id)
			var operand_recipe = (operand.get_meta(RECIPE_META) if operand.has_meta(RECIPE_META) else null)
			if operand_recipe != null:
				if not operand_recipe is Recipe or operand.get("data") != operand_recipe.cached_data or operand.get("materials") != operand_recipe.cached_materials:
					return _failure("Boolean operand has unrecorded manual edits; checkpoint it first.", step.id)
				operand_result = _evaluate(operand_recipe, operand, registry, chain, scratch)
				if operand_result.error != OK: return operand_result
				if not operand_result.instances.is_empty(): return _failure("Boolean operand has generated objects; choose an independent output.", step.id)
			else:
				operand_result = {"data": operand.get("data"), "materials": _materials_for(operand)}
		for entry in instances:
			var solid := _new_solid(scratch)
			solid.set("data", entry.data)
			if solid.call("face_count") == 0: return _failure("Invalid intermediate mesh.", step.id)
			var error: int = OK
			match step.kind:
				Step.Kind.BEVEL:
					var edges: PackedInt64Array = solid.call("get_edges")
					if step.selection_binding == Step.SelectionBinding.PINNED_EDGES:
						if Step.fingerprint(entry.data) != step.input_fingerprint:
							return _failure("Picked edges need rebinding after the upstream mesh changed.", step.id)
						for edge in step.picked_edges:
							if not edges.has(edge): return _failure("Picked edge no longer exists.", step.id)
						edges = step.picked_edges
					if step.selection_binding == Step.SelectionBinding.MIN_CORNER_X_EDGE:
						var selected := PackedInt64Array()
						var minimum: Vector3 = solid.call("get_local_aabb").position
						for edge in edges:
							var ends: PackedInt64Array = solid.call("edge_vertices", edge)
							var a: Vector3 = solid.call("vertex_position", ends[0])
							var b: Vector3 = solid.call("vertex_position", ends[1])
							if (a.is_equal_approx(minimum) or b.is_equal_approx(minimum)) and absf((b - a).normalized().dot(Vector3.RIGHT)) > 0.99999:
								selected.append(edge)
						if selected.size() != 1: return _failure("Minimum-corner X edge is missing or ambiguous; choose a new edge binding.", step.id)
						edges = selected
					error = solid.call("bevel_edges", edges, step.parameters.amount, step.parameters.segments)
				Step.Kind.BOOLEAN:
					var cutter := _new_solid(scratch)
					cutter.set("data", operand_result.data)
					if cutter.call("face_count") == 0: return _failure("Boolean operand has invalid mesh data.", step.id)
					var materials: Array = entry.materials.duplicate()
					var cutter_materials: Array = operand_result.materials
					for face in cutter.call("get_faces"):
						var old_slot: int = cutter.call("face_uv", face).slot
						var material: Material = cutter_materials[old_slot] if old_slot < cutter_materials.size() else null
						var new_slot := materials.find(material)
						if new_slot < 0:
							new_slot = materials.size()
							materials.append(material)
						cutter.call("set_face_material", PackedInt64Array([face]), new_slot)
					solid.transform = entry.transform
					cutter.transform = target.global_transform.affine_inverse() * operand.global_transform
					error = solid.call("boolean_with", cutter, step.parameters.mode)
					entry.materials = materials
				Step.Kind.CHECKPOINT:
					if instances.size() != 1 or Step.fingerprint(entry.data) != step.input_fingerprint:
						return _failure("Manual topology/UV checkpoint needs rebasing before upstream changes.", step.id)
					solid.set("data", step.parameters.data)
					entry.materials = step.parameters.get("materials", entry.materials)
			if error != OK or solid.call("face_count") == 0:
				return _failure("Construction operation failed (%d); last good result is unchanged." % error, step.id)
			entry.data = solid.get("data")
	var accepted: Resource = recipe.copy_recipe()
	accepted.cached_data = instances[0].data
	accepted.cached_materials.assign(instances[0].materials)
	accepted.cached_instances.assign(instances.slice(1).duplicate(true))
	return {"error": OK, "recipe": accepted, "data": accepted.cached_data,
		"materials": accepted.cached_materials, "instances": accepted.cached_instances}

func _validate_step(step: Resource) -> String:
	var p: Dictionary = step.parameters
	match step.kind:
		Step.Kind.PRIMITIVE:
			var signatures := {"make_box": [TYPE_VECTOR3], "make_plane": [TYPE_VECTOR2],
				"make_stair": [TYPE_VECTOR3, TYPE_INT], "make_cylinder": [TYPE_FLOAT, TYPE_FLOAT, TYPE_INT],
				"make_arch": [TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_FLOAT, TYPE_FLOAT],
				"make_prism": [TYPE_PACKED_VECTOR3_ARRAY, TYPE_FLOAT], "make_sweep": [TYPE_PACKED_VECTOR3_ARRAY, TYPE_VECTOR2, TYPE_BOOL]}
			var method := str(p.get("method", ""))
			if not signatures.has(method) or not p.get("args") is Array: return "Unknown primitive or malformed arguments."
			var signature: Array = signatures[method]
			if p.args.size() != signature.size(): return "Primitive argument count is invalid."
			for i in signature.size():
				if typeof(p.args[i]) != signature[i] and not (signature[i] == TYPE_FLOAT and typeof(p.args[i]) == TYPE_INT):
					return "Primitive argument type is invalid."
				if not _finite_argument(p.args[i]): return "Primitive arguments must be finite."
		Step.Kind.MESH_SOURCE, Step.Kind.CHECKPOINT:
			if not p.get("data") is PackedByteArray or p.data.is_empty(): return "Mesh source/checkpoint needs serialized mesh data."
			if step.kind == Step.Kind.CHECKPOINT and step.input_fingerprint.is_empty(): return "Checkpoint needs its upstream fingerprint."
		Step.Kind.BEVEL:
			if step.selection_binding not in [Step.SelectionBinding.ALL_EDGES, Step.SelectionBinding.PINNED_EDGES, Step.SelectionBinding.MIN_CORNER_X_EDGE]: return "Unknown bevel selection binding."
			if typeof(p.get("amount")) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(p.amount)) or p.amount <= 0: return "Bevel amount must be finite and positive."
			if typeof(p.get("segments")) != TYPE_INT or p.segments < 1 or p.segments > 64: return "Bevel segments must be between 1 and 64."
			if step.selection_binding == Step.SelectionBinding.PINNED_EDGES and (step.picked_edges.is_empty() or step.input_fingerprint.is_empty()): return "Picked bevel edges need IDs and an input fingerprint."
		Step.Kind.BOOLEAN:
			if step.operand_uuid.is_empty() or typeof(p.get("mode")) != TYPE_INT or p.mode not in [0, 1, 2]: return "Boolean needs an operand UUID and valid mode."
		Step.Kind.ARRAY_LINEAR, Step.Kind.ARRAY_RADIAL:
			if typeof(p.get("count")) != TYPE_INT or p.count < 2 or p.count > 256: return "Array count must be between 2 and 256."
			if step.kind == Step.Kind.ARRAY_LINEAR:
				if not p.get("step") is Vector3 or not p.step.is_finite(): return "Array step must be finite."
			else:
				if not p.get("center") is Vector3 or not p.center.is_finite() or not p.get("axis") is Vector3 or not p.axis.is_finite() or p.axis.is_zero_approx(): return "Radial array needs a finite centre and nonzero axis."
				if typeof(p.get("rotate", true)) != TYPE_BOOL: return "Radial rotate must be a boolean."
				if typeof(p.get("angle")) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(p.angle)): return "Radial array angle must be finite."
		_: return "Unsupported construction step."
	return ""

static func _finite_argument(value: Variant) -> bool:
	if value is float: return is_finite(value)
	if value is Vector2 or value is Vector3: return value.is_finite()
	if value is PackedVector2Array or value is PackedVector3Array:
		for point in value:
			if not point.is_finite(): return false
	return true

# Material slot 0 must remain reserved for the source even when it uses the
# prototype fallback; otherwise adding the cutter's first material recolors it.
static func _materials_for(solid: Node3D) -> Array:
	var materials: Array = solid.get("materials").duplicate()
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = solid.get("prototype_color")
	for face in solid.call("get_faces"):
		var slot: int = solid.call("face_uv", face).slot
		while materials.size() <= slot: materials.append(null)
	for i in materials.size():
		if materials[i] == null: materials[i] = fallback
	return materials

func _new_solid(parent: Node) -> Node3D:
	var solid: Node3D = ClassDB.instantiate("SlabSolid")
	solid.set("collision_enabled", false)
	parent.add_child(solid)
	return solid

static func _failure(message: String, step_id: String = "") -> Dictionary:
	return {"error": ERR_INVALID_DATA, "message": message, "step_id": step_id}

func edit_step(target: Node3D, step_id: String, parameters: Dictionary, scene_root: Node, undo: Object = null) -> Dictionary:
	var candidate = _candidate(target)
	if candidate == null: return _failure("This solid has no construction recipe.")
	for step in candidate.steps:
		if step.id == step_id:
			step.parameters.merge(parameters, true)
			return apply_candidate(target, candidate, scene_root, undo, "Edit construction parameters")
	return _failure("Construction step was not found.", step_id)

func reorder_step(target: Node3D, step_id: String, destination: int, scene_root: Node, undo: Object = null) -> Dictionary:
	var candidate = _candidate(target)
	if candidate == null: return _failure("This solid has no construction recipe.")
	if destination < 0 or destination >= candidate.steps.size(): return _failure("Reorder destination is outside the stack.", step_id)
	for index in candidate.steps.size():
		if candidate.steps[index].id == step_id:
			var step: Resource = candidate.steps[index]
			candidate.steps.remove_at(index)
			candidate.steps.insert(destination, step)
			return apply_candidate(target, candidate, scene_root, undo, "Reorder construction")
	return _failure("Construction step was not found.", step_id)

func set_step_enabled(target: Node3D, step_id: String, enabled: bool, scene_root: Node, undo: Object = null) -> Dictionary:
	var candidate = _candidate(target)
	if candidate == null: return _failure("This solid has no construction recipe.")
	for step in candidate.steps:
		if step.id == step_id:
			step.enabled = enabled
			return apply_candidate(target, candidate, scene_root, undo, "Toggle construction step")
	return _failure("Construction step was not found.", step_id)

func _candidate(target: Node3D) -> Resource:
	var recipe = (target.get_meta(RECIPE_META) if target.has_meta(RECIPE_META) else null)
	return recipe.copy_recipe() if recipe is Recipe else null

func apply_candidate(target: Node3D, candidate: Resource, scene_root: Node, undo: Object = null, label: String = "Edit construction", operand_bindings: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(target) or not target.is_class("SlabSolid") or not candidate is Recipe:
		return _failure("Construction requires a SlabSolid and recipe.")
	if target.has_meta(UUID_META) and str(target.get_meta(UUID_META)) != candidate.node_uuid:
		return _failure("Recipe identity does not match its target.")
	var seen_outputs: Dictionary = {}
	for child in target.get_children():
		if not child.has_meta(OUTPUT_META): continue
		var identity := str(child.get_meta(OUTPUT_META))
		if not child.is_class("SlabSolid") or seen_outputs.has(identity) or not identity.begins_with(candidate.node_uuid + "/"):
			return _failure("Invalid or duplicate generated-object identity.")
		seen_outputs[identity] = true
	var current = (target.get_meta(RECIPE_META) if target.has_meta(RECIPE_META) else null)
	if current is Recipe:
		var checkpoint_matches := false
		if not candidate.steps.is_empty():
			var last: Resource = candidate.steps.back()
			checkpoint_matches = (last.kind == Step.Kind.CHECKPOINT and last.enabled
				and last.parameters.get("data") == target.get("data")
				and last.input_fingerprint == Step.fingerprint(current.cached_data))
		if (target.get("data") != current.cached_data or target.get("materials") != current.cached_materials) and not checkpoint_matches:
			return _failure("Manual topology or UV changes need an explicit construction checkpoint.")
		var existing := _outputs(target)
		if existing.size() != current.cached_instances.size(): return _failure("Generated objects changed; make them independent before rebuilding.")
		for entry in current.cached_instances:
			if not existing.has(entry.id): return _failure("A generated object is missing; restore it or make the array independent.")
			var child: Node3D = existing[entry.id]
			if child.get("data") != entry.data or child.transform != entry.transform or child.get("materials") != entry.materials or child.get_child_count() > 0:
				return _failure("A generated object was edited; make it independent before rebuilding.")
	var result := evaluate(candidate, scene_root, target, operand_bindings)
	if result.error != OK: return result
	var before := _capture_state(target)
	var after := {"data": result.data, "materials": result.materials, "recipe": result.recipe,
		"has_uuid": true, "uuid": candidate.node_uuid, "outputs": []}
	before["bindings"] = []
	after["bindings"] = []
	for uuid in operand_bindings:
		var operand: Node = operand_bindings[uuid]
		before.bindings.append({"node": operand, "present": operand.has_meta(UUID_META), "uuid": operand.get_meta(UUID_META, "")})
		after.bindings.append({"node": operand, "present": true, "uuid": uuid})
	var known := _outputs(target)
	for entry in result.instances:
		var child: Node3D = known.get(entry.id)
		if child == null:
			child = ClassDB.instantiate("SlabSolid")
			child.name = "Array_%s" % str(entry.id).get_slice("/", str(entry.id).get_slice_count("/") - 1)
			child.set("prototype_color", target.get("prototype_color"))
			child.set("collision_enabled", target.get("collision_enabled"))
		after.outputs.append({"node": child, "id": entry.id, "data": entry.data,
			"transform": entry.transform, "materials": entry.materials})
	_restore_state(target, after)
	if undo != null:
		if undo is UndoRedo:
			undo.create_action(label)
			undo.add_do_method(_restore_state.bind(target, after))
			undo.add_undo_method(_restore_state.bind(target, before))
		else:
			undo.create_action(label, UndoRedo.MERGE_DISABLE, target)
			undo.add_do_method(self, "_restore_state", target, after)
			undo.add_undo_method(self, "_restore_state", target, before)
		var before_nodes: Array = []
		var after_nodes: Array = []
		for entry in before.outputs: before_nodes.append(entry.node)
		for entry in after.outputs: after_nodes.append(entry.node)
		for child in after_nodes:
			if not before_nodes.has(child): undo.add_do_reference(child)
		for child in before_nodes:
			if not after_nodes.has(child): undo.add_undo_reference(child)
		undo.commit_action(false)
	else:
		for entry in before.outputs:
			if entry.node.get_parent() == null: entry.node.free()
	return result

func _outputs(target: Node3D) -> Dictionary:
	var outputs: Dictionary = {}
	for child in target.get_children():
		if child is Node3D and child.has_meta(OUTPUT_META): outputs[str(child.get_meta(OUTPUT_META))] = child
	return outputs

func _capture_state(target: Node3D) -> Dictionary:
	var state := {"data": target.get("data"), "materials": target.get("materials").duplicate(),
		"recipe": (target.get_meta(RECIPE_META) if target.has_meta(RECIPE_META) else null), "has_uuid": target.has_meta(UUID_META),
		"uuid": target.get_meta(UUID_META, ""), "outputs": []}
	var outputs := _outputs(target)
	for id in outputs:
		var child: Node3D = outputs[id]
		state.outputs.append({"node": child, "id": id, "data": child.get("data"),
			"transform": child.transform, "materials": child.get("materials").duplicate()})
	return state

func _restore_state(target: Node3D, state: Dictionary) -> void:
	if not is_instance_valid(target): return
	for binding in state.get("bindings", []):
		if not is_instance_valid(binding.node): continue
		if binding.present: binding.node.set_meta(UUID_META, binding.uuid)
		elif binding.node.has_meta(UUID_META): binding.node.remove_meta(UUID_META)
	var wanted: Array = []
	for entry in state.outputs: wanted.append(entry.node)
	for child in _outputs(target).values():
		if not wanted.has(child): target.remove_child(child)
	if state.recipe != null: target.set_meta(RECIPE_META, state.recipe)
	elif target.has_meta(RECIPE_META): target.remove_meta(RECIPE_META)
	if state.has_uuid: target.set_meta(UUID_META, state.uuid)
	elif target.has_meta(UUID_META): target.remove_meta(UUID_META)
	for entry in state.outputs:
		var child: Node3D = entry.node
		child.set("data", entry.data)
		child.set("materials", entry.materials)
		child.transform = entry.transform
		child.set_meta(OUTPUT_META, entry.id)
		if child.get_parent() != target: target.add_child(child, true)
		child.owner = target.owner if target.owner != null else target
	target.set("materials", state.materials)
	target.set("data", state.data)
