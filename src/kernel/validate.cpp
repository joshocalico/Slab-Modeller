#include "mesh.hpp"

#include <unordered_set>
#include <vector>

namespace slab {

static MeshFault fault(MeshError p_code, uint32_t p_slot = INVALID_IDX) {
	MeshFault f;
	f.code = p_code;
	f.slot = p_slot;
	return f;
}

MeshFault validate(const Mesh &p_mesh) {
	if (p_mesh.face_count() < 1) {
		return fault(MeshError::RESULT_EMPTY);
	}

	for (uint32_t i = 0; i < p_mesh.half_edges.size(); i++) {
		if (!p_mesh._he_live(i)) {
			continue;
		}
		const HalfEdge &he = p_mesh.half_edges[i];
		if (he.twin.i == INVALID_IDX || he.twin.i >= p_mesh.half_edges.size() || !p_mesh._he_live(he.twin.i)) {
			return fault(MeshError::NOT_CLOSED, i);
		}
		const HalfEdge &twin = p_mesh.half_edges[he.twin.i];
		if (twin.twin.i != i || he.twin.i == i) {
			return fault(MeshError::TWIN_MISMATCH, i);
		}
		if (he.next.i == INVALID_IDX || he.next.i >= p_mesh.half_edges.size() || !p_mesh._he_live(he.next.i)) {
			return fault(MeshError::LOOP_TOO_SHORT, i);
		}
		if (he.face.i == INVALID_IDX || !p_mesh._face_live(he.face.i)) {
			return fault(MeshError::NOT_CLOSED, i);
		}
		if (he.origin.i == INVALID_IDX || !p_mesh._vertex_live(he.origin.i)) {
			return fault(MeshError::DEGENERATE_FACE, i);
		}
		if (p_mesh.half_edges[he.next.i].origin.i != twin.origin.i) {
			return fault(MeshError::INCONSISTENT_ORIENTATION, i);
		}
	}

	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	for (const FaceId id : faces) {
		const Face &face = p_mesh.faces[id.slot];
		if (face.he.i == INVALID_IDX || !p_mesh._he_live(face.he.i)) {
			return fault(MeshError::LOOP_TOO_SHORT, id.slot);
		}
		std::vector<VertexId> corners;
		p_mesh.face_corners(id, corners);
		if (corners.size() < 3) {
			return fault(MeshError::LOOP_TOO_SHORT, id.slot);
		}
		std::unordered_set<uint32_t> uniq;
		for (const VertexId &v : corners) {
			uniq.insert(v.slot);
		}
		if (uniq.size() < 3) {
			return fault(MeshError::DEGENERATE_FACE, id.slot);
		}
		HalfEdgeIdx he = face.he;
		std::unordered_set<uint32_t> walked;
		do {
			if (!walked.insert(he.i).second) {
				return fault(MeshError::LOOP_TOO_SHORT, id.slot);
			}
			if (p_mesh.half_edges[he.i].face.i != id.slot) {
				return fault(MeshError::INCONSISTENT_ORIENTATION, he.i);
			}
			he = p_mesh.half_edges[he.i].next;
		} while (he.i != face.he.i);
	}

	std::vector<VertexId> verts;
	p_mesh.all_vertices(verts);
	for (const VertexId id : verts) {
		const Vertex &v = p_mesh.vertices[id.slot];
		if (v.out.i == INVALID_IDX || !p_mesh._he_live(v.out.i)) {
			return fault(MeshError::NON_MANIFOLD_VERTEX, id.slot);
		}
		if (p_mesh.half_edges[v.out.i].origin.i != id.slot) {
			return fault(MeshError::NON_MANIFOLD_VERTEX, id.slot);
		}
		std::unordered_set<uint32_t> ring;
		HalfEdgeIdx he = v.out;
		do {
			if (p_mesh.half_edges[he.i].origin.i != id.slot) {
				return fault(MeshError::NON_MANIFOLD_VERTEX, id.slot);
			}
			if (!ring.insert(he.i).second) {
				return fault(MeshError::NON_MANIFOLD_VERTEX, id.slot);
			}
			const HalfEdgeIdx twin = p_mesh.half_edges[he.i].twin;
			he = p_mesh.half_edges[twin.i].next;
		} while (he.i != v.out.i);

		for (uint32_t i = 0; i < p_mesh.half_edges.size(); i++) {
			if (!p_mesh._he_live(i)) {
				continue;
			}
			if (p_mesh.half_edges[i].origin.i == id.slot && ring.count(i) == 0) {
				return fault(MeshError::NON_MANIFOLD_VERTEX, id.slot);
			}
		}
	}

	if (signed_volume_6x(p_mesh) <= 0) {
		return fault(MeshError::INVERTED_VOLUME);
	}
	return MeshFault{};
}

} // namespace slab
