#include "bridge.hpp"

#include "loop.hpp"

namespace slab {
namespace ops {

namespace {

MeshFault _bad(MeshError p_code, uint32_t p_slot = INVALID_IDX) {
	MeshFault f;
	f.code = p_code;
	f.slot = p_slot;
	return f;
}

} // namespace

MeshFault bridge(MeshEdit &p_edit, EdgeId p_a, EdgeId p_b) {
	const Mesh &src = p_edit.scratch();
	if (!src.alive(p_a) || !src.alive(p_b)) {
		return _bad(MeshError::STALE_HANDLE, src.alive(p_a) ? p_b.slot : p_a.slot);
	}
	if (p_a.slot == p_b.slot) {
		return _bad(MeshError::NO_INTERSECTION, p_a.slot);
	}
	FaceId a_left;
	FaceId a_right;
	FaceId b_left;
	FaceId b_right;
	src.edge_faces(p_a, a_left, a_right);
	src.edge_faces(p_b, b_left, b_right);
	if (!src.alive(a_left) || !src.alive(a_right) || !src.alive(b_left) || !src.alive(b_right)) {
		return _bad(MeshError::NOT_CLOSED, p_a.slot);
	}
	const uint32_t lhs[2] = { a_left.slot, a_right.slot };
	const uint32_t rhs[2] = { b_left.slot, b_right.slot };
	for (int i = 0; i < 2; i++) {
		for (int j = 0; j < 2; j++) {
			if (lhs[i] == rhs[j]) {
				return connect_edges(p_edit, p_a, p_b);
			}
		}
	}
	// Every edge of a closed two manifold already carries two faces. A connecting face spanning
	// two edges that share none would hand one of them a third and pinch the solid open, so the
	// only bridge that keeps the result closed is the one across a face the two edges already share.
	return _bad(MeshError::NO_INTERSECTION, p_a.slot);
}

} // namespace ops
} // namespace slab
