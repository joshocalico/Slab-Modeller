#pragma once
#include "mesh_edit.hpp"
namespace slab {
// Resample retained faces against the actual source triangulation. New cut or
// bevel faces inherit deformation/colour from the nearest source surface and
// retain the face mapping chosen by the operation.
void transfer_rebuilt_attributes(MeshEdit &p_edit, const std::vector<const Mesh *> &p_sources,
								 bool p_restore_faces = true);
bool has_authored_attributes(const Mesh &p_mesh);
} // namespace slab
