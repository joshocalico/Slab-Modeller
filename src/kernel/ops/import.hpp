#pragma once

#include "../mesh.hpp"

#include <string>
#include <vector>

namespace slab {
namespace ops {

struct ImportResult {
	Mesh mesh;
	MeshFault fault;
	std::string refuse_reason;
};

// Builds a closed Slab mesh from a triangle soup. Refuses empty, open, or
// non-manifold input without capping holes or otherwise repairing the soup.
ImportResult import_from_triangles(const std::vector<IVec3> &p_verts, const std::vector<int32_t> &p_indices);

} // namespace ops
} // namespace slab
