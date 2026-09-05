#include "bevel.hpp"

#include <vector>

namespace slab {
namespace ops {

namespace {

MeshFault _bad(MeshError p_code, uint32_t p_slot = INVALID_IDX) {
	MeshFault f;
	f.code = p_code;
	f.slot = p_slot;
	return f;
}

void _poison(MeshEdit &p_edit) {
	p_edit.move_vertex(VertexId{}, IVec3{});
}

bool _collinear(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c) {
	const int64_t bx = int64_t(p_b.x) - p_a.x;
	const int64_t by = int64_t(p_b.y) - p_a.y;
	const int64_t bz = int64_t(p_b.z) - p_a.z;
	const int64_t cx = int64_t(p_c.x) - p_a.x;
	const int64_t cy = int64_t(p_c.y) - p_a.y;
	const int64_t cz = int64_t(p_c.z) - p_a.z;
	return by * cz - bz * cy == 0 && bz * cx - bx * cz == 0 && bx * cy - by * cx == 0;
}

int64_t _gcd(int64_t p_a, int64_t p_b) {
	while (p_b != 0) {
		const int64_t rest = p_a % p_b;
		p_a = p_b;
		p_b = rest;
	}
	return p_a;
}

bool _offset_along(const IVec3 &p_from, const IVec3 &p_to, int32_t p_dist, IVec3 &r_out) {
	const godot::Vector3 from = dequantize(p_from);
	const godot::Vector3 to = dequantize(p_to);
	const float span = (to - from).length();
	if (span == 0.0f) {
		return false;
	}
	float reach = float(p_dist) / float(LATTICE);
	if (reach > span * 0.45f) {
		reach = span * 0.45f;
	}
	if (!quantize(from + (to - from) * (reach / span), r_out)) {
		return false;
	}
	return !(r_out == p_from) && !(r_out == p_to);
}

int32_t _span_cap(const IVec3 &p_from, const IVec3 &p_to) {
	const float span = (dequantize(p_to) - dequantize(p_from)).length();
	return int32_t(double(span) * 0.45 * double(LATTICE) + 0.5);
}

int32_t _face_rail_cap(const Mesh &p_mesh, EdgeId p_edge, FaceId p_face) {
	std::vector<VertexId> corners;
	std::vector<EdgeId> edges;
	p_mesh.face_corners(p_face, corners);
	p_mesh.face_edges(p_face, edges);
	const int n = int(corners.size());
	if (n < 3 || int(edges.size()) != n) {
		return 0;
	}
	int at = -1;
	for (int k = 0; k < n; k++) {
		if (edges[k].slot == p_edge.slot) {
			at = k;
		}
	}
	if (at < 0) {
		return 0;
	}
	const int32_t head = _span_cap(p_mesh.position_i(corners[at]), p_mesh.position_i(corners[(at + n - 1) % n]));
	const int32_t tail = _span_cap(p_mesh.position_i(corners[(at + 1) % n]), p_mesh.position_i(corners[(at + 2) % n]));
	return head < tail ? head : tail;
}

bool _midway_lattice(const IVec3 &p_a, const IVec3 &p_b, IVec3 &r_out) {
	const int64_t dx = int64_t(p_b.x) - p_a.x;
	const int64_t dy = int64_t(p_b.y) - p_a.y;
	const int64_t dz = int64_t(p_b.z) - p_a.z;
	const int64_t step = _gcd(_gcd(dx < 0 ? -dx : dx, dy < 0 ? -dy : dy), dz < 0 ? -dz : dz);
	if (step < 2) {
		return false;
	}
	const int64_t half = step / 2;
	r_out = IVec3{
		int32_t(int64_t(p_a.x) + half * dx / step),
		int32_t(int64_t(p_a.y) + half * dy / step),
		int32_t(int64_t(p_a.z) + half * dz / step)
	};
	return !(r_out == p_a) && !(r_out == p_b);
}

struct SidePlan {
	FaceId face;
	EdgeId rail_u;
	EdgeId rail_v;
	IVec3 cut_u;
	IVec3 cut_v;
	VertexId made_u;
	VertexId made_v;
};

struct BevelPlan {
	EdgeId edge;
	VertexId u;
	VertexId v;
	IVec3 u_seat;
	IVec3 v_seat;
	SidePlan side[2];
};

MeshFault _plan_side(const Mesh &p_mesh, EdgeId p_edge, FaceId p_face, VertexId p_u, int32_t p_dist, SidePlan &r_out) {
	std::vector<VertexId> corners;
	std::vector<EdgeId> edges;
	p_mesh.face_corners(p_face, corners);
	p_mesh.face_edges(p_face, edges);
	const int n = int(corners.size());
	if (n < 3 || int(edges.size()) != n) {
		return _bad(MeshError::LOOP_TOO_SHORT, p_face.slot);
	}
	int at = -1;
	for (int k = 0; k < n; k++) {
		if (edges[k].slot == p_edge.slot) {
			at = k;
		}
	}
	if (at < 0) {
		return _bad(MeshError::INVALID_SELECTION, p_face.slot);
	}
	const VertexId head = corners[at];
	IVec3 seat_head;
	IVec3 seat_tail;
	if (!_offset_along(p_mesh.position_i(head), p_mesh.position_i(corners[(at + n - 1) % n]), p_dist, seat_head)) {
		return _bad(MeshError::DEGENERATE_FACE, p_face.slot);
	}
	if (!_offset_along(p_mesh.position_i(corners[(at + 1) % n]), p_mesh.position_i(corners[(at + 2) % n]), p_dist, seat_tail)) {
		return _bad(MeshError::DEGENERATE_FACE, p_face.slot);
	}
	const EdgeId rail_head = edges[(at + n - 1) % n];
	const EdgeId rail_tail = edges[(at + 1) % n];

	r_out.face = p_face;
	if (head.slot == p_u.slot) {
		r_out.rail_u = rail_head;
		r_out.cut_u = seat_head;
		r_out.rail_v = rail_tail;
		r_out.cut_v = seat_tail;
	} else {
		r_out.rail_u = rail_tail;
		r_out.cut_u = seat_tail;
		r_out.rail_v = rail_head;
		r_out.cut_v = seat_head;
	}
	return MeshFault{};
}

MeshFault _plan_bevel(const Mesh &p_mesh, EdgeId p_edge, int32_t p_dist, BevelPlan &r_plan) {
	if (!p_mesh.alive(p_edge)) {
		return _bad(MeshError::STALE_HANDLE, p_edge.slot);
	}
	FaceId left;
	FaceId right;
	p_mesh.edge_faces(p_edge, left, right);
	if (!p_mesh.alive(left) || !p_mesh.alive(right)) {
		return _bad(MeshError::NOT_CLOSED, p_edge.slot);
	}
	VertexId u;
	VertexId v;
	p_mesh.edge_vertices(p_edge, u, v);
	if (!p_mesh.alive(u) || !p_mesh.alive(v)) {
		return _bad(MeshError::STALE_HANDLE, p_edge.slot);
	}
	std::vector<EdgeId> ring;
	p_mesh.vertex_edges(u, ring);
	if (ring.size() != 3) {
		return _bad(MeshError::NON_MANIFOLD_VERTEX, u.slot);
	}
	p_mesh.vertex_edges(v, ring);
	if (ring.size() != 3) {
		return _bad(MeshError::NON_MANIFOLD_VERTEX, v.slot);
	}

	r_plan.edge = p_edge;
	r_plan.u = u;
	r_plan.v = v;
	int32_t dist = p_dist;
	const int32_t left_cap = _face_rail_cap(p_mesh, p_edge, left);
	const int32_t right_cap = _face_rail_cap(p_mesh, p_edge, right);
	if (left_cap < dist) {
		dist = left_cap;
	}
	if (right_cap < dist) {
		dist = right_cap;
	}
	if (dist < 2) {
		return _bad(MeshError::DEGENERATE_FACE, p_edge.slot);
	}
	const FaceId faces[2] = { left, right };
	for (int i = 0; i < 2; i++) {
		const MeshFault planned = _plan_side(p_mesh, p_edge, faces[i], u, dist, r_plan.side[i]);
		if (!planned.ok()) {
			return planned;
		}
	}
	const uint32_t rails[4] = {
		r_plan.side[0].rail_u.slot,
		r_plan.side[0].rail_v.slot,
		r_plan.side[1].rail_u.slot,
		r_plan.side[1].rail_v.slot
	};
	for (int i = 0; i < 4; i++) {
		for (int j = i + 1; j < 4; j++) {
			if (rails[i] == rails[j]) {
				return _bad(MeshError::DEGENERATE_FACE, p_edge.slot);
			}
		}
	}

	const IVec3 au = r_plan.side[0].cut_u;
	const IVec3 av = r_plan.side[0].cut_v;
	const IVec3 bu = r_plan.side[1].cut_u;
	const IVec3 bv = r_plan.side[1].cut_v;
	if (_collinear(au, bu, av) || orient3d(au, bu, av, bv) != 0) {
		return _bad(MeshError::DEGENERATE_FACE, p_edge.slot);
	}
	if (!_midway_lattice(au, bu, r_plan.u_seat) || !_midway_lattice(av, bv, r_plan.v_seat)) {
		return _bad(MeshError::DEGENERATE_FACE, p_edge.slot);
	}
	return MeshFault{};
}

MeshFault _retire_seat(MeshEdit &p_edit, VertexId p_seat) {
	std::vector<EdgeId> ring;
	p_edit.scratch().vertex_edges(p_seat, ring);
	if (ring.size() != 2) {
		return _bad(MeshError::NON_MANIFOLD_VERTEX, p_seat.slot);
	}
	for (const EdgeId id : ring) {
		VertexId keep;
		VertexId kill;
		p_edit.scratch().edge_vertices(id, keep, kill);
		if (kill.slot == p_seat.slot) {
			return p_edit.collapse_edge(id);
		}
	}
	VertexId keep;
	VertexId kill;
	p_edit.scratch().edge_vertices(ring[0], keep, kill);
	p_edit.move_vertex(keep, p_edit.scratch().position_i(kill));
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	return p_edit.collapse_edge(ring[0]);
}

MeshFault _apply_bevel(MeshEdit &p_edit, BevelPlan &r_plan) {
	for (int i = 0; i < 2; i++) {
		SidePlan &side = r_plan.side[i];
		side.made_u = p_edit.split_edge(side.rail_u, side.cut_u);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
		side.made_v = p_edit.split_edge(side.rail_v, side.cut_v);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	for (int i = 0; i < 2; i++) {
		p_edit.split_face(r_plan.side[i].face, r_plan.side[i].made_u, r_plan.side[i].made_v);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	p_edit.move_vertex(r_plan.u, r_plan.u_seat);
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	p_edit.move_vertex(r_plan.v, r_plan.v_seat);
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	const MeshFault dissolved = p_edit.dissolve_edge(r_plan.edge);
	if (!dissolved.ok()) {
		return dissolved;
	}
	// The dissolve leaves the two seats as collinear midpoints of the chamfer's long sides, which
	// makes face_normal read zero off its first three corners. Retire them to land a clean quad.
	const MeshFault first = _retire_seat(p_edit, r_plan.u);
	if (!first.ok()) {
		return first;
	}
	return _retire_seat(p_edit, r_plan.v);
}

} // namespace

MeshFault bevel(MeshEdit &p_edit, const std::vector<EdgeId> &p_edges, float p_amount) {
	if (p_edges.empty() || !(p_amount > 0.0f)) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const int32_t dist = int32_t(double(p_amount) * double(LATTICE) + 0.5);
	if (dist < 2) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	for (const EdgeId id : p_edges) {
		if (!p_edit.scratch().alive(id)) {
			return _bad(MeshError::STALE_HANDLE, id.slot);
		}
	}
	for (size_t i = 0; i < p_edges.size(); i++) {
		for (size_t j = i + 1; j < p_edges.size(); j++) {
			if (p_edges[i].slot == p_edges[j].slot) {
				return _bad(MeshError::ADJACENT_SELECTION, p_edges[i].slot);
			}
		}
	}
	for (size_t i = 0; i < p_edges.size(); i++) {
		BevelPlan plan;
		const MeshFault planned = _plan_bevel(p_edit.scratch(), p_edges[i], dist, plan);
		if (!planned.ok()) {
			if (i > 0) {
				_poison(p_edit);
			}
			return planned;
		}
		const MeshFault applied = _apply_bevel(p_edit, plan);
		if (!applied.ok()) {
			return applied;
		}
	}
	return p_edit.last_fault();
}

} // namespace ops
} // namespace slab
