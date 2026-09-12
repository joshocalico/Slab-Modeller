#pragma once

#include "quantize.hpp"

#include <cstdint>
#include <vector>

namespace slab {

// Fills r_indices with triples of loop indices. Winding matches emit: clockwise
// against the outward normal (Godot front faces). Convex loops fan; reflex n-gons
// are ear-clipped so a triangle cannot cover the exterior.
void triangulate_loop(const std::vector<IVec3> &p_loop, std::vector<int32_t> &r_indices);

} // namespace slab
