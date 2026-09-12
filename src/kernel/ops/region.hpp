#pragma once

#include "../mesh_edit.hpp"

#include <vector>

namespace slab {
namespace ops {

// Region edits accept one edge-connected face patch smaller than the whole mesh.
// Extrude uses one area-weighted translation. Inset requires a coplanar patch.
// Rebuilding preserves cap topology and attributes but invalidates old handles.
MeshFault extrude_region(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, float p_distance);
MeshFault inset_region(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, float p_amount);

} // namespace ops
} // namespace slab
