#pragma once

#include "mesh.hpp"

#include <cstdint>
#include <vector>

namespace slab {

std::vector<uint8_t> serialize(const Mesh &p_mesh);
MeshFault deserialize(const std::vector<uint8_t> &p_bytes, Mesh &r_out);

} // namespace slab
