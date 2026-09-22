#pragma once

#include "kernel/mesh.hpp"

#include <algorithm>
#include <array>
#include <utility>
#include <vector>

namespace slabtest {

// Exact face geometry and attributes, independent of handles and loop start.
// Winding is significant. A different subdivision is a different signature.
using FacePositions = std::vector<std::array<int32_t, 3>>;
using AttributeSignature = std::array<double, 18>;
using MeshSignature = std::vector<std::pair<FacePositions, AttributeSignature>>;

inline AttributeSignature attribute_signature(const slab::FaceAttrs &a) {
	return { a.uv_scale.x, a.uv_scale.y, a.uv_offset.x, a.uv_offset.y,
		a.uv_rotation, double(a.uv_axis), double(a.material_slot), double(a.smooth),
		double(a.uv_unwrapped), a.uv_u.x, a.uv_u.y, a.uv_u.z,
		a.uv_v.x, a.uv_v.y, a.uv_v.z, a.uv_origin.x, a.uv_origin.y, double(a.uv_texture_resolution) };
}

inline MeshSignature mesh_signature(const slab::Mesh &mesh) {
	MeshSignature result;
	std::vector<slab::FaceId> faces;
	mesh.all_faces(faces);
	for (const slab::FaceId face : faces) {
		std::vector<slab::VertexId> corners;
		mesh.face_corners(face, corners);
		FacePositions points;
		for (const slab::VertexId corner : corners) {
			const slab::IVec3 p = mesh.position_i(corner);
			points.push_back({ p.x, p.y, p.z });
		}
		if (!points.empty()) {
			std::rotate(points.begin(), std::min_element(points.begin(), points.end()), points.end());
		}
		result.emplace_back(std::move(points), attribute_signature(mesh.attrs(face)));
	}
	std::sort(result.begin(), result.end());
	return result;
}

} // namespace slabtest
