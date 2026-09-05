#pragma once

#include "../mesh_edit.hpp"

#include <vector>

namespace slab {
namespace ops {

FaceId shared_cut_face(const Mesh &p_mesh, VertexId p_a, VertexId p_b);

MeshFault weld(MeshEdit &p_edit, const std::vector<VertexId> &p_verts, float p_radius);
MeshFault collapse(MeshEdit &p_edit, const std::vector<VertexId> &p_verts);
MeshFault connect_vertices(MeshEdit &p_edit, VertexId p_a, VertexId p_b);
MeshFault connect_vertices(MeshEdit &p_edit, const std::vector<VertexId> &p_verts);

} // namespace ops
} // namespace slab
