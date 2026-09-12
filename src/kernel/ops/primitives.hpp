#pragma once

#include "../mesh_edit.hpp"

#include <godot_cpp/core/math_defs.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace slab {
namespace ops {

static constexpr int STAIR_STEPS_MIN = 1;
static constexpr int STAIR_STEPS_MAX = 32;
static constexpr int CYLINDER_SIDES_MIN = 3;
static constexpr int CYLINDER_SIDES_MAX = 32;
static constexpr int ARCH_SEGMENTS_MIN = 4;
static constexpr int ARCH_SEGMENTS_MAX = 32;
static constexpr double ARCH_ARC_MIN = Math_PI / 12.0;
static constexpr double ARCH_ARC_MAX = Math_TAU;

MeshFault box(MeshEdit &p_edit, const godot::Vector3 &p_size);
MeshFault plane(MeshEdit &p_edit, const godot::Vector2 &p_size, float p_thickness);
MeshFault stair(MeshEdit &p_edit, const godot::Vector3 &p_size, int p_steps);
MeshFault cylinder(MeshEdit &p_edit, float p_radius, float p_height, int p_sides);
// p_arc is a double so that Math_PI * 0.5 - p_arc * 0.5 cancels exactly at 180 degrees,
// which is what keeps the half circle lattice-identical to the old arch. float32 loses it.
MeshFault arch(MeshEdit &p_edit, float p_span, float p_depth, int p_segments, float p_thickness, double p_arc);
MeshFault prism(MeshEdit &p_edit, const IVec3 *p_loop, int p_count, int32_t p_height);
MeshFault sweep(MeshEdit &p_edit, const IVec3 *p_path, int p_path_count, const IVec3 *p_profile, int p_profile_count, bool p_closed);

} // namespace ops
} // namespace slab
