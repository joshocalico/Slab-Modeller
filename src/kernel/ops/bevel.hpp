#pragma once

#include "../mesh_edit.hpp"

#include <vector>

namespace slab {
namespace ops {

static constexpr int BEVEL_SEGMENTS_MIN = 1;
static constexpr int BEVEL_SEGMENTS_MAX = 16;

MeshFault bevel(MeshEdit &p_edit, const std::vector<EdgeId> &p_edges, float p_amount);
MeshFault bevel(MeshEdit &p_edit, const std::vector<EdgeId> &p_edges, float p_amount, int p_segments);

} // namespace ops
} // namespace slab
