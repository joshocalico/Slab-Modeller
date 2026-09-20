#pragma once

#include "../mesh_edit.hpp"

#include <vector>

namespace slab {
namespace ops {

struct UvUnwrapResult {
	MeshFault fault;
	std::vector<EdgeId> auto_seams;
	int island_count = 0;
	bool atlas_overflow = false;
	int suggested_texture_resolution = 0;

	bool ok() const { return fault.ok(); }
};

struct UvPackResult {
	MeshFault fault;
	int island_count = 0;
	bool atlas_overflow = false;
	int suggested_texture_resolution = 0;

	bool ok() const { return fault.ok(); }
};

// Unfold selected faces across unmarked hinges. Marked seams start new islands.
// A non-seam cycle that cannot close continuously is cut and reported in
// auto_seams. UV values are normalized texture coordinates.
UvUnwrapResult unwrap_uv(MeshEdit &p_edit, const std::vector<FaceId> &p_faces,
		float p_pixels_per_meter, int p_texture_resolution);

// Re-atlas existing unwrapped islands without unfolding from 3D. Island size
// follows current placement. `p_source_texture_resolution` is the atlas the
// current UVs were authored for; 0 treats it as `p_texture_resolution`.
UvPackResult pack_uv(MeshEdit &p_edit, const std::vector<FaceId> &p_faces,
		int p_texture_resolution, int p_source_texture_resolution = 0);

} // namespace ops
} // namespace slab
