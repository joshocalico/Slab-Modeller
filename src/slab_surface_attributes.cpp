#include "slab_surface_attributes.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <cmath>
namespace godot {
bool decode_slab_surface_attributes(const Dictionary &input, int64_t count,
		std::vector<slab::SurfaceAttrs> &output, String &error) {
	const auto refuse = [&](const String &message) { error = message; return false; };
	struct Field { const char *name; Variant::Type type; int width; };
	const Field fields[] = {
		{"uv2",Variant::PACKED_VECTOR2_ARRAY,1}, {"colors",Variant::PACKED_COLOR_ARRAY,1},
		{"normals",Variant::PACKED_VECTOR3_ARRAY,1}, {"tangents",Variant::PACKED_FLOAT32_ARRAY,4},
		{"bones",Variant::PACKED_INT32_ARRAY,8}, {"weights",Variant::PACKED_FLOAT32_ARRAY,8},
		{"uv2_present",Variant::PACKED_BYTE_ARRAY,1}, {"color_present",Variant::PACKED_BYTE_ARRAY,1},
		{"normal_present",Variant::PACKED_BYTE_ARRAY,1}, {"tangent_present",Variant::PACKED_BYTE_ARRAY,1},
		{"skin_present",Variant::PACKED_BYTE_ARRAY,1}
	};
	for (const Field &field : fields) {
		if (!input.has(field.name)) continue;
		const Variant value = input[field.name];
		if (value.get_type() != field.type) return refuse(String("Wrong array type for ") + field.name);
		int64_t size = 0;
		switch (field.type) {
			case Variant::PACKED_VECTOR2_ARRAY: size = PackedVector2Array(value).size(); break;
			case Variant::PACKED_VECTOR3_ARRAY: size = PackedVector3Array(value).size(); break;
			case Variant::PACKED_COLOR_ARRAY: size = PackedColorArray(value).size(); break;
			case Variant::PACKED_FLOAT32_ARRAY: size = PackedFloat32Array(value).size(); break;
			case Variant::PACKED_INT32_ARRAY: size = PackedInt32Array(value).size(); break;
			case Variant::PACKED_BYTE_ARRAY: size = PackedByteArray(value).size(); break;
			default: break;
		}
		if (size != 0 && size != count * field.width) return refuse(String("Wrong array length for ") + field.name);
	}
	const PackedVector2Array uv2 = input.get("uv2", PackedVector2Array());
	const PackedColorArray colors = input.get("colors", PackedColorArray());
	const PackedVector3Array normals = input.get("normals", PackedVector3Array());
	const PackedFloat32Array tangents = input.get("tangents", PackedFloat32Array());
	const PackedInt32Array bones = input.get("bones", PackedInt32Array());
	const PackedFloat32Array weights = input.get("weights", PackedFloat32Array());
	if (bones.is_empty() != weights.is_empty()) return refuse("Skin requires bones and weights together.");
	const char *masks[] = {"uv2_present", "color_present", "normal_present", "tangent_present", "skin_present"};
	const bool channels[] = {!uv2.is_empty(), !colors.is_empty(), !normals.is_empty(), !tangents.is_empty(), !bones.is_empty()};
	PackedByteArray presence[5];
	for (int k = 0; k < 5; ++k) {
		presence[k] = input.get(masks[k], PackedByteArray());
		for (int64_t i = 0; i < presence[k].size(); ++i)
			if (presence[k][i] > 1 || (presence[k][i] && !channels[k])) return refuse("Invalid attribute presence mask.");
	}
	if (input.has("blend_shapes") && Variant(input["blend_shapes"]).get_type() != Variant::ARRAY) return refuse("Blend shapes must be an array.");
	const Array shapes = input.get("blend_shapes", Array());
	std::vector<PackedVector3Array> positions, shape_normals;
	std::vector<PackedFloat32Array> shape_tangents;
	for (int64_t k = 0; k < shapes.size(); ++k) {
		if (shapes[k].get_type() != Variant::DICTIONARY) return refuse("Invalid blend shape record.");
		const Dictionary shape = shapes[k];
		for (const char *key : {"positions", "normals", "tangents"}) {
			if (!shape.has(key)) continue;
			const Variant::Type type = String(key) == "tangents" ? Variant::PACKED_FLOAT32_ARRAY : Variant::PACKED_VECTOR3_ARRAY;
			if (Variant(shape[key]).get_type() != type) return refuse("Invalid blend shape array type.");
		}
		positions.push_back(shape.get("positions", PackedVector3Array()));
		shape_normals.push_back(shape.get("normals", PackedVector3Array()));
		shape_tangents.push_back(shape.get("tangents", PackedFloat32Array()));
		if (positions.back().size() != count || (!shape_normals.back().is_empty() && shape_normals.back().size() != count)
				|| (!shape_tangents.back().is_empty() && shape_tangents.back().size() != count*4)) return refuse("Invalid blend shape array length.");
	}
	std::vector<slab::SurfaceAttrs> candidate(size_t(count), slab::SurfaceAttrs{});
	for (int64_t i = 0; i < count; ++i) {
		auto &a = candidate[size_t(i)];
		for (int k = 0; k < 5; ++k) if (channels[k] && (presence[k].is_empty() || presence[k][i])) a.flags |= 1 << k;
		if (a.flags & slab::SurfaceAttrs::UV2) a.uv2 = uv2[i];
		if (a.flags & slab::SurfaceAttrs::COLOR) a.color = colors[i];
		if (a.flags & slab::SurfaceAttrs::NORMAL) a.normal = normals[i];
		if (a.flags & slab::SurfaceAttrs::TANGENT) for (int k = 0; k < 4; ++k) a.tangent[k] = tangents[i*4+k];
		if (a.flags & slab::SurfaceAttrs::SKIN) {
			double sum = 0;
			for (int k = 0; k < 8; ++k) {
				a.bones[k] = bones[i*8+k]; a.weights[k] = weights[i*8+k];
				if (!std::isfinite(a.weights[k]) || a.weights[k] < 0 || a.bones[k] < 0) return refuse("Invalid skin influence.");
				sum += a.weights[k];
			}
			if (!std::isfinite(sum) || sum <= 0) return refuse("Skin weights must have positive total weight.");
			for (float &weight : a.weights) weight /= sum;
		}
		a.morphs.resize(size_t(shapes.size()));
		for (size_t k = 0; k < a.morphs.size(); ++k) {
			auto &m = a.morphs[k]; m.position = positions[k][i];
			if (!shape_normals[k].is_empty()) m.normal = shape_normals[k][i];
			if (!shape_tangents[k].is_empty()) {
				for (int c = 0; c < 3; ++c) m.tangent[c] = shape_tangents[k][i*4+c];
				m.tangent_w = shape_tangents[k][i*4+3];
			}
		}
		if (!slab::valid_surface_attrs(a)) return refuse("Non-finite or malformed surface attributes.");
	}
	output = std::move(candidate);
	return true;
}
}
