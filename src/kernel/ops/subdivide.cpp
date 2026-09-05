#include "subdivide.hpp"

#include "inset.hpp"

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

int32_t _div_round(int64_t p_num, int64_t p_den) {
	const int64_t half = p_den / 2;
	return int32_t(p_num >= 0 ? (p_num + half) / p_den : (p_num - half) / p_den);
}

IVec3 _midpoint(const IVec3 &p_a, const IVec3 &p_b) {
	return IVec3{
		_div_round(int64_t(p_a.x) + p_b.x, 2),
		_div_round(int64_t(p_a.y) + p_b.y, 2),
		_div_round(int64_t(p_a.z) + p_b.z, 2)
	};
}

IVec3 _centroid(const std::vector<IVec3> &p_pts) {
	int64_t sx = 0;
	int64_t sy = 0;
	int64_t sz = 0;
	for (const IVec3 &p : p_pts) {
		sx += p.x;
		sy += p.y;
		sz += p.z;
	}
	const int64_t n = int64_t(p_pts.size());
	return IVec3{ _div_round(sx, n), _div_round(sy, n), _div_round(sz, n) };
}

EdgeId _edge_between(const Mesh &p_mesh, VertexId p_a, VertexId p_b) {
	std::vector<EdgeId> edges;
	p_mesh.vertex_edges(p_a, edges);
	for (const EdgeId id : edges) {
		VertexId x;
		VertexId y;
		p_mesh.edge_vertices(id, x, y);
		if (x.slot == p_b.slot || y.slot == p_b.slot) {
			return id;
		}
	}
	return EdgeId{};
}

MeshFault _subdivide_one(MeshEdit &p_edit, FaceId p_face) {
	std::vector<VertexId> corners;
	p_edit.scratch().face_corners(p_face, corners);
	const int n = int(corners.size());
	std::vector<IVec3> pos(n);
	for (int i = 0; i < n; i++) {
		pos[i] = p_edit.scratch().position_i(corners[i]);
	}
	const IVec3 centre = _centroid(pos);

	std::vector<VertexId> mids(n);
	for (int i = 0; i < n; i++) {
		const int next = (i + 1) % n;
		const EdgeId edge = _edge_between(p_edit.scratch(), corners[i], corners[next]);
		mids[i] = p_edit.split_edge(edge, _midpoint(pos[i], pos[next]));
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}

	const EdgeId cut = p_edit.split_face(p_face, mids[0], mids[2]);
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	FaceId halves[2];
	p_edit.scratch().edge_faces(cut, halves[0], halves[1]);
	const VertexId hub = p_edit.split_edge(cut, centre);
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}

	for (const FaceId half : halves) {
		for (int guard = 0; guard <= n; guard++) {
			std::vector<VertexId> ring;
			p_edit.scratch().face_corners(half, ring);
			const int len = int(ring.size());
			if (len <= 4) {
				break;
			}
			int at = -1;
			for (int k = 0; k < len; k++) {
				if (ring[k].slot == hub.slot) {
					at = k;
				}
			}
			if (at < 0) {
				_poison(p_edit);
				return p_edit.last_fault();
			}
			p_edit.split_face(half, ring[(at + 3) % len], hub);
			if (!p_edit.last_fault().ok()) {
				return p_edit.last_fault();
			}
		}
	}
	return p_edit.last_fault();
}

} // namespace

MeshFault subdivide(MeshEdit &p_edit, const std::vector<FaceId> &p_faces) {
	if (p_faces.empty()) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const Mesh &src = p_edit.scratch();
	if (!faces_alive(src, p_faces)) {
		return _bad(MeshError::STALE_HANDLE);
	}
	if (faces_share_an_edge(src, p_faces)) {
		return _bad(MeshError::ADJACENT_SELECTION);
	}
	for (const FaceId id : p_faces) {
		std::vector<VertexId> corners;
		src.face_corners(id, corners);
		if (corners.size() < 3) {
			return _bad(MeshError::LOOP_TOO_SHORT, id.slot);
		}
	}
	for (const FaceId id : p_faces) {
		const MeshFault split = _subdivide_one(p_edit, id);
		if (!split.ok()) {
			return split;
		}
	}
	return p_edit.last_fault();
}

} // namespace ops
} // namespace slab
