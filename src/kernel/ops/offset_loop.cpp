#include "offset_loop.hpp"

namespace slab {
namespace ops {

static bool _faces_share_edge(const Mesh &p_mesh, FaceId p_a, FaceId p_b) {
	if (!p_mesh.alive(p_a) || !p_mesh.alive(p_b)) {
		return false;
	}
	std::vector<VertexId> ca;
	std::vector<VertexId> cb;
	p_mesh.face_corners(p_a, ca);
	p_mesh.face_corners(p_b, cb);
	for (size_t i = 0; i < ca.size(); i++) {
		const uint32_t a0 = ca[i].slot;
		const uint32_t a1 = ca[(i + 1) % ca.size()].slot;
		for (size_t j = 0; j < cb.size(); j++) {
			const uint32_t b0 = cb[j].slot;
			const uint32_t b1 = cb[(j + 1) % cb.size()].slot;
			if ((a0 == b0 && a1 == b1) || (a0 == b1 && a1 == b0)) {
				return true;
			}
		}
	}
	return false;
}

MeshFault extrude(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, float p_distance) {
	if (p_faces.empty()) {
		MeshFault f;
		f.code = MeshError::DEGENERATE_FACE;
		return f;
	}
	const Mesh &src = p_edit.scratch();
	for (const FaceId id : p_faces) {
		if (!src.alive(id)) {
			MeshFault f;
			f.code = MeshError::STALE_HANDLE;
			return f;
		}
	}
	for (size_t i = 0; i < p_faces.size(); i++) {
		for (size_t j = i + 1; j < p_faces.size(); j++) {
			if (_faces_share_edge(src, p_faces[i], p_faces[j])) {
				MeshFault f;
				f.code = MeshError::ADJACENT_SELECTION;
				return f;
			}
		}
	}
	for (const FaceId id : p_faces) {
		const godot::Vector3 normal = p_edit.scratch().face_normal(id);
		const FaceId cap = p_edit.lift_loop(id);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
		std::vector<VertexId> corners;
		p_edit.scratch().face_corners(cap, corners);
		for (const VertexId v : corners) {
			const godot::Vector3 next = p_edit.scratch().position(v) + normal * p_distance;
			IVec3 q;
			if (!quantize(next, q)) {
				MeshFault f;
				f.code = MeshError::COORD_OUT_OF_RANGE;
				return f;
			}
			p_edit.move_vertex(v, q);
		}
	}
	return p_edit.last_fault();
}

} // namespace ops
} // namespace slab
