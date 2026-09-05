#include "mesh.hpp"

#include <unordered_set>

namespace slab {

bool Mesh::_vertex_live(uint32_t p_slot) const {
	if (p_slot >= vertices.size() || vertices[p_slot].gen == 0) {
		return false;
	}
	for (uint32_t free : free_vertices) {
		if (free == p_slot) {
			return false;
		}
	}
	return true;
}

bool Mesh::_face_live(uint32_t p_slot) const {
	if (p_slot >= faces.size() || faces[p_slot].gen == 0) {
		return false;
	}
	for (uint32_t free : free_faces) {
		if (free == p_slot) {
			return false;
		}
	}
	return true;
}

bool Mesh::_he_live(uint32_t p_slot) const {
	if (p_slot >= half_edges.size() || half_edges[p_slot].gen == 0) {
		return false;
	}
	for (uint32_t free : free_half_edges) {
		if (free == p_slot) {
			return false;
		}
	}
	return true;
}

int Mesh::face_count() const {
	int n = 0;
	for (uint32_t i = 0; i < faces.size(); i++) {
		if (_face_live(i)) {
			n++;
		}
	}
	return n;
}

int Mesh::vertex_count() const {
	int n = 0;
	for (uint32_t i = 0; i < vertices.size(); i++) {
		if (_vertex_live(i)) {
			n++;
		}
	}
	return n;
}

int Mesh::edge_count() const {
	int n = 0;
	for (uint32_t i = 0; i < half_edges.size(); i++) {
		if (!_he_live(i)) {
			continue;
		}
		const uint32_t twin = half_edges[i].twin.i;
		if (twin == INVALID_IDX || twin >= half_edges.size() || !_he_live(twin)) {
			continue;
		}
		if (i < twin) {
			n++;
		}
	}
	return n;
}

bool Mesh::alive(FaceId p_id) const {
	return p_id.gen != 0 && p_id.slot < faces.size() && faces[p_id.slot].gen == p_id.gen && _face_live(p_id.slot);
}

bool Mesh::alive(VertexId p_id) const {
	return p_id.gen != 0 && p_id.slot < vertices.size() && vertices[p_id.slot].gen == p_id.gen && _vertex_live(p_id.slot);
}

bool Mesh::alive(EdgeId p_id) const {
	if (p_id.gen == 0 || p_id.slot >= half_edges.size()) {
		return false;
	}
	if (!_he_live(p_id.slot) || half_edges[p_id.slot].gen != p_id.gen) {
		return false;
	}
	const uint32_t twin = half_edges[p_id.slot].twin.i;
	if (twin == INVALID_IDX || twin >= half_edges.size() || !_he_live(twin)) {
		return false;
	}
	if (half_edges[twin].twin.i != p_id.slot) {
		return false;
	}
	return p_id.slot < twin;
}

EdgeId Mesh::_edge_id(uint32_t p_he) const {
	if (p_he == INVALID_IDX || !_he_live(p_he)) {
		return EdgeId{};
	}
	const uint32_t twin = half_edges[p_he].twin.i;
	if (twin == INVALID_IDX || twin >= half_edges.size() || !_he_live(twin)) {
		return EdgeId{};
	}
	const uint32_t slot = p_he < twin ? p_he : twin;
	return EdgeId{ slot, half_edges[slot].gen };
}

godot::Vector3 Mesh::position(VertexId p_id) const {
	if (!alive(p_id)) {
		return godot::Vector3();
	}
	return dequantize(vertices[p_id.slot].pos);
}

FaceAttrs Mesh::attrs(FaceId p_id) const {
	if (!alive(p_id)) {
		return FaceAttrs{};
	}
	return faces[p_id.slot].attrs;
}

godot::Vector3 Mesh::face_normal(FaceId p_id) const {
	std::vector<VertexId> corners;
	face_corners(p_id, corners);
	if (corners.size() < 3) {
		return godot::Vector3();
	}
	const godot::Vector3 a = position(corners[0]);
	const godot::Vector3 ab = position(corners[1]) - a;
	const godot::Vector3 ac = position(corners[2]) - a;
	const godot::Vector3 n = ab.cross(ac);
	if (n.length_squared() == 0.0f) {
		return godot::Vector3();
	}
	return n.normalized();
}

IVec3 Mesh::position_i(VertexId p_id) const {
	if (!alive(p_id)) {
		return IVec3{};
	}
	return vertices[p_id.slot].pos;
}

void Mesh::face_corners(FaceId p_id, std::vector<VertexId> &r_out) const {
	r_out.clear();
	if (!alive(p_id)) {
		return;
	}
	const HalfEdgeIdx start = faces[p_id.slot].he;
	if (start.i == INVALID_IDX || !_he_live(start.i)) {
		return;
	}
	HalfEdgeIdx he = start;
	std::unordered_set<uint32_t> seen;
	do {
		if (!_he_live(he.i) || !seen.insert(he.i).second) {
			r_out.clear();
			return;
		}
		const VertexIdx v = half_edges[he.i].origin;
		if (!_vertex_live(v.i)) {
			r_out.clear();
			return;
		}
		r_out.push_back(VertexId{ v.i, vertices[v.i].gen });
		he = half_edges[he.i].next;
	} while (he.i != start.i);
}

void Mesh::all_faces(std::vector<FaceId> &r_out) const {
	r_out.clear();
	for (uint32_t i = 0; i < faces.size(); i++) {
		if (_face_live(i)) {
			r_out.push_back(FaceId{ i, faces[i].gen });
		}
	}
}

void Mesh::all_vertices(std::vector<VertexId> &r_out) const {
	r_out.clear();
	for (uint32_t i = 0; i < vertices.size(); i++) {
		if (_vertex_live(i)) {
			r_out.push_back(VertexId{ i, vertices[i].gen });
		}
	}
}

void Mesh::all_edges(std::vector<EdgeId> &r_out) const {
	r_out.clear();
	for (uint32_t i = 0; i < half_edges.size(); i++) {
		if (!_he_live(i)) {
			continue;
		}
		const uint32_t twin = half_edges[i].twin.i;
		if (twin == INVALID_IDX || twin >= half_edges.size() || !_he_live(twin)) {
			continue;
		}
		if (i < twin) {
			r_out.push_back(EdgeId{ i, half_edges[i].gen });
		}
	}
}

void Mesh::edge_vertices(EdgeId p_id, VertexId &r_a, VertexId &r_b) const {
	r_a = VertexId{};
	r_b = VertexId{};
	if (!alive(p_id)) {
		return;
	}
	const uint32_t twin = half_edges[p_id.slot].twin.i;
	const VertexIdx va = half_edges[p_id.slot].origin;
	const VertexIdx vb = half_edges[twin].origin;
	if (va.i == INVALID_IDX || !_vertex_live(va.i) || vb.i == INVALID_IDX || !_vertex_live(vb.i)) {
		return;
	}
	r_a = VertexId{ va.i, vertices[va.i].gen };
	r_b = VertexId{ vb.i, vertices[vb.i].gen };
}

void Mesh::edge_faces(EdgeId p_id, FaceId &r_a, FaceId &r_b) const {
	r_a = FaceId{};
	r_b = FaceId{};
	if (!alive(p_id)) {
		return;
	}
	const uint32_t twin = half_edges[p_id.slot].twin.i;
	const FaceIdx fa = half_edges[p_id.slot].face;
	const FaceIdx fb = half_edges[twin].face;
	if (fa.i == INVALID_IDX || !_face_live(fa.i) || fb.i == INVALID_IDX || !_face_live(fb.i)) {
		return;
	}
	r_a = FaceId{ fa.i, faces[fa.i].gen };
	r_b = FaceId{ fb.i, faces[fb.i].gen };
}

void Mesh::face_edges(FaceId p_id, std::vector<EdgeId> &r_out) const {
	r_out.clear();
	if (!alive(p_id)) {
		return;
	}
	const HalfEdgeIdx start = faces[p_id.slot].he;
	if (start.i == INVALID_IDX || !_he_live(start.i)) {
		return;
	}
	HalfEdgeIdx he = start;
	std::unordered_set<uint32_t> seen;
	do {
		if (!_he_live(he.i) || !seen.insert(he.i).second) {
			r_out.clear();
			return;
		}
		const EdgeId e = _edge_id(he.i);
		if (e.gen == 0) {
			r_out.clear();
			return;
		}
		r_out.push_back(e);
		he = half_edges[he.i].next;
		if (he.i == INVALID_IDX) {
			r_out.clear();
			return;
		}
	} while (he.i != start.i);
}

void Mesh::vertex_edges(VertexId p_id, std::vector<EdgeId> &r_out) const {
	r_out.clear();
	if (!alive(p_id)) {
		return;
	}
	const HalfEdgeIdx start = vertices[p_id.slot].out;
	if (start.i == INVALID_IDX || !_he_live(start.i)) {
		return;
	}
	HalfEdgeIdx he = start;
	std::unordered_set<uint32_t> seen;
	do {
		if (!_he_live(he.i) || !seen.insert(he.i).second) {
			r_out.clear();
			return;
		}
		const EdgeId e = _edge_id(he.i);
		if (e.gen == 0) {
			r_out.clear();
			return;
		}
		r_out.push_back(e);
		const uint32_t twin = half_edges[he.i].twin.i;
		if (twin == INVALID_IDX || !_he_live(twin)) {
			r_out.clear();
			return;
		}
		he = half_edges[twin].next;
		if (he.i == INVALID_IDX) {
			r_out.clear();
			return;
		}
	} while (he.i != start.i);
}

void Mesh::vertex_faces(VertexId p_id, std::vector<FaceId> &r_out) const {
	r_out.clear();
	if (!alive(p_id)) {
		return;
	}
	const HalfEdgeIdx start = vertices[p_id.slot].out;
	if (start.i == INVALID_IDX || !_he_live(start.i)) {
		return;
	}
	HalfEdgeIdx he = start;
	std::unordered_set<uint32_t> seen;
	do {
		if (!_he_live(he.i) || !seen.insert(he.i).second) {
			r_out.clear();
			return;
		}
		const FaceIdx f = half_edges[he.i].face;
		if (f.i == INVALID_IDX || !_face_live(f.i)) {
			r_out.clear();
			return;
		}
		r_out.push_back(FaceId{ f.i, faces[f.i].gen });
		const uint32_t twin = half_edges[he.i].twin.i;
		if (twin == INVALID_IDX || !_he_live(twin)) {
			r_out.clear();
			return;
		}
		he = half_edges[twin].next;
		if (he.i == INVALID_IDX) {
			r_out.clear();
			return;
		}
	} while (he.i != start.i);
}

godot::Vector3 Mesh::face_centroid(FaceId p_id) const {
	std::vector<VertexId> corners;
	face_corners(p_id, corners);
	if (corners.empty()) {
		return godot::Vector3();
	}
	double sx = 0;
	double sy = 0;
	double sz = 0;
	for (const VertexId v : corners) {
		const godot::Vector3 p = position(v);
		sx += double(p.x);
		sy += double(p.y);
		sz += double(p.z);
	}
	const double n = double(corners.size());
	return godot::Vector3(float(sx / n), float(sy / n), float(sz / n));
}

double Mesh::face_area(FaceId p_id) const {
	std::vector<VertexId> corners;
	face_corners(p_id, corners);
	if (corners.size() < 3) {
		return 0;
	}
	godot::Vector3 acc;
	const int n = int(corners.size());
	for (int i = 0; i < n; i++) {
		const godot::Vector3 a = position(corners[i]);
		const godot::Vector3 b = position(corners[(i + 1) % n]);
		acc += a.cross(b);
	}
	return 0.5 * double(acc.length());
}

godot::AABB Mesh::local_aabb() const {
	godot::AABB aabb;
	bool first = true;
	for (uint32_t i = 0; i < vertices.size(); i++) {
		if (!_vertex_live(i)) {
			continue;
		}
		const godot::Vector3 p = dequantize(vertices[i].pos);
		if (first) {
			aabb.position = p;
			aabb.size = godot::Vector3();
			first = false;
		} else {
			aabb.expand_to(p);
		}
	}
	return aabb;
}

double Mesh::signed_volume() const {
	const __int128 s = signed_volume_6x(*this);
	const double lat3 = double(LATTICE) * double(LATTICE) * double(LATTICE);
	return double(s) / 6.0 / lat3;
}

} // namespace slab
