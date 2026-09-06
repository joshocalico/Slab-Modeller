#pragma once

#include "mesh.hpp"

#include <cstdint>
#include <vector>

namespace slab {

struct EmitOut {
	std::vector<godot::Vector3> verts;
	std::vector<godot::Vector3> normals;
	std::vector<godot::Vector2> uvs;
	std::vector<int32_t> indices;
	std::vector<FaceId> provenance;
	std::vector<uint32_t> slots;
};

void emit_arrays(const Mesh &p_mesh, EmitOut &r_out);

} // namespace slab
