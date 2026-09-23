@tool
extends Resource

const Step := preload("res://addons/slab/slab_construction_step.gd")
const VERSION := 1

@export var schema_version: int = VERSION
@export var evaluator_version: int = 1
@export var node_uuid: String = Step.new_uuid()
@export var steps: Array[Step] = []
@export var base_deformation: Dictionary = {}
@export var cached_deformation: Dictionary = {}
@export var base_materials: Array[Material] = []
# Persist the last accepted result. Loading a recipe never evaluates it implicitly.
@export var cached_data: PackedByteArray = PackedByteArray()
@export var cached_materials: Array[Material] = []
# Each generated output contains stable id, local transform, data and materials.
@export var cached_instances: Array[Dictionary] = []

func copy_recipe() -> Resource:
	var copy: Resource = get_script().new()
	copy.schema_version = schema_version
	copy.evaluator_version = evaluator_version
	copy.node_uuid = node_uuid
	for step in steps:
		copy.steps.append(step.copy_step())
	# Material resources deliberately keep their identity and paint ownership.
	copy.base_materials.assign(base_materials)
	copy.base_deformation = base_deformation.duplicate()
	copy.cached_deformation = cached_deformation.duplicate()
	copy.cached_data = cached_data.duplicate()
	copy.cached_materials.assign(cached_materials)
	copy.cached_instances.assign(cached_instances.duplicate(true))
	return copy
