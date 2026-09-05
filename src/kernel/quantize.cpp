#include "quantize.hpp"

#include "mesh.hpp"

#include <godot_cpp/core/math.hpp>

#include <vector>

namespace slab {

bool quantize(const godot::Vector3 &p_p, IVec3 &r_out) {
	if (!godot::Math::is_finite(p_p.x) || !godot::Math::is_finite(p_p.y) || !godot::Math::is_finite(p_p.z)) {
		return false;
	}
	const int64_t x = int64_t(godot::Math::round(double(p_p.x) * double(LATTICE)));
	const int64_t y = int64_t(godot::Math::round(double(p_p.y) * double(LATTICE)));
	const int64_t z = int64_t(godot::Math::round(double(p_p.z) * double(LATTICE)));
	if (x < -COORD_LIMIT || x > COORD_LIMIT || y < -COORD_LIMIT || y > COORD_LIMIT || z < -COORD_LIMIT || z > COORD_LIMIT) {
		return false;
	}
	r_out = IVec3{ int32_t(x), int32_t(y), int32_t(z) };
	return true;
}

godot::Vector3 dequantize(const IVec3 &p_p) {
	return godot::Vector3(float(p_p.x) / float(LATTICE), float(p_p.y) / float(LATTICE), float(p_p.z) / float(LATTICE));
}

__int128 det3(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c) {
	const __int128 ax = p_a.x, ay = p_a.y, az = p_a.z;
	const __int128 bx = p_b.x, by = p_b.y, bz = p_b.z;
	const __int128 cx = p_c.x, cy = p_c.y, cz = p_c.z;
	return ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx);
}

int orient3d(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c, const IVec3 &p_d) {
	const IVec3 ba{ p_b.x - p_a.x, p_b.y - p_a.y, p_b.z - p_a.z };
	const IVec3 ca{ p_c.x - p_a.x, p_c.y - p_a.y, p_c.z - p_a.z };
	const IVec3 da{ p_d.x - p_a.x, p_d.y - p_a.y, p_d.z - p_a.z };
	const __int128 d = det3(ba, ca, da);
	if (d > 0) {
		return 1;
	}
	if (d < 0) {
		return -1;
	}
	return 0;
}

__int128 signed_volume_6x(const Mesh &p_mesh) {
	__int128 acc = 0;
	std::vector<VertexId> corners;
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	for (const FaceId id : faces) {
		p_mesh.face_corners(id, corners);
		if (corners.size() < 3) {
			continue;
		}
		const IVec3 a = p_mesh.position_i(corners[0]);
		for (size_t i = 1; i + 1 < corners.size(); i++) {
			const IVec3 b = p_mesh.position_i(corners[i]);
			const IVec3 c = p_mesh.position_i(corners[i + 1]);
			acc += det3(a, b, c);
		}
	}
	return acc;
}

} // namespace slab
