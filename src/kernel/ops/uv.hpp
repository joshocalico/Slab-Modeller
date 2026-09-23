#pragma once

#include "../mesh_edit.hpp"

#include <vector>
#include <string>

namespace slab {
namespace ops {

struct UvUnwrapResult {
	MeshFault fault;
	std::string refuse_reason;
	bool pinned_conflict = false;
	std::vector<EdgeId> auto_seams;
	int island_count = 0;
	bool atlas_overflow = false;
	int suggested_texture_resolution = 0;

	bool ok() const { return fault.ok(); }
};

struct UvPackResult {
	MeshFault fault;
	std::string refuse_reason;
	bool pinned_conflict = false;
	int island_count = 0;
	bool atlas_overflow = false;
	int suggested_texture_resolution = 0;

	bool ok() const { return fault.ok(); }
};

struct UvProjectionResult {
	MeshFault fault;
	std::string refuse_reason;
	bool pinned_conflict = false;
	bool ok() const { return fault.ok(); }
};

// Restore face-axis projection and clear explicit/atlas transforms. Pinned
// corners refuse the entire selection; seams and materials remain unchanged.
UvProjectionResult reset_uv_projection(MeshEdit &p_edit, const std::vector<FaceId> &p_faces,
		UvAxis p_axis = UvAxis::AUTO);

// Unfold selected faces across unmarked hinges. Marked seams start new islands.
// A non-seam cycle that cannot close continuously is cut and reported in
// auto_seams. UV values are normalized texture coordinates. Pin constraints
// place islands rigidly at the requested density or refuse atomically.
UvUnwrapResult unwrap_uv(MeshEdit &p_edit, const std::vector<FaceId> &p_faces,
		float p_pixels_per_meter, int p_texture_resolution);

// Re-atlas effective corner UVs without unfolding from 3D. Explicit mappings
// retain non-affine shapes. Any pinned corner fixes its entire island in place. Island size
// follows current placement and each face's saved source atlas resolution.
// `p_source_texture_resolution` is a fallback for legacy mappings without that
// value; 0 treats legacy UVs as authored for `p_texture_resolution`.
UvPackResult pack_uv(MeshEdit &p_edit, const std::vector<FaceId> &p_faces,
		int p_texture_resolution, int p_source_texture_resolution = 0);

} // namespace ops
} // namespace slab
