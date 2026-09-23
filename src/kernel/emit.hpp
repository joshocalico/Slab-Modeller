#pragma once

#include "mesh.hpp"

#include <cstdint>
#include <vector>

namespace slab {

struct EmitOut {
	std::vector<godot::Vector3> verts;
	std::vector<godot::Vector3> normals;
	std::vector<godot::Vector2> uvs;
	std::vector<float> tangents;
	std::vector<int32_t> indices;
	std::vector<FaceId> provenance;
	std::vector<uint32_t> slots;
};

void face_uv_points(const Mesh &p_mesh, FaceId p_face, std::vector<godot::Vector2> &r_uvs);

bool face_uv_at_point(const Mesh &p_mesh, FaceId p_face, const godot::Vector3 &p_point, godot::Vector2 &r_uv);

void emit_arrays(const Mesh &p_mesh, EmitOut &r_out);

} // namespace slab
