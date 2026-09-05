#pragma once

#include "../mesh_edit.hpp"

#include <vector>

namespace slab {
namespace ops {

MeshFault extrude(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, float p_distance);

} // namespace ops
} // namespace slab
