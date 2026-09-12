#pragma once

#include "../mesh_edit.hpp"

#include <utility>
#include <vector>

namespace slab {
namespace ops {

MeshFault insert_loop(MeshEdit &p_edit, EdgeId p_edge, float p_t);
MeshFault insert_loops(MeshEdit &p_edit, EdgeId p_edge, const std::vector<float> &p_positions);
// Exact lattice segments in position-major order; each position contributes one
// segment per traversed quad. Open strips stop cleanly at a non-quad face.
MeshFault loop_segments(const Mesh &p_mesh, EdgeId p_edge, const std::vector<float> &p_positions,
		std::vector<std::pair<IVec3, IVec3>> &r_segments);
MeshFault connect_edges(MeshEdit &p_edit, EdgeId p_a, EdgeId p_b);

} // namespace ops
} // namespace slab
