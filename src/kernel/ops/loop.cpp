#include "loop.hpp"

#include "weld.hpp"

#include <algorithm>
#include <cmath>
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

int32_t _lerp1(int32_t p_a, int32_t p_b, double p_t) {
	const double v = double(p_a) + p_t * (double(p_b) - double(p_a));
	return int32_t(v >= 0.0 ? int64_t(v + 0.5) : -int64_t(0.5 - v));
}

IVec3 _along(const IVec3 &p_a, const IVec3 &p_b, double p_t) {
	return IVec3{ _lerp1(p_a.x, p_b.x, p_t), _lerp1(p_a.y, p_b.y, p_t), _lerp1(p_a.z, p_b.z, p_t) };
}

__int128 _dist2(const IVec3 &p_a, const IVec3 &p_b) {
	const int64_t dx = int64_t(p_a.x) - p_b.x;
	const int64_t dy = int64_t(p_a.y) - p_b.y;
	const int64_t dz = int64_t(p_a.z) - p_b.z;
	return __int128(dx) * dx + __int128(dy) * dy + __int128(dz) * dz;
}

struct RingCut {
	EdgeId edge;
	std::vector<IVec3> pos;
	std::vector<VertexId> made;
};

struct RingFace {
	FaceId face;
	uint32_t entry = INVALID_IDX;
	uint32_t exit = INVALID_IDX;
};

struct LoopPlan {
	std::vector<float> positions;
	std::vector<RingCut> cuts;
	std::vector<RingFace> faces;
};

int _cut_at(const std::vector<RingCut> &p_cuts, uint32_t p_slot) {
	for (size_t i = 0; i < p_cuts.size(); i++) {
		if (p_cuts[i].edge.slot == p_slot) {
			return int(i);
		}
	}
	return -1;
}

bool _face_seen(const std::vector<RingFace> &p_faces, uint32_t p_slot) {
	for (const RingFace &rf : p_faces) {
		if (rf.face.slot == p_slot) {
			return true;
		}
	}
	return false;
}

bool _add_cut(EdgeId p_edge, const IVec3 &p_a, const IVec3 &p_b,
		const std::vector<float> &p_positions, bool p_reverse, std::vector<RingCut> &r_cuts) {
	if (_cut_at(r_cuts, p_edge.slot) >= 0) {
		return true;
	}
	RingCut cut;
	cut.edge = p_edge;
	cut.pos.reserve(p_positions.size());
	for (const float position : p_positions) {
		const double t = p_reverse ? 1.0 - double(position) : double(position);
		const IVec3 point = _along(p_a, p_b, t);
		if (point == p_a || point == p_b) {
			return false;
		}
		for (const IVec3 &prior : cut.pos) {
			if (point == prior) {
				return false;
			}
		}
		cut.pos.push_back(point);
	}
	cut.made.resize(p_positions.size());
	r_cuts.push_back(cut);
	return true;
}

enum class WalkResult {
	INVALID,
	TERMINATED,
	CLOSED,
};

// A non-quad terminates an open strip; revisiting closes a ring.
WalkResult _walk_strip(const Mesh &p_mesh, EdgeId p_entry, FaceId p_face,
		const std::vector<float> &p_positions, bool p_reverse, LoopPlan &r_plan) {
	EdgeId entry = p_entry;
	FaceId face = p_face;
	const int limit = p_mesh.face_count() + 1;
	for (int step = 0; step < limit; step++) {
		if (!p_mesh.alive(face) || !p_mesh.alive(entry)) {
			return WalkResult::INVALID;
		}
		if (_face_seen(r_plan.faces, face.slot)) {
			return WalkResult::CLOSED;
		}
		std::vector<VertexId> corners;
		std::vector<EdgeId> edges;
		p_mesh.face_corners(face, corners);
		p_mesh.face_edges(face, edges);
		if (corners.size() != 4 || edges.size() != 4) {
			return WalkResult::TERMINATED;
		}
		int at = -1;
		for (int k = 0; k < 4; k++) {
			if (edges[k].slot == entry.slot) {
				at = k;
				break;
			}
		}
		if (at < 0) {
			return WalkResult::INVALID;
		}
		const EdgeId exit = edges[(at + 2) % 4];
		if (exit.slot == entry.slot ||
				!_add_cut(entry, p_mesh.position_i(corners[at]), p_mesh.position_i(corners[(at + 1) % 4]), p_positions, p_reverse, r_plan.cuts) ||
				!_add_cut(exit, p_mesh.position_i(corners[(at + 2) % 4]), p_mesh.position_i(corners[(at + 3) % 4]), p_positions, !p_reverse, r_plan.cuts)) {
			return WalkResult::INVALID;
		}
		r_plan.faces.push_back({ face, entry.slot, exit.slot });

		FaceId near_side;
		FaceId far_side;
		p_mesh.edge_faces(exit, near_side, far_side);
		face = near_side.slot == face.slot ? far_side : near_side;
		entry = exit;
	}
	return WalkResult::INVALID;
}

MeshFault _plan_loops(const Mesh &p_mesh, EdgeId p_edge, const std::vector<float> &p_positions, LoopPlan &r_plan) {
	r_plan = LoopPlan{};
	if (!p_mesh.alive(p_edge)) {
		return _bad(MeshError::STALE_HANDLE, p_edge.slot);
	}
	if (p_positions.empty()) {
		return _bad(MeshError::INVALID_SELECTION, p_edge.slot);
	}
	for (size_t i = 0; i < p_positions.size(); i++) {
		const float position = p_positions[i];
		if (!std::isfinite(position) || !(position > 0.0f && position < 1.0f)) {
			return _bad(MeshError::INVALID_SELECTION, p_edge.slot);
		}
		for (size_t j = 0; j < i; j++) {
			if (position == p_positions[j]) {
				return _bad(MeshError::INVALID_SELECTION, p_edge.slot);
			}
		}
	}

	FaceId left;
	FaceId right;
	p_mesh.edge_faces(p_edge, left, right);
	if (!p_mesh.alive(left) || !p_mesh.alive(right)) {
		return _bad(MeshError::NOT_CLOSED, p_edge.slot);
	}
	LoopPlan left_plan;
	left_plan.positions = p_positions;
	const WalkResult left_result = _walk_strip(p_mesh, p_edge, left, p_positions, false, left_plan);
	if (left_result == WalkResult::CLOSED) {
		r_plan = std::move(left_plan);
		return MeshFault{};
	}
	if (left_result != WalkResult::INVALID &&
			_walk_strip(p_mesh, p_edge, right, p_positions, true, left_plan) != WalkResult::INVALID &&
			!left_plan.faces.empty()) {
		r_plan = std::move(left_plan);
		return MeshFault{};
	}
	return _bad(MeshError::DEGENERATE_FACE, p_edge.slot);
}

} // namespace

MeshFault loop_segments(const Mesh &p_mesh, EdgeId p_edge, const std::vector<float> &p_positions,
		std::vector<std::pair<IVec3, IVec3>> &r_segments) {
	r_segments.clear();
	LoopPlan plan;
	const MeshFault fault = _plan_loops(p_mesh, p_edge, p_positions, plan);
	if (!fault.ok()) {
		return fault;
	}
	r_segments.reserve(plan.positions.size() * plan.faces.size());
	for (size_t position = 0; position < plan.positions.size(); position++) {
		for (const RingFace &face : plan.faces) {
			const int entry = _cut_at(plan.cuts, face.entry);
			const int exit = _cut_at(plan.cuts, face.exit);
			if (entry < 0 || exit < 0) {
				r_segments.clear();
				return _bad(MeshError::CORRUPT_DATA, face.face.slot);
			}
			r_segments.push_back({ plan.cuts[size_t(entry)].pos[position], plan.cuts[size_t(exit)].pos[position] });
		}
	}
	return MeshFault{};
}

MeshFault insert_loops(MeshEdit &p_edit, EdgeId p_edge, const std::vector<float> &p_positions) {
	LoopPlan plan;
	const MeshFault planned = _plan_loops(p_edit.scratch(), p_edge, p_positions, plan);
	if (!planned.ok()) {
		return planned;
	}
	for (RingCut &cut : plan.cuts) {
		std::vector<size_t> order(plan.positions.size());
		for (size_t i = 0; i < order.size(); i++) {
			order[i] = i;
		}
		VertexId origin;
		VertexId end;
		p_edit.scratch().edge_vertices(cut.edge, origin, end);
		const IVec3 origin_pos = p_edit.scratch().position_i(origin);
		std::sort(order.begin(), order.end(), [&](size_t p_a, size_t p_b) {
			return _dist2(cut.pos[p_a], origin_pos) > _dist2(cut.pos[p_b], origin_pos);
		});
		for (const size_t position : order) {
			cut.made[position] = p_edit.split_edge(cut.edge, cut.pos[position]);
			if (!p_edit.last_fault().ok()) {
				return p_edit.last_fault();
			}
		}
	}
	for (size_t position = 0; position < plan.positions.size(); position++) {
		for (const RingFace &rf : plan.faces) {
			const int entry = _cut_at(plan.cuts, rf.entry);
			const int exit = _cut_at(plan.cuts, rf.exit);
			if (entry < 0 || exit < 0) {
				_poison(p_edit);
				return p_edit.last_fault();
			}
			const VertexId a = plan.cuts[size_t(entry)].made[position];
			const VertexId b = plan.cuts[size_t(exit)].made[position];
			const FaceId face = shared_cut_face(p_edit.scratch(), a, b);
			if (!p_edit.scratch().alive(face)) {
				_poison(p_edit);
				return p_edit.last_fault();
			}
			p_edit.split_face(face, a, b);
			if (!p_edit.last_fault().ok()) {
				return p_edit.last_fault();
			}
		}
	}
	return p_edit.last_fault();
}

MeshFault insert_loop(MeshEdit &p_edit, EdgeId p_edge, float p_t) {
	double t = double(p_t);
	if (!(t > 0.05)) {
		t = 0.05;
	}
	if (t > 0.95) {
		t = 0.95;
	}
	return insert_loops(p_edit, p_edge, { float(t) });
}

MeshFault connect_edges(MeshEdit &p_edit, EdgeId p_a, EdgeId p_b) {
	const Mesh &src = p_edit.scratch();
	if (!src.alive(p_a) || !src.alive(p_b)) {
		return _bad(MeshError::STALE_HANDLE, src.alive(p_a) ? p_b.slot : p_a.slot);
	}
	if (p_a.slot == p_b.slot) {
		return _bad(MeshError::ADJACENT_SELECTION, p_a.slot);
	}
	VertexId a0;
	VertexId a1;
	VertexId b0;
	VertexId b1;
	src.edge_vertices(p_a, a0, a1);
	src.edge_vertices(p_b, b0, b1);
	const VertexId lhs[2] = { a0, a1 };
	const VertexId rhs[2] = { b0, b1 };

	struct Span {
		VertexId a;
		VertexId b;
		__int128 reach = 0;
	};
	std::vector<Span> spans;
	for (int i = 0; i < 2; i++) {
		for (int j = 0; j < 2; j++) {
			if (!src.alive(lhs[i]) || !src.alive(rhs[j]) || lhs[i].slot == rhs[j].slot) {
				continue;
			}
			Span span;
			span.a = lhs[i];
			span.b = rhs[j];
			span.reach = _dist2(src.position_i(lhs[i]), src.position_i(rhs[j]));
			spans.push_back(span);
		}
	}
	if (spans.empty()) {
		return _bad(MeshError::ADJACENT_SELECTION, p_a.slot);
	}
	std::sort(spans.begin(), spans.end(), [](const Span &p_x, const Span &p_y) {
		return p_x.reach < p_y.reach;
	});
	for (const Span &span : spans) {
		if (src.alive(shared_cut_face(src, span.a, span.b))) {
			return connect_vertices(p_edit, span.a, span.b);
		}
	}
	return _bad(MeshError::ADJACENT_SELECTION, p_a.slot);
}

} // namespace ops
} // namespace slab
