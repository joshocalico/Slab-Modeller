#pragma once

#include "../mesh_edit.hpp"

#include <vector>

namespace slab {
namespace ops {

MeshFault insert_loop(MeshEdit &p_edit, EdgeId p_edge, float p_t);
MeshFault connect_edges(MeshEdit &p_edit, EdgeId p_a, EdgeId p_b);

} // namespace ops
} // namespace slab
