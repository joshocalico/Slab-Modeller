@tool
extends RefCounted

# IDs are persisted in material metadata. Append new channels, never reorder them.
const DEFINITIONS := [
	{"name": "Albedo", "texture": &"albedo_texture", "settings": []},
	{"name": "Roughness", "texture": &"roughness_texture", "settings": [&"roughness", &"roughness_texture_channel"]},
	{"name": "Emission", "texture": &"emission_texture", "settings": [&"emission_enabled", &"emission", &"emission_operator"]},
	{"name": "Metallic", "texture": &"metallic_texture", "settings": [&"metallic", &"metallic_texture_channel"]},
	{"name": "Normal", "texture": &"normal_texture", "settings": [&"normal_enabled"]},
	{"name": "Height", "texture": &"heightmap_texture", "settings": [&"heightmap_enabled"]},
]


static func name_for(channel: int) -> String:
	return DEFINITIONS[channel].name


static func texture_for(material: StandardMaterial3D, channel: int) -> Texture2D:
	return material.get(DEFINITIONS[channel].texture) if material != null else null


static func capture(material: StandardMaterial3D, channel: int) -> Dictionary:
	var properties: Dictionary = {}
	if material == null:
		return properties
	var definition: Dictionary = DEFINITIONS[channel]
	properties[definition.texture] = material.get(definition.texture)
	for property: StringName in definition.settings:
		properties[property] = material.get(property)
	return properties


static func restore(material: StandardMaterial3D, properties: Dictionary) -> void:
	for property: StringName in properties:
		material.set(property, properties[property])


static func publish(material: StandardMaterial3D, channel: int, texture: ImageTexture) -> void:
	material.set(DEFINITIONS[channel].texture, texture)
	if texture == null:
		return
	match channel:
		1:
			material.roughness = 1.0
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		2:
			material.emission_enabled = true
			material.emission = Color.WHITE
			material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		3:
			material.metallic = 1.0
			material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		4:
			material.normal_enabled = true
		5:
			material.heightmap_enabled = true


static func has_texture(material: StandardMaterial3D, channel: int) -> bool:
	if texture_for(material, channel) == null:
		return false
	match channel:
		2: return material.emission_enabled
		4: return material.normal_enabled
		5: return material.heightmap_enabled
	return true


static func default_color(material: StandardMaterial3D, channel: int) -> Color:
	match channel:
		1:
			var value: float = material.roughness if material != null else 0.5
			return Color(value, value, value)
		3:
			var value: float = material.metallic if material != null else 0.0
			return Color(value, value, value)
		4: return Color(0.5, 0.5, 1.0)
		5: return Color.BLACK if material != null and material.heightmap_flip_texture else Color.WHITE
	return Color.BLACK


static func paint_color(channel: int, color: Color) -> Color:
	if channel in [1, 3, 5]:
		var value := color.get_luminance()
		return Color(value, value, value, color.a)
	if channel == 4:
		# Godot reconstructs Z from encoded tangent-space XY. Keep XY on the unit disk.
		var xy := Vector2(color.r, color.g) * 2.0 - Vector2.ONE
		if xy.length_squared() > 1.0:
			xy = xy.normalized()
		return Color(xy.x * 0.5 + 0.5, xy.y * 0.5 + 0.5, sqrt(maxf(0.0, 1.0 - xy.length_squared())) * 0.5 + 0.5, color.a)
	return color
