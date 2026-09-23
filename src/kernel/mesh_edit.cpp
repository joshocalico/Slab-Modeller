#include "mesh_edit.hpp"
#include "surface_attrs_interpolate.hpp"

#include <algorithm>
#include <cstdint>
#include <cmath>
#include <map>
#include <unordered_map>
#include <vector>

namespace slab {

static bool _collinear(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c) {
	const int64_t bx = int64_t(p_b.x) - p_a.x;
	const int64_t by = int64_t(p_b.y) - p_a.y;
	const int64_t bz = int64_t(p_b.z) - p_a.z;
	const int64_t cx = int64_t(p_c.x) - p_a.x;
	const int64_t cy = int64_t(p_c.y) - p_a.y;
	const int64_t cz = int64_t(p_c.z) - p_a.z;
	return by * cz - bz * cy == 0 && bz * cx - bx * cz == 0 && bx * cy - by * cx == 0;
}

static bool _planar(const std::vector<IVec3> &p_pts) {
	const int n = int(p_pts.size());
	int c = -1;
	for (int k = 2; k < n; k++) {
		if (!_collinear(p_pts[0], p_pts[1], p_pts[k])) {
			c = k;
			break;
		}
	}
	if (c < 0) {
		return false;
	}
	for (int k = c + 1; k < n; k++) {
		if (orient3d(p_pts[0], p_pts[1], p_pts[c], p_pts[k]) != 0) {
			return false;
		}
	}
	return true;
}

static void _project(const IVec3 &p, int p_axis, int32_t &r_x, int32_t &r_y) {
	if (p_axis == 0) { r_x = p.y; r_y = p.z; }
	else if (p_axis == 1) { r_x = p.x; r_y = p.z; }
	else { r_x = p.x; r_y = p.y; }
}

static int _orient_2d(const IVec3 &a, const IVec3 &b, const IVec3 &c, int p_axis) {
	int32_t ax, ay, bx, by, cx, cy;
	_project(a, p_axis, ax, ay); _project(b, p_axis, bx, by); _project(c, p_axis, cx, cy);
	return orient2d(ax, ay, bx, by, cx, cy);
}

static bool _on_segment(const IVec3 &p, const IVec3 &a, const IVec3 &b, int p_axis) {
	if (_orient_2d(a, b, p, p_axis) != 0) return false;
	int32_t px, py, ax, ay, bx, by;
	_project(p, p_axis, px, py); _project(a, p_axis, ax, ay); _project(b, p_axis, bx, by);
	return px >= std::min(ax, bx) && px <= std::max(ax, bx) && py >= std::min(ay, by) && py <= std::max(ay, by);
}

static bool _simple_planar_loop(const std::vector<IVec3> &p_loop) {
	if (p_loop.size() < 3 || !_planar(p_loop)) return false;
	int axis = 2;
	__int128 area_x = 0, area_y = 0, area_z = 0;
	for (size_t i = 0; i < p_loop.size(); i++) {
		const IVec3 &a = p_loop[i], &b = p_loop[(i + 1) % p_loop.size()];
		area_x += (__int128)a.y * b.z - (__int128)a.z * b.y;
		area_y += (__int128)a.z * b.x - (__int128)a.x * b.z;
		area_z += (__int128)a.x * b.y - (__int128)a.y * b.x;
	}
	if (area_x == 0 && area_y == 0 && area_z == 0) return false;
	for (size_t i = 0; i + 2 < p_loop.size(); i++) {
		const int64_t ux = int64_t(p_loop[i + 1].x) - p_loop[i].x;
		const int64_t uy = int64_t(p_loop[i + 1].y) - p_loop[i].y;
		const int64_t uz = int64_t(p_loop[i + 1].z) - p_loop[i].z;
		const int64_t vx = int64_t(p_loop[i + 2].x) - p_loop[i].x;
		const int64_t vy = int64_t(p_loop[i + 2].y) - p_loop[i].y;
		const int64_t vz = int64_t(p_loop[i + 2].z) - p_loop[i].z;
		const __int128 nx = (__int128)uy * vz - (__int128)uz * vy;
		const __int128 ny = (__int128)uz * vx - (__int128)ux * vz;
		const __int128 nz = (__int128)ux * vy - (__int128)uy * vx;
		if (nx || ny || nz) {
			const __int128 ax = nx < 0 ? -nx : nx, ay = ny < 0 ? -ny : ny, az = nz < 0 ? -nz : nz;
			axis = ax >= ay && ax >= az ? 0 : (ay >= az ? 1 : 2);
			break;
		}
	}
	const int n = int(p_loop.size());
	for (int i = 0; i < n; i++) {
		const int in = (i + 1) % n;
		if (p_loop[i] == p_loop[in]) return false;
		if (_on_segment(p_loop[(i + 2) % n], p_loop[i], p_loop[in], axis)) return false;
		for (int j = i + 1; j < n; j++) {
			const int jn = (j + 1) % n;
			if (j == i || j == in || jn == i) continue;
			const int o1 = _orient_2d(p_loop[i], p_loop[in], p_loop[j], axis);
			const int o2 = _orient_2d(p_loop[i], p_loop[in], p_loop[jn], axis);
			const int o3 = _orient_2d(p_loop[j], p_loop[jn], p_loop[i], axis);
			const int o4 = _orient_2d(p_loop[j], p_loop[jn], p_loop[in], axis);
			if ((o1 != o2 && o1 != 0 && o2 != 0 && o3 != o4 && o3 != 0 && o4 != 0) ||
					_on_segment(p_loop[j], p_loop[i], p_loop[in], axis) || _on_segment(p_loop[jn], p_loop[i], p_loop[in], axis) ||
					_on_segment(p_loop[i], p_loop[j], p_loop[jn], axis) || _on_segment(p_loop[in], p_loop[j], p_loop[jn], axis)) return false;
		}
	}
	return true;
}

MeshEdit MeshEdit::empty() {
	return MeshEdit();
}

MeshEdit::MeshEdit(const Mesh &p_base) :
		work(p_base) {
}

VertexIdx MeshEdit::_alloc_vertex(IVec3 p_pos) {
	Vertex v;
	v.gen = 1;
	v.pos = p_pos;
	v.out = HalfEdgeIdx{ INVALID_IDX };
	if (!work.free_vertices.empty()) {
		const uint32_t slot = work.free_vertices.back();
		work.free_vertices.pop_back();
		v.gen = work.vertices[slot].gen + 1;
		if (v.gen == 0) {
			v.gen = 1;
		}
		work.vertices[slot] = v;
		return VertexIdx{ slot };
	}
	work.vertices.push_back(v);
	return VertexIdx{ uint32_t(work.vertices.size() - 1) };
}

HalfEdgeIdx MeshEdit::_alloc_half_edge() {
	HalfEdge e;
	e.gen = 1;
	e.next = HalfEdgeIdx{ INVALID_IDX };
	e.twin = HalfEdgeIdx{ INVALID_IDX };
	e.origin = VertexIdx{ INVALID_IDX };
	e.face = FaceIdx{ INVALID_IDX };
	if (!work.free_half_edges.empty()) {
		const uint32_t slot = work.free_half_edges.back();
		work.free_half_edges.pop_back();
		e.gen = work.half_edges[slot].gen + 1;
		if (e.gen == 0) {
			e.gen = 1;
		}
		work.half_edges[slot] = e;
		return HalfEdgeIdx{ slot };
	}
	work.half_edges.push_back(e);
	return HalfEdgeIdx{ uint32_t(work.half_edges.size() - 1) };
}

FaceIdx MeshEdit::_alloc_face() {
	Face f;
	f.gen = 1;
	f.he = HalfEdgeIdx{ INVALID_IDX };
	if (!work.free_faces.empty()) {
		const uint32_t slot = work.free_faces.back();
		work.free_faces.pop_back();
		f.gen = work.faces[slot].gen + 1;
		if (f.gen == 0) {
			f.gen = 1;
		}
		work.faces[slot] = f;
		return FaceIdx{ slot };
	}
	work.faces.push_back(f);
	return FaceIdx{ uint32_t(work.faces.size() - 1) };
}

void MeshEdit::free_vertex(VertexIdx p_v) {
	if (p_v.i == INVALID_IDX || !work._vertex_live(p_v.i)) {
		return;
	}
	Vertex &v = work.vertices[p_v.i];
	v.gen++;
	if (v.gen == 0) {
		v.gen = 1;
	}
	v.out = HalfEdgeIdx{ INVALID_IDX };
	work.free_vertices.push_back(p_v.i);
}

void MeshEdit::free_half_edge(HalfEdgeIdx p_he) {
	if (p_he.i == INVALID_IDX || !work._he_live(p_he.i)) {
		return;
	}
	HalfEdge &he = work.half_edges[p_he.i];
	he.gen++;
	if (he.gen == 0) {
		he.gen = 1;
	}
	he.next = HalfEdgeIdx{ INVALID_IDX };
	he.twin = HalfEdgeIdx{ INVALID_IDX };
	he.origin = VertexIdx{ INVALID_IDX };
	he.face = FaceIdx{ INVALID_IDX };
	work.free_half_edges.push_back(p_he.i);
}

void MeshEdit::free_face(FaceIdx p_f) {
	if (p_f.i == INVALID_IDX || !work._face_live(p_f.i)) {
		return;
	}
	Face &f = work.faces[p_f.i];
	f.gen++;
	if (f.gen == 0) {
		f.gen = 1;
	}
	f.he = HalfEdgeIdx{ INVALID_IDX };
	work.free_faces.push_back(p_f.i);
}

bool MeshEdit::loop_of(FaceId p_face, std::vector<HalfEdgeIdx> &r_out) {
	r_out.clear();
	if (!work.alive(p_face)) {
		fault.code = MeshError::STALE_HANDLE;
		fault.slot = p_face.slot;
		return false;
	}
	const HalfEdgeIdx start = work.faces[p_face.slot].he;
	HalfEdgeIdx he = start;
	while (he.i != INVALID_IDX && work._he_live(he.i) && r_out.size() <= work.half_edges.size()) {
		r_out.push_back(he);
		he = work.half_edges[he.i].next;
		if (he.i == start.i) {
			if (r_out.size() >= 3) {
				return true;
			}
			break;
		}
	}
	fault.code = MeshError::LOOP_TOO_SHORT;
	fault.slot = p_face.slot;
	r_out.clear();
	return false;
}

int MeshEdit::_valence(VertexIdx p_v) const {
	int n = 0;
	for (uint32_t i = 0; i < work.half_edges.size(); i++) {
		if (work._he_live(i) && work.half_edges[i].origin.i == p_v.i) {
			n++;
		}
	}
	return n;
}

VertexId MeshEdit::_id(VertexIdx p_v) const {
	return VertexId{ p_v.i, work.vertices[p_v.i].gen };
}

FaceId MeshEdit::_id(FaceIdx p_f) const {
	return FaceId{ p_f.i, work.faces[p_f.i].gen };
}

EdgeId MeshEdit::_id(HalfEdgeIdx p_he) const {
	const uint32_t twin = work.half_edges[p_he.i].twin.i;
	const uint32_t slot = (twin != INVALID_IDX && twin < p_he.i) ? twin : p_he.i;
	return EdgeId{ slot, work.half_edges[slot].gen };
}

FaceId MeshEdit::make_lamina(const IVec3 *p_loop, int p_count) {
	fault = MeshFault{};
	if (p_loop == nullptr || p_count < 3) {
		fault.code = MeshError::LOOP_TOO_SHORT;
		return FaceId{};
	}
	for (int i = 3; i < p_count; i++) {
		if (orient3d(p_loop[0], p_loop[1], p_loop[2], p_loop[i]) != 0) {
			fault.code = MeshError::DEGENERATE_FACE;
			return FaceId{};
		}
	}
	std::vector<VertexIdx> vs(p_count);
	for (int i = 0; i < p_count; i++) {
		vs[i] = _alloc_vertex(p_loop[i]);
	}
	std::vector<HalfEdgeIdx> front(p_count);
	std::vector<HalfEdgeIdx> back(p_count);
	for (int i = 0; i < p_count; i++) {
		front[i] = _alloc_half_edge();
		back[i] = _alloc_half_edge();
	}
	const FaceIdx f_front = _alloc_face();
	const FaceIdx f_back = _alloc_face();
	work.faces[f_front.i].he = front[0];
	work.faces[f_back.i].he = back[0];
	for (int i = 0; i < p_count; i++) {
		const int n = (i + 1) % p_count;
		const int p = (i + p_count - 1) % p_count;
		HalfEdge &hf = work.half_edges[front[i].i];
		hf.origin = vs[i];
		hf.next = front[n];
		hf.twin = back[i];
		hf.face = f_front;
		HalfEdge &hb = work.half_edges[back[i].i];
		hb.origin = vs[n];
		hb.next = back[p];
		hb.twin = front[i];
		hb.face = f_back;
		work.vertices[vs[i].i].out = front[i];
	}
	return _id(f_front);
}

FaceId MeshEdit::lift_loop(FaceId p_face) {
	fault = MeshFault{};
	std::vector<HalfEdgeIdx> loop;
	if (!loop_of(p_face, loop)) {
		return FaceId{};
	}
	const int n = int(loop.size());

	const FaceAttrs attrs = work.faces[p_face.slot].attrs;
	std::vector<CornerAttrs> old_corners(n);
	std::vector<VertexIdx> old_v(n);
	std::vector<HalfEdgeIdx> old_twin(n);
	for (int i = 0; i < n; i++) {
		old_corners[i] = work.half_edges[loop[i].i].corner;
		old_v[i] = work.half_edges[loop[i].i].origin;
		old_twin[i] = work.half_edges[loop[i].i].twin;
	}

	std::vector<VertexIdx> nv(n);
	std::vector<HalfEdgeIdx> side_a(n);
	std::vector<HalfEdgeIdx> side_b(n);
	std::vector<HalfEdgeIdx> side_c(n);
	std::vector<HalfEdgeIdx> side_d(n);
	std::vector<FaceIdx> sides(n);
	for (int i = 0; i < n; i++) {
		nv[i] = _alloc_vertex(work.vertices[old_v[i].i].pos);
		side_a[i] = _alloc_half_edge();
		side_b[i] = _alloc_half_edge();
		side_c[i] = _alloc_half_edge();
		side_d[i] = _alloc_half_edge();
		sides[i] = _alloc_face();
		work.faces[sides[i].i].attrs = attrs;
		work.faces[sides[i].i].attrs.uv_unwrapped = false;
		work.faces[sides[i].i].he = side_a[i];
	}

	for (int i = 0; i < n; i++) {
		const int nxi = (i + 1) % n;
		const int pri = (i + n - 1) % n;

		HalfEdge &cap = work.half_edges[loop[i].i];
		cap.origin = nv[i];
		cap.twin = side_b[i];
		work.vertices[nv[i].i].out = loop[i];

		HalfEdge &b = work.half_edges[side_b[i].i];
		b.origin = nv[nxi];
		b.next = side_a[i];
		b.twin = loop[i];
		b.face = sides[i];
		b.uv_seam = cap.uv_seam;
		b.hard = cap.hard;
		b.corner.surface = old_corners[nxi].surface;

		HalfEdge &a = work.half_edges[side_a[i].i];
		a.origin = nv[i];
		a.next = side_d[i];
		a.twin = side_c[pri];
		a.face = sides[i];
		a.corner.surface = old_corners[i].surface;

		HalfEdge &d = work.half_edges[side_d[i].i];
		d.origin = old_v[i];
		d.next = side_c[i];
		d.twin = old_twin[i];
		d.face = sides[i];
		d.uv_seam = work.half_edges[old_twin[i].i].uv_seam;
		d.hard = work.half_edges[old_twin[i].i].hard;
		d.corner.surface = old_corners[i].surface;

		HalfEdge &c = work.half_edges[side_c[i].i];
		c.origin = old_v[nxi];
		c.next = side_b[i];
		c.twin = side_a[nxi];
		c.face = sides[i];
		c.corner.surface = old_corners[nxi].surface;
		// New wall normals follow wall geometry, while its vertex channels and
		// deformation follow the corresponding source cap endpoints.
		for (HalfEdge *side : {&a, &b, &c, &d})
			side->corner.surface.flags &= ~(SurfaceAttrs::NORMAL | SurfaceAttrs::TANGENT);

		work.half_edges[old_twin[i].i].twin = side_d[i];
		work.vertices[old_v[i].i].out = side_d[i];
	}

	return p_face;
}

VertexId MeshEdit::split_edge(EdgeId p_edge, IVec3 p_pos) {
	fault = MeshFault{};
	if (!work.alive(p_edge)) {
		fault.code = MeshError::STALE_HANDLE;
		fault.slot = p_edge.slot;
		return VertexId{};
	}
	const HalfEdgeIdx a{ p_edge.slot };
	const HalfEdgeIdx b = work.half_edges[a.i].twin;
	const VertexIdx v0 = work.half_edges[a.i].origin;
	const VertexIdx v1 = work.half_edges[b.i].origin;
	if (work.vertices[v0.i].pos == p_pos || work.vertices[v1.i].pos == p_pos) {
		fault.code = MeshError::DEGENERATE_FACE;
		fault.slot = p_edge.slot;
		return VertexId{};
	}

	const VertexIdx m = _alloc_vertex(p_pos);
	const HalfEdgeIdx a2 = _alloc_half_edge();
	const HalfEdgeIdx b2 = _alloc_half_edge();

	HalfEdge &ha = work.half_edges[a.i];
	HalfEdge &hb = work.half_edges[b.i];
	HalfEdge &ha2 = work.half_edges[a2.i];
	HalfEdge &hb2 = work.half_edges[b2.i];

	ha2.origin = m;
	ha2.next = ha.next;
	ha2.twin = b;
	ha2.face = ha.face;
	ha2.uv_seam = ha.uv_seam;
	ha2.hard = ha.hard;

	hb2.origin = m;
	hb2.next = hb.next;
	hb2.twin = a;
	hb2.face = hb.face;
	hb2.uv_seam = hb.uv_seam;
	hb2.hard = hb.hard;
	const godot::Vector3 start = dequantize(work.vertices[v0.i].pos);
	const godot::Vector3 delta = dequantize(work.vertices[v1.i].pos) - start;
	const float t = float((dequantize(p_pos) - start).dot(delta) / delta.length_squared());
	const CornerAttrs &an = work.half_edges[ha.next.i].corner;
	const CornerAttrs &bn = work.half_edges[hb.next.i].corner;
	ha2.corner.surface = lerp_surface_attrs(ha.corner.surface, an.surface, t);
	hb2.corner.surface = lerp_surface_attrs(hb.corner.surface, bn.surface, 1.0f - t);
	if (ha.corner.uv_explicit && an.uv_explicit) {
		ha2.corner.uv_explicit = true;
		ha2.corner.uv = ha.corner.uv.lerp(an.uv, t);
	}
	if (hb.corner.uv_explicit && bn.uv_explicit) {
		hb2.corner.uv_explicit = true;
		hb2.corner.uv = hb.corner.uv.lerp(bn.uv, 1.0f - t);
	}

	ha.next = a2;
	ha.twin = b2;
	hb.next = b2;
	hb.twin = a2;

	work.vertices[m.i].out = a2;
	return _id(m);
}

EdgeId MeshEdit::split_face(FaceId p_face, VertexId p_a, VertexId p_b) {
	fault = MeshFault{};
	std::vector<HalfEdgeIdx> loop;
	if (!loop_of(p_face, loop)) {
		return EdgeId{};
	}
	if (!work.alive(p_a) || !work.alive(p_b)) {
		fault.code = MeshError::STALE_HANDLE;
		fault.slot = work.alive(p_a) ? p_b.slot : p_a.slot;
		return EdgeId{};
	}
	if (p_a.slot == p_b.slot) {
		fault.code = MeshError::INVALID_SELECTION;
		fault.slot = p_a.slot;
		return EdgeId{};
	}

	const int n = int(loop.size());
	int i = -1;
	int j = -1;
	for (int k = 0; k < n; k++) {
		const uint32_t origin = work.half_edges[loop[k].i].origin.i;
		if (origin == p_a.slot && i < 0) {
			i = k;
		}
		if (origin == p_b.slot && j < 0) {
			j = k;
		}
	}
	if (i < 0 || j < 0) {
		fault.code = MeshError::INVALID_SELECTION;
		fault.slot = i < 0 ? p_a.slot : p_b.slot;
		return EdgeId{};
	}
	if (i > j) {
		const int swap = i;
		i = j;
		j = swap;
	}
	if (j == i + 1 || (i == 0 && j == n - 1)) {
		fault.code = MeshError::ADJACENT_SELECTION;
		fault.slot = p_face.slot;
		return EdgeId{};
	}

	const HalfEdgeIdx cut = _alloc_half_edge();
	const HalfEdgeIdx cut_twin = _alloc_half_edge();
	const FaceIdx split = _alloc_face();
	const FaceIdx kept{ p_face.slot };
	work.faces[split.i].attrs = work.faces[kept.i].attrs;

	HalfEdge &hc = work.half_edges[cut.i];
	hc.origin = work.half_edges[loop[j].i].origin;
	hc.next = loop[i];
	hc.twin = cut_twin;
	hc.face = kept;
	hc.corner = work.half_edges[loop[j].i].corner;

	HalfEdge &ht = work.half_edges[cut_twin.i];
	ht.origin = work.half_edges[loop[i].i].origin;
	ht.next = loop[j];
	ht.twin = cut;
	ht.face = split;
	ht.corner = work.half_edges[loop[i].i].corner;

	work.half_edges[loop[(j + n - 1) % n].i].next = cut;
	work.half_edges[loop[(i + n - 1) % n].i].next = cut_twin;
	for (int k = j; k != i; k = (k + 1) % n) {
		work.half_edges[loop[k].i].face = split;
	}

	work.faces[kept.i].he = loop[i];
	work.faces[split.i].he = loop[j];
	return _id(cut);
}

MeshFault MeshEdit::remove_face(FaceId p_face) {
	fault = MeshFault{};
	std::vector<HalfEdgeIdx> loop;
	if (!loop_of(p_face, loop)) {
		return fault;
	}
	for (const HalfEdgeIdx he : loop) {
		work.half_edges[he.i].face = FaceIdx{ INVALID_IDX };
	}
	free_face(FaceIdx{ p_face.slot });
	return fault;
}

MeshFault MeshEdit::dissolve_edge(EdgeId p_edge) {
	fault = MeshFault{};
	if (!work.alive(p_edge)) {
		fault.code = MeshError::STALE_HANDLE;
		fault.slot = p_edge.slot;
		return fault;
	}
	const HalfEdgeIdx a{ p_edge.slot };
	const HalfEdgeIdx b = work.half_edges[a.i].twin;
	const FaceIdx fa = work.half_edges[a.i].face;
	const FaceIdx fb = work.half_edges[b.i].face;
	if (fa.i == INVALID_IDX || fb.i == INVALID_IDX || !work._face_live(fa.i) || !work._face_live(fb.i)) {
		fault.code = MeshError::NOT_CLOSED;
		fault.slot = p_edge.slot;
		return fault;
	}
	if (fa.i == fb.i) {
		fault.code = MeshError::DEGENERATE_FACE;
		fault.slot = fa.i;
		return fault;
	}

	const VertexIdx v0 = work.half_edges[a.i].origin;
	const VertexIdx v1 = work.half_edges[b.i].origin;
	if (_valence(v0) < 3 || _valence(v1) < 3) {
		fault.code = MeshError::NON_MANIFOLD_VERTEX;
		fault.slot = _valence(v0) < 3 ? v0.i : v1.i;
		return fault;
	}

	std::vector<HalfEdgeIdx> la;
	std::vector<HalfEdgeIdx> lb;
	if (!loop_of(_id(fa), la) || !loop_of(_id(fb), lb)) {
		return fault;
	}
	int shared = 0;
	for (const HalfEdgeIdx he : la) {
		const HalfEdgeIdx twin = work.half_edges[he.i].twin;
		if (twin.i != INVALID_IDX && work._he_live(twin.i) && work.half_edges[twin.i].face.i == fb.i) {
			shared++;
		}
	}
	if (shared != 1) {
		fault.code = MeshError::ADJACENT_SELECTION;
		fault.slot = p_edge.slot;
		return fault;
	}

	std::vector<IVec3> merged;
	for (const HalfEdgeIdx he : la) {
		if (he.i != a.i) {
			merged.push_back(work.vertices[work.half_edges[he.i].origin.i].pos);
		}
	}
	for (const HalfEdgeIdx he : lb) {
		if (he.i != b.i) {
			merged.push_back(work.vertices[work.half_edges[he.i].origin.i].pos);
		}
	}
	if (!_planar(merged)) {
		fault.code = MeshError::DEGENERATE_FACE;
		fault.slot = p_edge.slot;
		return fault;
	}

	const int na = int(la.size());
	const int nb = int(lb.size());
	int ia = 0;
	int ib = 0;
	for (int k = 0; k < na; k++) {
		if (la[k].i == a.i) {
			ia = k;
		}
	}
	for (int k = 0; k < nb; k++) {
		if (lb[k].i == b.i) {
			ib = k;
		}
	}
	const HalfEdgeIdx prev_a = la[(ia + na - 1) % na];
	const HalfEdgeIdx prev_b = lb[(ib + nb - 1) % nb];
	const HalfEdgeIdx next_a = work.half_edges[a.i].next;
	const HalfEdgeIdx next_b = work.half_edges[b.i].next;
	std::vector<IVec3> boundary;
	HalfEdgeIdx cursor = next_b;
	while (cursor.i != b.i) {
		boundary.push_back(work.vertices[work.half_edges[cursor.i].origin.i].pos);
		cursor = work.half_edges[cursor.i].next;
	}
	cursor = next_a;
	while (cursor.i != a.i) {
		boundary.push_back(work.vertices[work.half_edges[cursor.i].origin.i].pos);
		cursor = work.half_edges[cursor.i].next;
	}
	if (!_simple_planar_loop(boundary)) {
		fault.code = MeshError::DEGENERATE_FACE;
		fault.slot = p_edge.slot;
		return fault;
	}

	work.half_edges[prev_a.i].next = next_b;
	work.half_edges[prev_b.i].next = next_a;
	for (const HalfEdgeIdx he : lb) {
		if (he.i != b.i) {
			work.half_edges[he.i].face = fa;
		}
	}
	work.faces[fa.i].he = prev_a;
	work.vertices[v0.i].out = next_b;
	work.vertices[v1.i].out = next_a;

	free_face(fb);
	free_half_edge(a);
	free_half_edge(b);
	return fault;
}

MeshFault MeshEdit::merge_face_region(const std::vector<FaceId> &p_faces) {
	fault = MeshFault{};
	if (p_faces.size() < 2) {
		fault.code = MeshError::INVALID_SELECTION;
		return fault;
	}
	std::unordered_map<uint32_t, bool> selected;
	for (const FaceId id : p_faces) {
		if (!work.alive(id)) {
			fault.code = MeshError::STALE_HANDLE;
			fault.slot = id.slot;
			return fault;
		}
		if (!selected.emplace(id.slot, true).second) {
			fault.code = MeshError::INVALID_SELECTION;
			fault.slot = id.slot;
			return fault;
		}
	}

	std::vector<HalfEdgeIdx> boundary;
	std::vector<HalfEdgeIdx> internal;
	std::vector<VertexIdx> region_vertices;
	std::unordered_map<uint32_t, bool> seen_vertices;
	for (const FaceId id : p_faces) {
		std::vector<HalfEdgeIdx> loop;
		if (!loop_of(id, loop)) {
			return fault;
		}
		for (const HalfEdgeIdx he : loop) {
			const VertexIdx origin = work.half_edges[he.i].origin;
			if (seen_vertices.emplace(origin.i, true).second) {
				region_vertices.push_back(origin);
			}
			const HalfEdgeIdx twin = work.half_edges[he.i].twin;
			const FaceIdx other = twin.i == INVALID_IDX ? FaceIdx{ INVALID_IDX } : work.half_edges[twin.i].face;
			if (other.i != INVALID_IDX && selected.find(other.i) != selected.end()) {
				internal.push_back(he);
			} else {
				boundary.push_back(he);
			}
		}
	}
	if (boundary.size() < 3) {
		fault.code = MeshError::INVALID_SELECTION;
		return fault;
	}
	std::unordered_map<uint32_t, std::vector<uint32_t>> graph;
	for (const HalfEdgeIdx he : internal) {
		const HalfEdgeIdx twin = work.half_edges[he.i].twin;
		graph[work.half_edges[he.i].face.i].push_back(work.half_edges[twin.i].face.i);
	}
	std::unordered_map<uint32_t, bool> reached;
	std::vector<uint32_t> stack{ p_faces[0].slot };
	while (!stack.empty()) {
		const uint32_t face = stack.back();
		stack.pop_back();
		if (!reached.emplace(face, true).second) continue;
		for (const uint32_t next : graph[face]) stack.push_back(next);
	}
	if (reached.size() != selected.size()) {
		fault.code = MeshError::INVALID_SELECTION;
		fault.slot = p_faces[0].slot;
		return fault;
	}

	std::unordered_map<uint32_t, HalfEdgeIdx> by_origin;
	std::unordered_map<uint32_t, int> arrivals;
	for (const HalfEdgeIdx he : boundary) {
		const uint32_t origin = work.half_edges[he.i].origin.i;
		const HalfEdgeIdx twin = work.half_edges[he.i].twin;
		if (twin.i == INVALID_IDX || !work._he_live(twin.i) || !by_origin.emplace(origin, he).second) {
			fault.code = MeshError::INVALID_SELECTION;
			fault.slot = p_faces[0].slot;
			return fault;
		}
		arrivals[work.half_edges[twin.i].origin.i]++;
	}
	for (const auto &entry : by_origin) {
		if (arrivals[entry.first] != 1) {
			fault.code = MeshError::INVALID_SELECTION;
			fault.slot = p_faces[0].slot;
			return fault;
		}
	}
	std::vector<HalfEdgeIdx> ordered;
	std::unordered_map<uint32_t, bool> seen_boundary;
	HalfEdgeIdx cursor = boundary[0];
	for (size_t guard = 0; guard < boundary.size(); guard++) {
		if (!ordered.empty() && cursor.i == boundary[0].i) {
			break;
		}
		if (!seen_boundary.emplace(cursor.i, true).second) {
			fault.code = MeshError::INVALID_SELECTION;
			fault.slot = p_faces[0].slot;
			return fault;
		}
		ordered.push_back(cursor);
		const HalfEdgeIdx twin = work.half_edges[cursor.i].twin;
		const uint32_t destination = work.half_edges[twin.i].origin.i;
		const auto next = by_origin.find(destination);
		if (next == by_origin.end()) {
			fault.code = MeshError::INVALID_SELECTION;
			return fault;
		}
		cursor = next->second;
	}
	if (cursor.i == boundary[0].i && ordered.size() != boundary.size()) {
		fault.code = MeshError::MULTIPLE_BOUNDARY_LOOPS;
		fault.slot = p_faces[0].slot;
		return fault;
	}
	if (cursor.i != boundary[0].i) {
		fault.code = MeshError::INVALID_SELECTION;
		fault.slot = p_faces[0].slot;
		return fault;
	}
	std::vector<IVec3> points;
	for (const VertexIdx vertex : region_vertices) {
		points.push_back(work.vertices[vertex.i].pos);
	}
	if (!_planar(points)) {
		fault.code = MeshError::DEGENERATE_FACE;
		fault.slot = p_faces[0].slot;
		return fault;
	}

	const FaceIdx keep{ p_faces[0].slot };
	for (size_t i = 0; i < ordered.size(); i++) {
		HalfEdge &edge = work.half_edges[ordered[i].i];
		edge.face = keep;
		edge.next = ordered[(i + 1) % ordered.size()];
		work.vertices[edge.origin.i].out = ordered[i];
	}
	work.faces[keep.i].he = ordered[0];
	for (const HalfEdgeIdx he : internal) {
		free_half_edge(he);
	}
	for (size_t i = 1; i < p_faces.size(); i++) {
		free_face(FaceIdx{ p_faces[i].slot });
	}
	std::unordered_map<uint32_t, bool> used_vertices;
	for (uint32_t i = 0; i < work.half_edges.size(); i++) {
		if (work._he_live(i)) {
			used_vertices[work.half_edges[i].origin.i] = true;
		}
	}
	for (const VertexIdx vertex : region_vertices) {
		if (used_vertices.find(vertex.i) == used_vertices.end()) {
			free_vertex(vertex);
		}
	}
	return fault;
}

MeshFault MeshEdit::collapse_edge(EdgeId p_edge) {
	fault = MeshFault{};
	if (!work.alive(p_edge)) {
		fault.code = MeshError::STALE_HANDLE;
		fault.slot = p_edge.slot;
		return fault;
	}
	const HalfEdgeIdx a{ p_edge.slot };
	const HalfEdgeIdx b = work.half_edges[a.i].twin;
	const VertexIdx v_keep = work.half_edges[a.i].origin;
	const VertexIdx v_kill = work.half_edges[b.i].origin;
	if (v_keep.i == v_kill.i) {
		fault.code = MeshError::DEGENERATE_FACE;
		fault.slot = p_edge.slot;
		return fault;
	}
	const FaceIdx fa = work.half_edges[a.i].face;
	const FaceIdx fb = work.half_edges[b.i].face;
	if (fa.i == INVALID_IDX || fb.i == INVALID_IDX || !work._face_live(fa.i) || !work._face_live(fb.i)) {
		fault.code = MeshError::NOT_CLOSED;
		fault.slot = p_edge.slot;
		return fault;
	}
	std::vector<HalfEdgeIdx> la;
	std::vector<HalfEdgeIdx> lb;
	if (!loop_of(_id(fa), la) || !loop_of(_id(fb), lb)) {
		return fault;
	}
	if (la.size() < 4 || lb.size() < 4) {
		fault.code = MeshError::LOOP_TOO_SHORT;
		fault.slot = p_edge.slot;
		return fault;
	}

	HalfEdgeIdx prev_a;
	HalfEdgeIdx prev_b;
	for (const HalfEdgeIdx he : la) {
		if (work.half_edges[he.i].next.i == a.i) {
			prev_a = he;
		}
	}
	for (const HalfEdgeIdx he : lb) {
		if (work.half_edges[he.i].next.i == b.i) {
			prev_b = he;
		}
	}
	const HalfEdgeIdx next_a = work.half_edges[a.i].next;
	const HalfEdgeIdx next_b = work.half_edges[b.i].next;

	for (uint32_t i = 0; i < work.half_edges.size(); i++) {
		if (!work._he_live(i)) {
			continue;
		}
		if (work.half_edges[i].origin.i == v_kill.i) {
			work.half_edges[i].origin = v_keep;
		}
	}

	work.half_edges[prev_a.i].next = next_a;
	work.half_edges[prev_b.i].next = next_b;
	if (work.faces[fa.i].he.i == a.i) {
		work.faces[fa.i].he = next_a;
	}
	if (work.faces[fb.i].he.i == b.i) {
		work.faces[fb.i].he = next_b;
	}
	work.vertices[v_keep.i].out = next_a;

	free_half_edge(a);
	free_half_edge(b);
	free_vertex(v_kill);
	return fault;
}

MeshFault MeshEdit::flip_face(FaceId p_face) {
	fault = MeshFault{};
	std::vector<HalfEdgeIdx> loop;
	if (!loop_of(p_face, loop)) {
		return fault;
	}
	const int n = int(loop.size());
	std::vector<VertexIdx> origins(n);
	std::vector<CornerAttrs> corners(n);
	for (int i = 0; i < n; i++) {
		origins[i] = work.half_edges[loop[i].i].origin;
		corners[i] = work.half_edges[loop[i].i].corner;
	}
	for (int i = 0; i < n; i++) {
		const VertexIdx origin = origins[(i + 1) % n];
		HalfEdge &he = work.half_edges[loop[i].i];
		he.next = loop[(i + n - 1) % n];
		he.origin = origin;
		he.corner = corners[(i + 1) % n];
		work.vertices[origin.i].out = loop[i];
	}
	return fault;
}

MeshFault MeshEdit::flip_all() {
	fault = MeshFault{};
	std::vector<FaceId> faces;
	work.all_faces(faces);
	for (const FaceId id : faces) {
		const MeshFault flipped = flip_face(id);
		if (!flipped.ok()) {
			return flipped;
		}
	}
	return fault;
}

void MeshEdit::move_vertex(VertexId p_v, IVec3 p_pos) {
	if (!work.alive(p_v)) {
		fault.code = MeshError::STALE_HANDLE;
		return;
	}
	work.vertices[p_v.slot].pos = p_pos;
}

void MeshEdit::set_uv_seam(EdgeId p_edge, bool p_marked) {
	if (!work.alive(p_edge)) {
		fault.code = MeshError::STALE_HANDLE;
		return;
	}
	work.half_edges[p_edge.slot].uv_seam = p_marked;
	const HalfEdgeIdx twin = work.half_edges[p_edge.slot].twin;
	if (twin.i != INVALID_IDX) work.half_edges[twin.i].uv_seam = p_marked;
}

void MeshEdit::set_hard_edge(EdgeId p_edge, bool p_hard) {
	if (!work.alive(p_edge)) { fault.code = MeshError::STALE_HANDLE; return; }
	work.half_edges[p_edge.slot].hard = p_hard;
	work.half_edges[work.half_edges[p_edge.slot].twin.i].hard = p_hard;
}

void MeshEdit::set_corner_attrs(FaceId p_face, uint32_t p_corner, const CornerAttrs &p_attrs) {
	std::vector<HalfEdgeIdx> loop;
	if (!loop_of(p_face, loop)) return;
	if (p_corner >= loop.size() || !valid_surface_attrs(p_attrs.surface) || !std::isfinite(p_attrs.uv.x) || !std::isfinite(p_attrs.uv.y)) {
		fault.code = MeshError::INVALID_SELECTION;
		return;
	}
	work.half_edges[loop[p_corner].i].corner = p_attrs;
}

void MeshEdit::set_attrs(FaceId p_face, const FaceAttrs &p_attrs) {
	if (!work.alive(p_face)) {
		fault.code = MeshError::STALE_HANDLE;
		return;
	}
	work.faces[p_face.slot].attrs = p_attrs;
}

MeshFault MeshEdit::replace_with(const Mesh &p_mesh) {
	work = p_mesh;
	fault = MeshFault{};
	return fault;
}

MeshFault MeshEdit::append(const Mesh &p_other, bool p_flip) {
	fault = MeshFault{};
	std::unordered_map<uint32_t, uint32_t> vmap;
	std::unordered_map<uint32_t, uint32_t> hmap;
	std::unordered_map<uint32_t, uint32_t> fmap;
	for (uint32_t i = 0; i < p_other.vertices.size(); i++) {
		if (!p_other._vertex_live(i)) {
			continue;
		}
		const VertexIdx nv = _alloc_vertex(p_other.vertices[i].pos);
		vmap[i] = nv.i;
	}
	for (uint32_t i = 0; i < p_other.half_edges.size(); i++) {
		if (!p_other._he_live(i)) {
			continue;
		}
		const HalfEdgeIdx nh = _alloc_half_edge();
		hmap[i] = nh.i;
	}
	std::vector<FaceId> new_faces;
	for (uint32_t i = 0; i < p_other.faces.size(); i++) {
		if (!p_other._face_live(i)) {
			continue;
		}
		const FaceIdx nf = _alloc_face();
		fmap[i] = nf.i;
		work.faces[nf.i].attrs = p_other.faces[i].attrs;
		new_faces.push_back(_id(nf));
	}
	for (const auto &kv : hmap) {
		const HalfEdge &src = p_other.half_edges[kv.first];
		HalfEdge &dst = work.half_edges[kv.second];
		if (hmap.find(src.next.i) == hmap.end() || hmap.find(src.twin.i) == hmap.end() || vmap.find(src.origin.i) == vmap.end() || fmap.find(src.face.i) == fmap.end()) {
			fault.code = MeshError::CORRUPT_DATA;
			return fault;
		}
		dst.next = HalfEdgeIdx{ hmap[src.next.i] };
		dst.twin = HalfEdgeIdx{ hmap[src.twin.i] };
		dst.origin = VertexIdx{ vmap[src.origin.i] };
		dst.face = FaceIdx{ fmap[src.face.i] };
		dst.uv_seam = src.uv_seam;
		dst.hard = src.hard;
		dst.corner = src.corner;
	}
	for (const auto &kv : vmap) {
		const uint32_t out = p_other.vertices[kv.first].out.i;
		if (hmap.find(out) == hmap.end()) {
			fault.code = MeshError::CORRUPT_DATA;
			return fault;
		}
		work.vertices[kv.second].out = HalfEdgeIdx{ hmap[out] };
	}
	for (const auto &kv : fmap) {
		const uint32_t he = p_other.faces[kv.first].he.i;
		if (hmap.find(he) == hmap.end()) {
			fault.code = MeshError::CORRUPT_DATA;
			return fault;
		}
		work.faces[kv.second].he = HalfEdgeIdx{ hmap[he] };
	}
	if (p_flip) {
		for (const FaceId id : new_faces) {
			const MeshFault flipped = flip_face(id);
			if (!flipped.ok()) {
				return flipped;
			}
		}
	}
	return fault;
}

MeshFault MeshEdit::assemble(const std::vector<std::vector<IVec3>> &p_loops) {
	fault = MeshFault{};
	std::map<std::pair<IVec3, IVec3>, bool> seams, hard_edges;
	std::vector<EdgeId> old_edges;
	work.all_edges(old_edges);
	for (const EdgeId edge : old_edges) {
		if (!work.edge_uv_seam(edge) && !work.edge_hard(edge)) continue;
		VertexId a, b;
		work.edge_vertices(edge, a, b);
		IVec3 pa = work.position_i(a), pb = work.position_i(b);
		if (pb < pa) std::swap(pa, pb);
		if (work.edge_uv_seam(edge)) seams[{pa, pb}] = true;
		if (work.edge_hard(edge)) hard_edges[{pa, pb}] = true;
	}
	work = Mesh();
	if (p_loops.empty()) {
		fault.code = MeshError::RESULT_EMPTY;
		return fault;
	}

	std::map<IVec3, VertexIdx> verts;
	std::unordered_map<uint64_t, HalfEdgeIdx> directed;
	auto key = [](uint32_t p_a, uint32_t p_b) -> uint64_t {
		return (uint64_t(p_a) << 32) | uint64_t(p_b);
	};

	for (const std::vector<IVec3> &raw : p_loops) {
		std::vector<IVec3> loop;
		loop.reserve(raw.size());
		for (const IVec3 &p : raw) {
			if (loop.empty() || loop.back() != p) {
				loop.push_back(p);
			}
		}
		if (loop.size() >= 2 && loop.front() == loop.back()) {
			loop.pop_back();
		}
		if (loop.size() < 3) {
			continue;
		}
		bool dup = false;
		for (size_t i = 0; i < loop.size() && !dup; i++) {
			for (size_t j = i + 1; j < loop.size(); j++) {
				if (loop[i] == loop[j]) {
					dup = true;
					break;
				}
			}
		}
		if (dup) {
			continue;
		}

		std::vector<VertexIdx> vs(loop.size());
		for (size_t i = 0; i < loop.size(); i++) {
			const auto found = verts.find(loop[i]);
			if (found != verts.end()) {
				vs[i] = found->second;
			} else {
				vs[i] = _alloc_vertex(loop[i]);
				verts[loop[i]] = vs[i];
			}
		}
		bool dup_edge = false;
		for (size_t i = 0; i < loop.size(); i++) {
			const size_t n = (i + 1) % loop.size();
			if (directed.find(key(vs[i].i, vs[n].i)) != directed.end()) {
				dup_edge = true;
				break;
			}
		}
		if (dup_edge) {
			continue;
		}

		std::vector<HalfEdgeIdx> hes(loop.size());
		const FaceIdx face = _alloc_face();
		for (size_t i = 0; i < loop.size(); i++) {
			hes[i] = _alloc_half_edge();
		}
		work.faces[face.i].he = hes[0];
		for (size_t i = 0; i < loop.size(); i++) {
			const size_t n = (i + 1) % loop.size();
			HalfEdge &he = work.half_edges[hes[i].i];
			he.origin = vs[i];
			he.next = hes[n];
			he.twin = HalfEdgeIdx{ INVALID_IDX };
			he.face = face;
			work.vertices[vs[i].i].out = hes[i];
			directed[key(vs[i].i, vs[n].i)] = hes[i];
		}
	}

	auto add_face = [&](const std::vector<VertexIdx> &vs) -> bool {
		if (vs.size() < 3) {
			return false;
		}
		for (size_t i = 0; i < vs.size(); i++) {
			const size_t n = (i + 1) % vs.size();
			if (directed.find(key(vs[i].i, vs[n].i)) != directed.end()) {
				return false;
			}
		}
		std::vector<HalfEdgeIdx> hes(vs.size());
		const FaceIdx face = _alloc_face();
		for (size_t i = 0; i < vs.size(); i++) {
			hes[i] = _alloc_half_edge();
		}
		work.faces[face.i].he = hes[0];
		for (size_t i = 0; i < vs.size(); i++) {
			const size_t n = (i + 1) % vs.size();
			HalfEdge &he = work.half_edges[hes[i].i];
			he.origin = vs[i];
			he.next = hes[n];
			he.twin = HalfEdgeIdx{ INVALID_IDX };
			he.face = face;
			work.vertices[vs[i].i].out = hes[i];
			directed[key(vs[i].i, vs[n].i)] = hes[i];
		}
		return true;
	};

	std::unordered_map<uint32_t, uint32_t> unmatched_next;
	for (const auto &kv : directed) {
		const uint32_t a = uint32_t(kv.first >> 32);
		const uint32_t b = uint32_t(kv.first);
		if (directed.find(key(b, a)) == directed.end()) {
			unmatched_next[a] = b;
		}
	}
	while (!unmatched_next.empty()) {
		std::vector<VertexIdx> cycle;
		uint32_t start = unmatched_next.begin()->first;
		uint32_t cur = start;
		while (true) {
			cycle.push_back(VertexIdx{ cur });
			const auto found = unmatched_next.find(cur);
			if (found == unmatched_next.end()) {
				fault.code = MeshError::NOT_CLOSED;
				return fault;
			}
			const uint32_t nxt = found->second;
			unmatched_next.erase(found);
			cur = nxt;
			if (cur == start) {
				break;
			}
			if (cycle.size() > work.vertices.size() + 2) {
				fault.code = MeshError::NOT_CLOSED;
				return fault;
			}
		}
		if (cycle.size() < 3) {
			fault.code = MeshError::NOT_CLOSED;
			return fault;
		}
		std::vector<VertexIdx> rev;
		rev.reserve(cycle.size());
		rev.push_back(cycle[0]);
		for (size_t i = cycle.size() - 1; i > 0; i--) {
			rev.push_back(cycle[i]);
		}
		if (!add_face(rev)) {
			fault.code = MeshError::NOT_CLOSED;
			return fault;
		}
	}

	if (work.face_count() < 1) {
		fault.code = MeshError::RESULT_EMPTY;
		return fault;
	}
	for (const auto &kv : directed) {
		const uint32_t a = uint32_t(kv.first >> 32);
		const uint32_t b = uint32_t(kv.first);
		const auto twin = directed.find(key(b, a));
		if (twin == directed.end()) {
			fault.code = MeshError::NOT_CLOSED;
			return fault;
		}
		work.half_edges[kv.second.i].twin = twin->second;
		const HalfEdge &he = work.half_edges[kv.second.i];
		IVec3 pa = work.vertices[he.origin.i].pos;
		IVec3 pb = work.vertices[work.half_edges[he.next.i].origin.i].pos;
		if (pb < pa) std::swap(pa, pb);
		work.half_edges[kv.second.i].uv_seam = seams.count({pa, pb}) != 0;
		work.half_edges[kv.second.i].hard = hard_edges.count({pa, pb}) != 0;
	}
	return fault;
}

MeshFault MeshEdit::commit(Mesh &r_out) && {
	if (!fault.ok()) {
		return fault;
	}
	const MeshFault v = validate(work);
	if (!v.ok()) {
		return v;
	}
	r_out = std::move(work);
	return MeshFault{};
}

} // namespace slab
