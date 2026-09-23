#pragma once

#include "../mesh.hpp"

#include <array>
#include <string>
#include <vector>

namespace slab {
namespace ops {

struct ImportTriangleAttrs {
	uint32_t material_slot = 0;
	bool has_uvs = false;
	std::array<godot::Vector2, 3> uvs;
	std::array<SurfaceAttrs, 3> surface;
};

struct ImportResult {
	Mesh mesh;
	MeshFault fault;
	std::string refuse_reason;
};

// Builds a closed Slab mesh from a triangle soup. Refuses empty, open, or
// non-manifold input without capping holes that have area. Zero-area slivers
// (degenerate faces, or T-junction holes left when emit dropped one) stay
// legal so a closed SlabSolid can round-trip OBJ export → import → Promote.
ImportResult import_from_triangles(const std::vector<IVec3> &p_verts, const std::vector<int32_t> &p_indices,
		const std::vector<ImportTriangleAttrs> &p_attrs = {});

} // namespace ops
} // namespace slab
