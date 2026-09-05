#pragma once

#include "handles.hpp"

#include <godot_cpp/variant/vector3.hpp>

namespace slab {

static constexpr int32_t LATTICE = 1024;
static constexpr int32_t COORD_LIMIT = 1 << 20;

struct IVec3 {
	int32_t x = 0;
	int32_t y = 0;
	int32_t z = 0;

	bool operator==(const IVec3 &p_o) const {
		return x == p_o.x && y == p_o.y && z == p_o.z;
	}

	bool operator!=(const IVec3 &p_o) const {
		return !(*this == p_o);
	}

	bool operator<(const IVec3 &p_o) const {
		if (x != p_o.x) {
			return x < p_o.x;
		}
		if (y != p_o.y) {
			return y < p_o.y;
		}
		return z < p_o.z;
	}
};

bool quantize(const godot::Vector3 &p_p, IVec3 &r_out);
godot::Vector3 dequantize(const IVec3 &p_p);
int orient3d(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c, const IVec3 &p_d);
__int128 det3(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c);

class Mesh;
__int128 signed_volume_6x(const Mesh &p_mesh);

} // namespace slab
