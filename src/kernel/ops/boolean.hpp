#pragma once

#include "../mesh_edit.hpp"

namespace slab {
namespace ops {

MeshFault boolean(MeshEdit &p_edit, const Mesh &p_other, int p_mode);

} // namespace ops
} // namespace slab
