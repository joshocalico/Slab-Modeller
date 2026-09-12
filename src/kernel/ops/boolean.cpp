#include "boolean.hpp"

#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

namespace slab {
namespace ops {

namespace {

MeshFault _bad(MeshError p_code) {
	MeshFault f;
	f.code = p_code;
	return f;
}

bool _aabb_disjoint(const godot::AABB &p_a, const godot::AABB &p_b) {
	return !p_a.intersects(p_b);
}

bool _aabb_strictly_encloses(const godot::AABB &p_outer, const godot::AABB &p_inner) {
	if (!p_outer.encloses(p_inner)) {
		return false;
	}
	const godot::Vector3 a0 = p_outer.position;
	const godot::Vector3 a1 = p_outer.position + p_outer.size;
	const godot::Vector3 b0 = p_inner.position;
	const godot::Vector3 b1 = p_inner.position + p_inner.size;
	return b0.x > a0.x && b0.y > a0.y && b0.z > a0.z && b1.x < a1.x && b1.y < a1.y && b1.z < a1.z;
}

struct Wide {
	__int128 x = 0;
	__int128 y = 0;
	__int128 z = 0;
};

struct Plane {
	IVec3 origin;
	Wide n;
};

struct Frag {
	std::vector<IVec3> loop;
};

__int128 _dot(const Wide &p_a, const Wide &p_b) {
	return p_a.x * p_b.x + p_a.y * p_b.y + p_a.z * p_b.z;
}

Wide _cross(const IVec3 &p_a, const IVec3 &p_b) {
	Wide w;
	w.x = __int128(p_a.y) * p_b.z - __int128(p_a.z) * p_b.y;
	w.y = __int128(p_a.z) * p_b.x - __int128(p_a.x) * p_b.z;
	w.z = __int128(p_a.x) * p_b.y - __int128(p_a.y) * p_b.x;
	return w;
}

__int128 _side(const IVec3 &p_p, const Plane &p_pl) {
	const Wide d{
		__int128(p_p.x) - p_pl.origin.x,
		__int128(p_p.y) - p_pl.origin.y,
		__int128(p_p.z) - p_pl.origin.z,
	};
	return _dot(d, p_pl.n);
}

int _sign(__int128 p_v) {
	if (p_v > 0) {
		return 1;
	}
	if (p_v < 0) {
		return -1;
	}
	return 0;
}

void _clean(std::vector<IVec3> &p_loop) {
	if (p_loop.empty()) {
		return;
	}
	std::vector<IVec3> out;
	out.reserve(p_loop.size());
	for (const IVec3 &p : p_loop) {
		if (out.empty() || out.back() != p) {
			out.push_back(p);
		}
	}
	if (out.size() >= 2 && out.front() == out.back()) {
		out.pop_back();
	}
	p_loop.swap(out);
}

bool _face_plane(const Mesh &p_mesh, FaceId p_face, Plane &r_out) {
	std::vector<VertexId> corners;
	p_mesh.face_corners(p_face, corners);
	if (corners.size() < 3) {
		return false;
	}
	const IVec3 a = p_mesh.position_i(corners[0]);
	for (size_t i = 1; i + 1 < corners.size(); i++) {
		const IVec3 b = p_mesh.position_i(corners[i]);
		const IVec3 c = p_mesh.position_i(corners[i + 1]);
		const IVec3 ab{ b.x - a.x, b.y - a.y, b.z - a.z };
		const IVec3 ac{ c.x - a.x, c.y - a.y, c.z - a.z };
		const Wide n = _cross(ab, ac);
		if (n.x != 0 || n.y != 0 || n.z != 0) {
			r_out.origin = a;
			r_out.n = n;
			return true;
		}
	}
	return false;
}

IVec3 _hit(const IVec3 &p_a, const IVec3 &p_b, const Plane &p_pl) {
	const __int128 sa = _side(p_a, p_pl);
	const __int128 sb = _side(p_b, p_pl);
	__int128 den = sb - sa;
	if (den == 0) {
		return p_a;
	}
	auto lerp = [&](int32_t p_av, int32_t p_bv) -> int32_t {
		__int128 d = den;
		__int128 num = __int128(p_av) * d + __int128(int64_t(p_bv) - int64_t(p_av)) * (-sa);
		if (d < 0) {
			num = -num;
			d = -d;
		}
		if (num >= 0) {
			return int32_t((num + d / 2) / d);
		}
		return int32_t((num - d / 2) / d);
	};
	return IVec3{ lerp(p_a.x, p_b.x), lerp(p_a.y, p_b.y), lerp(p_a.z, p_b.z) };
}

bool _split_by_plane(const std::vector<IVec3> &p_poly, const Plane &p_pl, std::vector<IVec3> &r_pos, std::vector<IVec3> &r_neg) {
	r_pos.clear();
	r_neg.clear();
	const int n = int(p_poly.size());
	if (n < 3) {
		return false;
	}
	std::vector<int> s(n);
	bool any_pos = false;
	bool any_neg = false;
	for (int i = 0; i < n; i++) {
		s[i] = _sign(_side(p_poly[i], p_pl));
		any_pos = any_pos || s[i] > 0;
		any_neg = any_neg || s[i] < 0;
	}
	if (!any_pos || !any_neg) {
		return false;
	}
	for (int i = 0; i < n; i++) {
		const int j = (i + 1) % n;
		if (s[i] >= 0) {
			r_pos.push_back(p_poly[i]);
		}
		if (s[i] <= 0) {
			r_neg.push_back(p_poly[i]);
		}
		if (s[i] != 0 && s[j] != 0 && s[i] != s[j]) {
			const IVec3 h = _hit(p_poly[i], p_poly[j], p_pl);
			r_pos.push_back(h);
			r_neg.push_back(h);
		}
	}
	_clean(r_pos);
	_clean(r_neg);
	return true;
}

void _planes_of(const Mesh &p_mesh, std::vector<Plane> &r_out) {
	r_out.clear();
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	for (const FaceId id : faces) {
		Plane pl;
		if (_face_plane(p_mesh, id, pl)) {
			r_out.push_back(pl);
		}
	}
}

void _face_loops(const Mesh &p_mesh, std::vector<Frag> &r_out) {
	r_out.clear();
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	for (const FaceId id : faces) {
		std::vector<VertexId> corners;
		p_mesh.face_corners(id, corners);
		Frag f;
		f.loop.reserve(corners.size());
		for (const VertexId v : corners) {
			f.loop.push_back(p_mesh.position_i(v));
		}
		_clean(f.loop);
		if (f.loop.size() >= 3) {
			r_out.push_back(f);
		}
	}
}

godot::Vector3 _centroid(const std::vector<IVec3> &p_loop) {
	godot::Vector3 acc;
	for (const IVec3 &p : p_loop) {
		acc += dequantize(p);
	}
	if (p_loop.empty()) {
		return acc;
	}
	return acc / float(p_loop.size());
}

godot::Vector3 _normal(const std::vector<IVec3> &p_loop) {
	if (p_loop.size() < 3) {
		return godot::Vector3();
	}
	const godot::Vector3 a = dequantize(p_loop[0]);
	for (size_t i = 1; i + 1 < p_loop.size(); i++) {
		const godot::Vector3 n = (dequantize(p_loop[i]) - a).cross(dequantize(p_loop[i + 1]) - a);
		if (n.length_squared() > 0.0f) {
			return n.normalized();
		}
	}
	return godot::Vector3();
}

void _xy_axis(const godot::Vector3 &p_p, int p_axis, float &r_x, float &r_y) {
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

int _axis_of(const godot::Vector3 &p_n) {
	const float ax = godot::Math::abs(p_n.x);
	const float ay = godot::Math::abs(p_n.y);
	const float az = godot::Math::abs(p_n.z);
	if (ax >= ay && ax >= az) {
		return 0;
	}
	if (ay >= az) {
		return 1;
	}
	return 2;
}

bool _point_in_loop(const std::vector<IVec3> &p_loop, const godot::Vector3 &p_p, const godot::Vector3 &p_n) {
	const int n = int(p_loop.size());
	if (n < 3 || p_n.length_squared() == 0.0f) {
		return false;
	}
	const int axis = _axis_of(p_n);
	float px, py;
	_xy_axis(p_p, axis, px, py);
	bool inside = false;
	for (int i = 0, j = n - 1; i < n; j = i++) {
		float xi, yi, xj, yj;
		_xy_axis(dequantize(p_loop[i]), axis, xi, yi);
		_xy_axis(dequantize(p_loop[j]), axis, xj, yj);
		if ((yi > py) == (yj > py)) {
			continue;
		}
		const float den = yj - yi;
		if (den == 0.0f) {
			continue;
		}
		const float xhit = (xj - xi) * (py - yi) / den + xi;
		if (px < xhit) {
			inside = !inside;
		}
	}
	return inside;
}

bool _ray_hits_loop(const godot::Vector3 &p_o, const godot::Vector3 &p_d, const std::vector<IVec3> &p_loop) {
	const godot::Vector3 n = _normal(p_loop);
	if (n.length_squared() == 0.0f) {
		return false;
	}
	const float den = p_d.dot(n);
	if (godot::Math::abs(den) < 1e-12f) {
		return false;
	}
	const godot::Vector3 a = dequantize(p_loop[0]);
	const float t = (a - p_o).dot(n) / den;
	if (t <= 1e-5f) {
		return false;
	}
	return _point_in_loop(p_loop, p_o + p_d * t, n);
}

bool _inside_ray(const Mesh &p_mesh, const godot::Vector3 &p_p, const godot::Vector3 &p_d) {
	int hits = 0;
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	std::vector<VertexId> corners;
	for (const FaceId id : faces) {
		p_mesh.face_corners(id, corners);
		if (corners.size() < 3) {
			continue;
		}
		std::vector<IVec3> loop;
		loop.reserve(corners.size());
		for (const VertexId v : corners) {
			loop.push_back(p_mesh.position_i(v));
		}
		if (_ray_hits_loop(p_p, p_d, loop)) {
			hits++;
		}
	}
	return (hits % 2) == 1;
}

bool _point_inside(const Mesh &p_mesh, const godot::Vector3 &p_p) {
	const godot::AABB box = p_mesh.local_aabb().grow(2.0f / float(LATTICE));
	if (!box.has_point(p_p)) {
		return false;
	}
	const godot::Vector3 dirs[3] = {
		godot::Vector3(1.0f, 0.013f, 0.007f),
		godot::Vector3(0.011f, 1.0f, -0.017f),
		godot::Vector3(-0.019f, 0.009f, 1.0f),
	};
	int votes = 0;
	for (const godot::Vector3 &d : dirs) {
		if (_inside_ray(p_mesh, p_p, d)) {
			votes++;
		}
	}
	return votes >= 2;
}

void _shatter(const Frag &p_src, const std::vector<Plane> &p_planes, std::vector<Frag> &r_out) {
	std::vector<std::vector<IVec3>> pieces;
	pieces.push_back(p_src.loop);
	for (const Plane &pl : p_planes) {
		std::vector<std::vector<IVec3>> next;
		for (const std::vector<IVec3> &poly : pieces) {
			std::vector<IVec3> pos;
			std::vector<IVec3> neg;
			if (_split_by_plane(poly, pl, pos, neg)) {
				if (pos.size() >= 3) {
					next.push_back(pos);
				}
				if (neg.size() >= 3) {
					next.push_back(neg);
				}
			} else {
				next.push_back(poly);
			}
		}
		pieces.swap(next);
	}
	for (std::vector<IVec3> &poly : pieces) {
		_clean(poly);
		if (poly.size() >= 3) {
			Frag f;
			f.loop = std::move(poly);
			r_out.push_back(std::move(f));
		}
	}
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

__int128 _dist2(const IVec3 &p_a, const IVec3 &p_b) {
	const int64_t dx = int64_t(p_a.x) - p_b.x;
	const int64_t dy = int64_t(p_a.y) - p_b.y;
	const int64_t dz = int64_t(p_a.z) - p_b.z;
	return __int128(dx) * dx + __int128(dy) * dy + __int128(dz) * dz;
}

bool _on_open_segment(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_p) {
	if (p_p == p_a || p_p == p_b) {
		return false;
	}
	if (!_collinear(p_a, p_b, p_p)) {
		return false;
	}
	const __int128 ab = _dist2(p_a, p_b);
	return _dist2(p_a, p_p) < ab && _dist2(p_p, p_b) < ab;
}

void _snap_near(std::vector<std::vector<IVec3>> &p_loops) {
	std::vector<IVec3> pts;
	for (const std::vector<IVec3> &loop : p_loops) {
		for (const IVec3 &p : loop) {
			pts.push_back(p);
		}
	}
	for (size_t i = 0; i < pts.size(); i++) {
		for (size_t j = i + 1; j < pts.size(); j++) {
			const int64_t dx = int64_t(pts[i].x) - pts[j].x;
			const int64_t dy = int64_t(pts[i].y) - pts[j].y;
			const int64_t dz = int64_t(pts[i].z) - pts[j].z;
			if (dx * dx + dy * dy + dz * dz <= 4) {
				pts[j] = pts[i];
			}
		}
	}
	size_t k = 0;
	for (std::vector<IVec3> &loop : p_loops) {
		for (IVec3 &p : loop) {
			p = pts[k++];
		}
	}
}

void _imprint(std::vector<std::vector<IVec3>> &p_loops) {
	std::vector<IVec3> pts;
	for (const std::vector<IVec3> &loop : p_loops) {
		for (const IVec3 &p : loop) {
			pts.push_back(p);
		}
	}
	for (std::vector<IVec3> &loop : p_loops) {
		std::vector<IVec3> next;
		const int n = int(loop.size());
		for (int i = 0; i < n; i++) {
			const IVec3 a = loop[i];
			const IVec3 b = loop[(i + 1) % n];
			next.push_back(a);
			std::vector<IVec3> mids;
			for (const IVec3 &p : pts) {
				if (_on_open_segment(a, b, p)) {
					bool seen = false;
					for (const IVec3 &m : mids) {
						if (m == p) {
							seen = true;
							break;
						}
					}
					if (!seen) {
						mids.push_back(p);
					}
				}
			}
			std::sort(mids.begin(), mids.end(), [&](const IVec3 &p_l, const IVec3 &p_r) {
				return _dist2(a, p_l) < _dist2(a, p_r);
			});
			for (const IVec3 &m : mids) {
				next.push_back(m);
			}
		}
		loop.swap(next);
	}
}

void _split_at_repeats(const std::vector<IVec3> &p_loop, std::vector<std::vector<IVec3>> &r_out) {
	const int n = int(p_loop.size());
	for (int i = 0; i < n; i++) {
		for (int j = i + 2; j < n; j++) {
			if (i == 0 && j == n - 1) {
				continue;
			}
			if (p_loop[size_t(i)] != p_loop[size_t(j)]) {
				continue;
			}
			std::vector<IVec3> a;
			for (int k = i; k <= j; k++) {
				a.push_back(p_loop[size_t(k)]);
			}
			std::vector<IVec3> b;
			for (int k = j; k < n; k++) {
				b.push_back(p_loop[size_t(k)]);
			}
			for (int k = 0; k <= i; k++) {
				b.push_back(p_loop[size_t(k)]);
			}
			_clean(a);
			_clean(b);
			if (a.size() >= 3) {
				_split_at_repeats(a, r_out);
			}
			if (b.size() >= 3) {
				_split_at_repeats(b, r_out);
			}
			return;
		}
	}
	if (p_loop.size() >= 3) {
		r_out.push_back(p_loop);
	}
}

void _break_bowties(std::vector<std::vector<IVec3>> &p_loops) {
	std::vector<std::vector<IVec3>> next;
	for (std::vector<IVec3> loop : p_loops) {
		std::vector<std::vector<IVec3>> one;
		one.push_back(std::move(loop));
		_imprint(one);
		_split_at_repeats(one[0], next);
	}
	p_loops.swap(next);
}

void _reverse(std::vector<IVec3> &p_loop) {
	if (p_loop.size() < 3) {
		return;
	}
	std::reverse(p_loop.begin() + 1, p_loop.end());
}

bool _on_surface(const Mesh &p_mesh, const godot::Vector3 &p_p, godot::Vector3 &r_n) {
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	std::vector<VertexId> corners;
	for (const FaceId id : faces) {
		const godot::Vector3 n = p_mesh.face_normal(id);
		if (n.length_squared() == 0.0f) {
			continue;
		}
		p_mesh.face_corners(id, corners);
		if (corners.size() < 3) {
			continue;
		}
		const godot::Vector3 a = p_mesh.position(corners[0]);
		if (godot::Math::abs((p_p - a).dot(n)) > 2.0f / float(LATTICE)) {
			continue;
		}
		std::vector<IVec3> loop;
		loop.reserve(corners.size());
		for (const VertexId v : corners) {
			loop.push_back(p_mesh.position_i(v));
		}
		if (_point_in_loop(loop, p_p, n)) {
			r_n = n;
			return true;
		}
	}
	return false;
}

void _keep(const Mesh &p_other, const std::vector<Frag> &p_frags, bool p_inside, bool p_flip, bool p_skip_same_dir_coplanar, std::vector<std::vector<IVec3>> &r_out) {
	for (const Frag &f : p_frags) {
		const godot::Vector3 n = _normal(f.loop);
		if (n.length_squared() == 0.0f) {
			continue;
		}
		const godot::Vector3 c = _centroid(f.loop);
		godot::Vector3 other_n;
		if (_on_surface(p_other, c, other_n)) {
			if (p_inside && n.dot(other_n) >= 0.0f) {
				continue;
			}
			if (!p_inside && p_skip_same_dir_coplanar && n.dot(other_n) > 0.0f) {
				continue;
			}
		} else {
			const godot::Vector3 probe = c - n * (1.0f / float(LATTICE));
			if (_point_inside(p_other, probe) != p_inside) {
				continue;
			}
		}
		std::vector<IVec3> loop = f.loop;
		if (p_flip) {
			_reverse(loop);
		}
		r_out.push_back(std::move(loop));
	}
}

void _dissolve_coplanar(MeshEdit &p_edit) {
	for (;;) {
		std::vector<EdgeId> edges;
		p_edit.scratch().all_edges(edges);
		bool did = false;
		for (const EdgeId id : edges) {
			if (!p_edit.scratch().alive(id)) {
				continue;
			}
			FaceId fa;
			FaceId fb;
			p_edit.scratch().edge_faces(id, fa, fb);
			if (!p_edit.scratch().alive(fa) || !p_edit.scratch().alive(fb)) {
				continue;
			}
			if (p_edit.scratch().face_normal(fa).dot(p_edit.scratch().face_normal(fb)) <= 0.999f) {
				continue;
			}
			if (p_edit.dissolve_edge(id).ok()) {
				did = true;
			} else {
				p_edit.clear_fault();
			}
		}
		if (!did) {
			return;
		}
	}
}

MeshFault _clip(MeshEdit &p_edit, const Mesh &p_other, int p_mode) {
	std::vector<Plane> planes_a;
	std::vector<Plane> planes_b;
	_planes_of(p_edit.scratch(), planes_a);
	_planes_of(p_other, planes_b);

	std::vector<Frag> faces_a;
	std::vector<Frag> faces_b;
	_face_loops(p_edit.scratch(), faces_a);
	_face_loops(p_other, faces_b);

	std::vector<Frag> bits_a;
	std::vector<Frag> bits_b;
	for (const Frag &f : faces_a) {
		_shatter(f, planes_b, bits_a);
	}
	for (const Frag &f : faces_b) {
		_shatter(f, planes_a, bits_b);
	}

	std::vector<std::vector<IVec3>> loops;
	if (p_mode == 0) {
		_keep(p_other, bits_a, false, false, false, loops);
		_keep(p_edit.scratch(), bits_b, false, false, true, loops);
	} else if (p_mode == 1) {
		_keep(p_other, bits_a, false, false, true, loops);
		_keep(p_edit.scratch(), bits_b, true, true, true, loops);
	} else {
		_keep(p_other, bits_a, true, false, true, loops);
		_keep(p_edit.scratch(), bits_b, true, false, true, loops);
	}
	if (loops.empty()) {
		return _bad(MeshError::RESULT_EMPTY);
	}
	_snap_near(loops);
	_break_bowties(loops);
	_imprint(loops);
	const MeshFault assembled = p_edit.assemble(loops);
	if (!assembled.ok()) {
		return assembled;
	}
	// Collapsing collinear Steiner vertices after a Boolean warps planar
	// n-gons: a vertex can be locally collinear on every incident face and
	// still sit at the meeting of distinct edges. Sliding it along one edge
	// takes the others off-plane (workshop window SELF_INTERSECTION).
	_dissolve_coplanar(p_edit);
	return p_edit.last_fault();
}

} // namespace

MeshFault boolean(MeshEdit &p_edit, const Mesh &p_other, int p_mode) {
	if (p_other.face_count() < 1) {
		return _bad(MeshError::RESULT_EMPTY);
	}
	if (p_mode < 0 || p_mode > 2) {
		return _bad(MeshError::INVALID_SELECTION);
	}
	const godot::AABB a = p_edit.scratch().local_aabb();
	const godot::AABB b = p_other.local_aabb();
	if (p_mode == 0) {
		if (_aabb_disjoint(a, b)) {
			return p_edit.append(p_other, false);
		}
		if (_aabb_strictly_encloses(a, b) || _aabb_strictly_encloses(b, a)) {
			return _bad(MeshError::NO_INTERSECTION);
		}
		return _clip(p_edit, p_other, 0);
	}
	if (p_mode == 1) {
		if (_aabb_disjoint(a, b)) {
			return _bad(MeshError::NO_INTERSECTION);
		}
		if (_aabb_strictly_encloses(b, a)) {
			return _bad(MeshError::RESULT_EMPTY);
		}
		if (_aabb_strictly_encloses(a, b)) {
			return p_edit.append(p_other, true);
		}
		return _clip(p_edit, p_other, 1);
	}
	if (_aabb_disjoint(a, b)) {
		return _bad(MeshError::NO_INTERSECTION);
	}
	if (_aabb_strictly_encloses(a, b)) {
		return p_edit.replace_with(p_other);
	}
	if (_aabb_strictly_encloses(b, a)) {
		return p_edit.last_fault();
	}
	return _clip(p_edit, p_other, 2);
}

} // namespace ops
} // namespace slab
