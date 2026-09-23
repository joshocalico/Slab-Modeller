#pragma once

#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <array>
#include <cstdint>
#include <cmath>
#include <vector>

namespace slab {

// Morph entries use the saved deformation envelope's shape order. Values are
// relative deltas, so splitting or moving base geometry need not bake a pose.
struct MorphDelta {
	godot::Vector3 position;
	godot::Vector3 normal;
	godot::Vector3 tangent;
	float tangent_w = 0.0f;
};

struct SurfaceAttrs {
	enum Flag : uint8_t { UV2 = 1, COLOR = 2, NORMAL = 4, TANGENT = 8, SKIN = 16 };
	uint8_t flags = 0;
	godot::Vector2 uv2;
	godot::Color color = godot::Color(1, 1, 1, 1);
	godot::Vector3 normal;
	std::array<float, 4> tangent = {1, 0, 0, 1};
	std::array<int32_t, 8> bones = {};
	std::array<float, 8> weights = {};
	std::vector<MorphDelta> morphs;
};

inline bool valid_surface_attrs(const SurfaceAttrs &a) {
	if (a.flags > 31) return false;
	if ((a.flags & SurfaceAttrs::UV2) && !a.uv2.is_finite()) return false;
	if (a.flags & SurfaceAttrs::COLOR) {
		for (int i = 0; i < 4; ++i) if (!std::isfinite(a.color[i])) return false;
	}
	if ((a.flags & SurfaceAttrs::NORMAL) && !a.normal.is_finite()) return false;
	if (a.flags & SurfaceAttrs::TANGENT) {
		for (float value : a.tangent) if (!std::isfinite(value)) return false;
	}
	if (a.flags & SurfaceAttrs::SKIN) {
		double total = 0.0;
		for (int i = 0; i < 8; ++i) {
			if (a.bones[i] < 0 || !std::isfinite(a.weights[i]) || a.weights[i] < 0) return false;
			total += a.weights[i];
		}
		if (std::abs(total - 1.0) > .0001) return false;
	}
	for (const MorphDelta &m : a.morphs) {
		if (!m.position.is_finite() || !m.normal.is_finite() || !m.tangent.is_finite() || !std::isfinite(m.tangent_w)) return false;
	}
	return true;
}

} // namespace slab
