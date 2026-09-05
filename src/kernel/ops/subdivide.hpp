#pragma once

#include "../mesh_edit.hpp"

#include <vector>

namespace slab {
namespace ops {

MeshFault subdivide(MeshEdit &p_edit, const std::vector<FaceId> &p_faces);

} // namespace ops
} // namespace slab
