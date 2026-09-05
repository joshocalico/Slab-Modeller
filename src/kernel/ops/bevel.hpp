#pragma once

#include "../mesh_edit.hpp"

#include <vector>

namespace slab {
namespace ops {

MeshFault bevel(MeshEdit &p_edit, const std::vector<EdgeId> &p_edges, float p_amount);

} // namespace ops
} // namespace slab
