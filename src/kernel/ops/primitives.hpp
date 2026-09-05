#pragma once

#include "../mesh_edit.hpp"

#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace slab {
namespace ops {

MeshFault box(MeshEdit &p_edit, const godot::Vector3 &p_size);
MeshFault plane(MeshEdit &p_edit, const godot::Vector2 &p_size, float p_thickness);
MeshFault stair(MeshEdit &p_edit, const godot::Vector3 &p_size, int p_steps);
MeshFault cylinder(MeshEdit &p_edit, float p_radius, float p_height, int p_sides);
MeshFault arch(MeshEdit &p_edit, const godot::Vector3 &p_size, int p_segments, float p_thickness);
MeshFault prism(MeshEdit &p_edit, const IVec3 *p_loop, int p_count, int32_t p_height);
MeshFault sweep(MeshEdit &p_edit, const IVec3 *p_path, int p_path_count, const IVec3 *p_profile, int p_profile_count, bool p_closed);

} // namespace ops
} // namespace slab
