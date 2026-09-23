@tool
extends Resource

## A replay instruction. Parameters are checked at the recipe boundary, before
## any live solid changes. Picked IDs are valid only for their exact input mesh.
enum Kind { PRIMITIVE, MESH_SOURCE, BEVEL, BOOLEAN, ARRAY_LINEAR, ARRAY_RADIAL, CHECKPOINT }
enum SelectionBinding { ALL_EDGES, PINNED_EDGES, MIN_CORNER_X_EDGE }

@export var id: String = new_uuid()
@export var kind: Kind = Kind.PRIMITIVE
@export var enabled: bool = true
@export var parameters: Dictionary = {"method": &"make_box", "args": [Vector3.ONE]}
@export var selection_binding: SelectionBinding = SelectionBinding.MIN_CORNER_X_EDGE
@export var picked_edges: PackedInt64Array = PackedInt64Array()
@export var input_fingerprint: String = ""
@export var operand_uuid: String = ""

static func new_uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20)]

static func fingerprint(data: PackedByteArray) -> String:
	return data.hex_encode().sha256_text()

func copy_step() -> Resource:
	return duplicate(true)
