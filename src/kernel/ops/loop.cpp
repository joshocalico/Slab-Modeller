#include "loop.hpp"

#include "weld.hpp"

#include <algorithm>
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
	IVec3 pos;
	VertexId made;
};

struct RingFace {
	FaceId face;
	uint32_t entry = INVALID_IDX;
	uint32_t exit = INVALID_IDX;
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

bool _walk_strip(const Mesh &p_mesh, EdgeId p_entry, FaceId p_face, double p_t,
		std::vector<RingCut> &r_cuts, std::vector<RingFace> &r_faces) {
	EdgeId entry = p_entry;
	FaceId face = p_face;
	const int limit = p_mesh.face_count() + 1;
	for (int step = 0; step < limit; step++) {
		if (!p_mesh.alive(face) || !p_mesh.alive(entry)) {
			return false;
		}
		std::vector<VertexId> corners;
		std::vector<EdgeId> edges;
		p_mesh.face_corners(face, corners);
		p_mesh.face_edges(face, edges);
		if (corners.size() != 4 || edges.size() != 4) {
			return false;
		}
		int at = -1;
		for (int k = 0; k < 4; k++) {
			if (edges[k].slot == entry.slot) {
				at = k;
			}
		}
		if (at < 0) {
			return false;
		}
		const EdgeId exit = edges[(at + 2) % 4];
		if (exit.slot == entry.slot) {
			return false;
		}
		if (_face_seen(r_faces, face.slot)) {
			return true;
		}
		if (_cut_at(r_cuts, entry.slot) < 0) {
			RingCut cut;
			cut.edge = entry;
			cut.pos = _along(p_mesh.position_i(corners[at]), p_mesh.position_i(corners[(at + 1) % 4]), p_t);
			r_cuts.push_back(cut);
		}
		if (_cut_at(r_cuts, exit.slot) < 0) {
			RingCut cut;
			cut.edge = exit;
			cut.pos = _along(p_mesh.position_i(corners[(at + 2) % 4]), p_mesh.position_i(corners[(at + 3) % 4]), 1.0 - p_t);
			r_cuts.push_back(cut);
		}
		RingFace rf;
		rf.face = face;
		rf.entry = entry.slot;
		rf.exit = exit.slot;
		r_faces.push_back(rf);

		FaceId near_side;
		FaceId far_side;
		p_mesh.edge_faces(exit, near_side, far_side);
		face = near_side.slot == face.slot ? far_side : near_side;
		entry = exit;
	}
	return false;
}

} // namespace

MeshFault insert_loop(MeshEdit &p_edit, EdgeId p_edge, float p_t) {
	const Mesh &src = p_edit.scratch();
	if (!src.alive(p_edge)) {
		return _bad(MeshError::STALE_HANDLE, p_edge.slot);
	}
	FaceId left;
	FaceId right;
	src.edge_faces(p_edge, left, right);
	if (!src.alive(left) || !src.alive(right)) {
		return _bad(MeshError::NOT_CLOSED, p_edge.slot);
	}
	double t = double(p_t);
	if (!(t > 0.05)) {
		t = 0.05;
	}
	if (t > 0.95) {
		t = 0.95;
	}

	std::vector<RingCut> cuts;
	std::vector<RingFace> faces;
	if (!_walk_strip(src, p_edge, left, t, cuts, faces)) {
		_walk_strip(src, p_edge, right, 1.0 - t, cuts, faces);
	}
	if (faces.empty()) {
		return _bad(MeshError::DEGENERATE_FACE, p_edge.slot);
	}

	for (RingCut &cut : cuts) {
		cut.made = p_edit.split_edge(cut.edge, cut.pos);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	for (const RingFace &rf : faces) {
		const int entry = _cut_at(cuts, rf.entry);
		const int exit = _cut_at(cuts, rf.exit);
		if (entry < 0 || exit < 0) {
			_poison(p_edit);
			return p_edit.last_fault();
		}
		p_edit.split_face(rf.face, cuts[entry].made, cuts[exit].made);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	return p_edit.last_fault();
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
