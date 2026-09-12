#include "mesh.hpp"
#include "triangulate.hpp"

#include <cstdint>
#include <unordered_set>
#include <vector>

namespace slab {

namespace {

MeshFault fault(MeshError p_code, uint32_t p_slot = INVALID_IDX) {
	MeshFault f;
	f.code = p_code;
	f.slot = p_slot;
	return f;
}

struct Tri {
	IVec3 a;
	IVec3 b;
	IVec3 c;
};

struct FaceGeom {
	FaceId id;
	godot::AABB box;
	std::vector<IVec3> loop;
	std::vector<Tri> tris;
};

bool _zero_normal(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c) {
	const IVec3 ab{ p_b.x - p_a.x, p_b.y - p_a.y, p_b.z - p_a.z };
	const IVec3 ac{ p_c.x - p_a.x, p_c.y - p_a.y, p_c.z - p_a.z };
	const __int128 nx = (__int128)ab.y * ac.z - (__int128)ab.z * ac.y;
	const __int128 ny = (__int128)ab.z * ac.x - (__int128)ab.x * ac.z;
	const __int128 nz = (__int128)ab.x * ac.y - (__int128)ab.y * ac.x;
	return nx == 0 && ny == 0 && nz == 0;
}

int _drop_axis(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c) {
	const IVec3 ab{ p_b.x - p_a.x, p_b.y - p_a.y, p_b.z - p_a.z };
	const IVec3 ac{ p_c.x - p_a.x, p_c.y - p_a.y, p_c.z - p_a.z };
	__int128 nx = (__int128)ab.y * ac.z - (__int128)ab.z * ac.y;
	__int128 ny = (__int128)ab.z * ac.x - (__int128)ab.x * ac.z;
	__int128 nz = (__int128)ab.x * ac.y - (__int128)ab.y * ac.x;
	if (nx < 0) {
		nx = -nx;
	}
	if (ny < 0) {
		ny = -ny;
	}
	if (nz < 0) {
		nz = -nz;
	}
	if (nx >= ny && nx >= nz) {
		return 0;
	}
	if (ny >= nz) {
		return 1;
	}
	return 2;
}

void _xy(const IVec3 &p_p, int p_axis, int32_t &r_x, int32_t &r_y) {
	if (p_axis == 0) {
		r_x = p_p.y;
		r_y = p_p.z;
		return;
	}
	if (p_axis == 1) {
		r_x = p_p.x;
		r_y = p_p.z;
		return;
	}
	r_x = p_p.x;
	r_y = p_p.y;
}

int _o2(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c, int p_axis) {
	int32_t ax, ay, bx, by, cx, cy;
	_xy(p_a, p_axis, ax, ay);
	_xy(p_b, p_axis, bx, by);
	_xy(p_c, p_axis, cx, cy);
	return orient2d(ax, ay, bx, by, cx, cy);
}

bool _seg_proper_2d(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c, const IVec3 &p_d, int p_axis) {
	const int o1 = _o2(p_a, p_b, p_c, p_axis);
	const int o2 = _o2(p_a, p_b, p_d, p_axis);
	const int o3 = _o2(p_c, p_d, p_a, p_axis);
	const int o4 = _o2(p_c, p_d, p_b, p_axis);
	return o1 * o2 < 0 && o3 * o4 < 0;
}

bool _point_strict_in_tri_2d(const IVec3 &p_p, const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c, int p_axis) {
	const int o1 = _o2(p_a, p_b, p_p, p_axis);
	const int o2 = _o2(p_b, p_c, p_p, p_axis);
	const int o3 = _o2(p_c, p_a, p_p, p_axis);
	return o1 != 0 && o1 == o2 && o2 == o3;
}

void _triangulate(const std::vector<IVec3> &p_loop, std::vector<Tri> &r_tris) {
	std::vector<int32_t> indices;
	triangulate_loop(p_loop, indices);
	for (size_t i = 0; i + 2 < indices.size(); i += 3) {
		r_tris.push_back(Tri{
				p_loop[size_t(indices[i])],
				p_loop[size_t(indices[i + 1])],
				p_loop[size_t(indices[i + 2])],
		});
	}
}

bool _tri_overlap_2d(const Tri &p_a, const Tri &p_b) {
	const int axis = _drop_axis(p_a.a, p_a.b, p_a.c);
	const IVec3 a[3] = { p_a.a, p_a.b, p_a.c };
	const IVec3 b[3] = { p_b.a, p_b.b, p_b.c };
	for (int i = 0; i < 3; i++) {
		if (_point_strict_in_tri_2d(a[i], p_b.a, p_b.b, p_b.c, axis) || _point_strict_in_tri_2d(b[i], p_a.a, p_a.b, p_a.c, axis)) {
			return true;
		}
		for (int j = 0; j < 3; j++) {
			if (_seg_proper_2d(a[i], a[(i + 1) % 3], b[j], b[(j + 1) % 3], axis)) {
				return true;
			}
		}
	}
	return false;
}

bool _edge_pierces_tri(const IVec3 &p_p, const IVec3 &p_q, const Tri &p_t) {
	const int op = orient3d(p_t.a, p_t.b, p_t.c, p_p);
	const int oq = orient3d(p_t.a, p_t.b, p_t.c, p_q);
	if (op == 0 || oq == 0 || op == oq) {
		return false;
	}
	const int o1 = orient3d(p_p, p_q, p_t.a, p_t.b);
	const int o2 = orient3d(p_p, p_q, p_t.b, p_t.c);
	const int o3 = orient3d(p_p, p_q, p_t.c, p_t.a);
	return o1 != 0 && o1 == o2 && o2 == o3;
}

bool _edge_in_tri_plane(const IVec3 &p_p, const IVec3 &p_q, const Tri &p_t) {
	if (orient3d(p_t.a, p_t.b, p_t.c, p_p) != 0 || orient3d(p_t.a, p_t.b, p_t.c, p_q) != 0) {
		return false;
	}
	if (p_p == p_q) {
		return false;
	}
	const int axis = _drop_axis(p_t.a, p_t.b, p_t.c);
	if (_point_strict_in_tri_2d(p_p, p_t.a, p_t.b, p_t.c, axis) || _point_strict_in_tri_2d(p_q, p_t.a, p_t.b, p_t.c, axis)) {
		return true;
	}
	if (_seg_proper_2d(p_p, p_q, p_t.a, p_t.b, axis) || _seg_proper_2d(p_p, p_q, p_t.b, p_t.c, axis) || _seg_proper_2d(p_p, p_q, p_t.c, p_t.a, axis)) {
		return true;
	}
	const IVec3 mid{
		int32_t((int64_t(p_p.x) + p_q.x) / 2),
		int32_t((int64_t(p_p.y) + p_q.y) / 2),
		int32_t((int64_t(p_p.z) + p_q.z) / 2),
	};
	if ((int64_t(p_p.x) + p_q.x) % 2 != 0 || (int64_t(p_p.y) + p_q.y) % 2 != 0 || (int64_t(p_p.z) + p_q.z) % 2 != 0) {
		return false;
	}
	return _point_strict_in_tri_2d(mid, p_t.a, p_t.b, p_t.c, axis);
}

bool _tris_improper(const Tri &p_a, const Tri &p_b) {
	if (_zero_normal(p_a.a, p_a.b, p_a.c) || _zero_normal(p_b.a, p_b.b, p_b.c)) {
		return false;
	}
	const IVec3 ae[3][2] = { { p_a.a, p_a.b }, { p_a.b, p_a.c }, { p_a.c, p_a.a } };
	const IVec3 be[3][2] = { { p_b.a, p_b.b }, { p_b.b, p_b.c }, { p_b.c, p_b.a } };
	for (int i = 0; i < 3; i++) {
		if (_edge_pierces_tri(ae[i][0], ae[i][1], p_b) || _edge_pierces_tri(be[i][0], be[i][1], p_a)) {
			return true;
		}
	}
	const int oa = orient3d(p_a.a, p_a.b, p_a.c, p_b.a);
	const int ob = orient3d(p_a.a, p_a.b, p_a.c, p_b.b);
	const int oc = orient3d(p_a.a, p_a.b, p_a.c, p_b.c);
	if (oa == 0 && ob == 0 && oc == 0) {
		return _tri_overlap_2d(p_a, p_b);
	}
	for (int i = 0; i < 3; i++) {
		if (_edge_in_tri_plane(ae[i][0], ae[i][1], p_b) || _edge_in_tri_plane(be[i][0], be[i][1], p_a)) {
			return true;
		}
	}
	return false;
}

uint64_t _pair_key(uint32_t p_a, uint32_t p_b) {
	if (p_a > p_b) {
		const uint32_t t = p_a;
		p_a = p_b;
		p_b = t;
	}
	return (uint64_t(p_a) << 32) | p_b;
}

FaceGeom _face_geom(const Mesh &p_mesh, FaceId p_id) {
	FaceGeom g;
	g.id = p_id;
	std::vector<VertexId> corners;
	p_mesh.face_corners(p_id, corners);
	g.loop.reserve(corners.size());
	for (const VertexId v : corners) {
		g.loop.push_back(p_mesh.position_i(v));
	}
	if (!g.loop.empty()) {
		g.box = godot::AABB(dequantize(g.loop[0]), godot::Vector3());
		for (size_t i = 1; i < g.loop.size(); i++) {
			g.box.expand_to(dequantize(g.loop[i]));
		}
		g.box = g.box.grow(1.0f / float(LATTICE));
	}
	_triangulate(g.loop, g.tris);
	return g;
}

bool _faces_adjacent(const std::unordered_set<uint64_t> &p_adj, FaceId p_a, FaceId p_b) {
	return p_adj.count(_pair_key(p_a.slot, p_b.slot)) != 0;
}

MeshFault _self_intersection(const Mesh &p_mesh, const std::vector<FaceId> &p_faces) {
	std::unordered_set<uint64_t> adj;
	std::vector<EdgeId> edges;
	p_mesh.all_edges(edges);
	for (const EdgeId id : edges) {
		FaceId fa;
		FaceId fb;
		p_mesh.edge_faces(id, fa, fb);
		if (p_mesh.alive(fa) && p_mesh.alive(fb) && fa.slot != fb.slot) {
			adj.insert(_pair_key(fa.slot, fb.slot));
		}
	}
	std::vector<FaceGeom> geom;
	geom.reserve(p_faces.size());
	for (const FaceId id : p_faces) {
		geom.push_back(_face_geom(p_mesh, id));
	}
	for (size_t i = 0; i < geom.size(); i++) {
		for (size_t j = i + 1; j < geom.size(); j++) {
			if (_faces_adjacent(adj, geom[i].id, geom[j].id)) {
				continue;
			}
			if (!geom[i].box.intersects(geom[j].box)) {
				continue;
			}
			for (const Tri &ta : geom[i].tris) {
				for (const Tri &tb : geom[j].tris) {
					if (_tris_improper(ta, tb)) {
						return fault(MeshError::SELF_INTERSECTION, geom[i].id.slot);
					}
				}
			}
		}
	}
	return MeshFault{};
}

} // namespace

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

	const MeshFault embed = _self_intersection(p_mesh, faces);
	if (!embed.ok()) {
		return embed;
	}
	if (signed_volume_6x(p_mesh) <= 0) {
		return fault(MeshError::INVERTED_VOLUME);
	}
	return MeshFault{};
}

} // namespace slab
