#pragma once

#include "../mesh_edit.hpp"

#include <vector>

namespace slab {
namespace ops {

bool faces_alive(const Mesh &p_mesh, const std::vector<FaceId> &p_faces);
bool faces_share_an_edge(const Mesh &p_mesh, const std::vector<FaceId> &p_faces);

MeshFault inset(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, float p_amount);
MeshFault delete_faces(MeshEdit &p_edit, const std::vector<FaceId> &p_faces);
MeshFault flip_faces(MeshEdit &p_edit, const std::vector<FaceId> &p_faces);

} // namespace ops
} // namespace slab
