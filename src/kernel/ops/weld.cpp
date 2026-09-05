#include "weld.hpp"

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

__int128 _dist2(const IVec3 &p_a, const IVec3 &p_b) {
	const int64_t dx = int64_t(p_a.x) - p_b.x;
	const int64_t dy = int64_t(p_a.y) - p_b.y;
	const int64_t dz = int64_t(p_a.z) - p_b.z;
	return __int128(dx) * dx + __int128(dy) * dy + __int128(dz) * dz;
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

bool _shares_any_face(const Mesh &p_mesh, VertexId p_a, VertexId p_b) {
	std::vector<FaceId> faces;
	p_mesh.vertex_faces(p_a, faces);
	for (const FaceId id : faces) {
		std::vector<VertexId> ring;
		p_mesh.face_corners(id, ring);
		for (const VertexId v : ring) {
			if (v.slot == p_b.slot) {
				return true;
			}
		}
	}
	return false;
}

MeshFault _all_alive(const Mesh &p_mesh, const std::vector<VertexId> &p_verts) {
	for (const VertexId v : p_verts) {
		if (!p_mesh.alive(v)) {
			return _bad(MeshError::STALE_HANDLE, v.slot);
		}
	}
	return MeshFault{};
}

EdgeId _shortest_edge(const Mesh &p_mesh, VertexId p_v) {
	std::vector<EdgeId> edges;
	p_mesh.vertex_edges(p_v, edges);
	EdgeId best;
	__int128 reach = 0;
	for (const EdgeId id : edges) {
		VertexId keep;
		VertexId kill;
		p_mesh.edge_vertices(id, keep, kill);
		if (!p_mesh.alive(keep) || !p_mesh.alive(kill)) {
			continue;
		}
		const __int128 span = _dist2(p_mesh.position_i(keep), p_mesh.position_i(kill));
		if (best.gen == 0 || span < reach) {
			best = id;
			reach = span;
		}
	}
	return best;
}

MeshFault _collapse_onto_neighbour(MeshEdit &p_edit, EdgeId p_edge, VertexId p_doomed) {
	VertexId keep;
	VertexId kill;
	p_edit.scratch().edge_vertices(p_edge, keep, kill);
	if (!p_edit.scratch().alive(keep) || !p_edit.scratch().alive(kill)) {
		return _bad(MeshError::STALE_HANDLE, p_edge.slot);
	}
	// collapse_edge always retires the twin's origin, so when the doomed vertex is the one that
	// survives, the survivor has to be walked onto its neighbour first to land the same geometry.
	if (keep.slot == p_doomed.slot) {
		p_edit.move_vertex(keep, p_edit.scratch().position_i(kill));
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	return p_edit.collapse_edge(p_edge);
}

} // namespace

FaceId shared_cut_face(const Mesh &p_mesh, VertexId p_a, VertexId p_b) {
	if (!p_mesh.alive(p_a) || !p_mesh.alive(p_b) || p_a.slot == p_b.slot) {
		return FaceId{};
	}
	std::vector<FaceId> faces;
	p_mesh.vertex_faces(p_a, faces);
	for (const FaceId id : faces) {
		std::vector<VertexId> ring;
		p_mesh.face_corners(id, ring);
		const int len = int(ring.size());
		if (len < 4) {
			continue;
		}
		int at_a = -1;
		int at_b = -1;
		for (int k = 0; k < len; k++) {
			if (ring[k].slot == p_a.slot) {
				at_a = k;
			}
			if (ring[k].slot == p_b.slot) {
				at_b = k;
			}
		}
		if (at_a < 0 || at_b < 0) {
			continue;
		}
		const int gap = at_a < at_b ? at_b - at_a : at_a - at_b;
		if (gap == 1 || gap == len - 1) {
			continue;
		}
		return id;
	}
	return FaceId{};
}

MeshFault connect_vertices(MeshEdit &p_edit, VertexId p_a, VertexId p_b) {
	const Mesh &src = p_edit.scratch();
	if (!src.alive(p_a) || !src.alive(p_b)) {
		return _bad(MeshError::STALE_HANDLE, src.alive(p_a) ? p_b.slot : p_a.slot);
	}
	if (p_a.slot == p_b.slot) {
		return _bad(MeshError::INVALID_SELECTION, p_a.slot);
	}
	const FaceId face = shared_cut_face(src, p_a, p_b);
	if (!src.alive(face)) {
		const MeshError code = _shares_any_face(src, p_a, p_b) ? MeshError::ADJACENT_SELECTION : MeshError::INVALID_SELECTION;
		return _bad(code, p_a.slot);
	}
	p_edit.split_face(face, p_a, p_b);
	return p_edit.last_fault();
}

MeshFault connect_vertices(MeshEdit &p_edit, const std::vector<VertexId> &p_verts) {
	if (p_verts.size() < 2) {
		return _bad(MeshError::INVALID_SELECTION);
	}
	for (size_t i = 1; i < p_verts.size(); i++) {
		const MeshFault cut = connect_vertices(p_edit, p_verts[i - 1], p_verts[i]);
		if (!cut.ok()) {
			return cut;
		}
	}
	return p_edit.last_fault();
}

MeshFault weld(MeshEdit &p_edit, const std::vector<VertexId> &p_verts, float p_radius) {
	if (p_verts.empty()) {
		return MeshFault{};
	}
	if (!(p_radius >= 0.0f)) {
		return _bad(MeshError::COORD_OUT_OF_RANGE);
	}
	const MeshFault alive = _all_alive(p_edit.scratch(), p_verts);
	if (!alive.ok()) {
		return alive;
	}
	const int64_t reach = int64_t(double(p_radius) * double(LATTICE) + 0.5);
	const __int128 reach2 = __int128(reach) * reach;
	for (int pass = 0; pass <= int(p_verts.size()); pass++) {
		bool merged = false;
		for (size_t i = 0; i < p_verts.size() && !merged; i++) {
			if (!p_edit.scratch().alive(p_verts[i])) {
				continue;
			}
			for (size_t j = i + 1; j < p_verts.size() && !merged; j++) {
				if (!p_edit.scratch().alive(p_verts[j]) || p_verts[i].slot == p_verts[j].slot) {
					continue;
				}
				if (_dist2(p_edit.scratch().position_i(p_verts[i]), p_edit.scratch().position_i(p_verts[j])) > reach2) {
					continue;
				}
				const EdgeId shared = _edge_between(p_edit.scratch(), p_verts[i], p_verts[j]);
				if (!p_edit.scratch().alive(shared)) {
					// Merging two vertices that share no edge pinches the surface into a
					// non-manifold point, which no rewire of the existing half-edges can undo.
					return _bad(MeshError::SNAP_COLLAPSED_TOPOLOGY, p_verts[j].slot);
				}
				const MeshFault collapsed = _collapse_onto_neighbour(p_edit, shared, p_verts[j]);
				if (!collapsed.ok()) {
					return collapsed;
				}
				merged = true;
			}
		}
		if (!merged) {
			break;
		}
	}
	return p_edit.last_fault();
}

MeshFault collapse(MeshEdit &p_edit, const std::vector<VertexId> &p_verts) {
	if (p_verts.empty()) {
		return MeshFault{};
	}
	const MeshFault alive = _all_alive(p_edit.scratch(), p_verts);
	if (!alive.ok()) {
		return alive;
	}
	for (const VertexId v : p_verts) {
		if (!p_edit.scratch().alive(v)) {
			continue;
		}
		const EdgeId shortest = _shortest_edge(p_edit.scratch(), v);
		if (!p_edit.scratch().alive(shortest)) {
			return _bad(MeshError::NON_MANIFOLD_VERTEX, v.slot);
		}
		const MeshFault collapsed = _collapse_onto_neighbour(p_edit, shortest, v);
		if (!collapsed.ok()) {
			return collapsed;
		}
	}
	return p_edit.last_fault();
}

} // namespace ops
} // namespace slab
