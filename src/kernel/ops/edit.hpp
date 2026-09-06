#pragma once

#include "../mesh_edit.hpp"

#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace slab {
namespace ops {

MeshFault set_face_material(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, uint32_t p_slot);
MeshFault merge_faces(MeshEdit &p_edit, const std::vector<FaceId> &p_faces);
MeshFault dissolve_edges(MeshEdit &p_edit, const std::vector<EdgeId> &p_edges);
MeshFault move_vertices(MeshEdit &p_edit, const std::vector<VertexId> &p_verts, const godot::Vector3 &p_delta);
MeshFault center_pivot(MeshEdit &p_edit);
MeshFault snap_to_grid(MeshEdit &p_edit, float p_step);
MeshFault mirror(MeshEdit &p_edit, const godot::Vector3 &p_scale);

} // namespace ops
} // namespace slab
