#pragma once

#include "../mesh_edit.hpp"

namespace slab {
namespace ops {

enum class PlaneSide : uint8_t {
	NEGATIVE = 0,
	POSITIVE = 1,
};

// Retains one closed half of p_edit and closes every section loop with caps.
// p_normal is an exact integer plane normal; it need not be normalized.
MeshFault plane_cut(MeshEdit &p_edit, const IVec3 &p_origin, const IVec3 &p_normal,
		PlaneSide p_keep, const FaceAttrs &p_cap_attrs = FaceAttrs{});

} // namespace ops
} // namespace slab
