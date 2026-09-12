#include "triangulate.hpp"

namespace slab {

namespace {

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

bool _on_closed_seg_2d(const IVec3 &p_p, const IVec3 &p_a, const IVec3 &p_b, int p_axis) {
	if (_o2(p_a, p_b, p_p, p_axis) != 0) {
		return false;
	}
	int32_t px, py, ax, ay, bx, by;
	_xy(p_p, p_axis, px, py);
	_xy(p_a, p_axis, ax, ay);
	_xy(p_b, p_axis, bx, by);
	const int32_t minx = ax < bx ? ax : bx;
	const int32_t maxx = ax < bx ? bx : ax;
	const int32_t miny = ay < by ? ay : by;
	const int32_t maxy = ay < by ? by : ay;
	return px >= minx && px <= maxx && py >= miny && py <= maxy;
}

bool _point_in_tri_closed_2d(const IVec3 &p_p, const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c, int p_axis) {
	const int tsign = _o2(p_a, p_b, p_c, p_axis);
	if (tsign == 0) {
		return false;
	}
	const int o1 = _o2(p_a, p_b, p_p, p_axis);
	const int o2 = _o2(p_b, p_c, p_p, p_axis);
	const int o3 = _o2(p_c, p_a, p_p, p_axis);
	return (o1 == 0 || o1 == tsign) && (o2 == 0 || o2 == tsign) && (o3 == 0 || o3 == tsign);
}

int _loop_axis(const std::vector<IVec3> &p_loop) {
	const size_t n = p_loop.size();
	for (size_t i = 0; i < n; i++) {
		for (size_t j = i + 1; j < n; j++) {
			for (size_t k = j + 1; k < n; k++) {
				if (!_zero_normal(p_loop[i], p_loop[j], p_loop[k])) {
					return _drop_axis(p_loop[i], p_loop[j], p_loop[k]);
				}
			}
		}
	}
	return 2;
}

int _loop_sign(const std::vector<IVec3> &p_loop, int p_axis) {
	__int128 s = 0;
	const size_t n = p_loop.size();
	for (size_t i = 0; i < n; i++) {
		int32_t x1, y1, x2, y2;
		_xy(p_loop[i], p_axis, x1, y1);
		_xy(p_loop[(i + 1) % n], p_axis, x2, y2);
		s += (__int128)x1 * y2 - (__int128)x2 * y1;
	}
	if (s > 0) {
		return 1;
	}
	if (s < 0) {
		return -1;
	}
	return 0;
}

void _push_tri(std::vector<int32_t> &r_indices, const std::vector<IVec3> &p_loop, int32_t p_a, int32_t p_b, int32_t p_c) {
	if (_zero_normal(p_loop[size_t(p_a)], p_loop[size_t(p_b)], p_loop[size_t(p_c)])) {
		return;
	}
	r_indices.push_back(p_a);
	r_indices.push_back(p_c);
	r_indices.push_back(p_b);
}

} // namespace

void triangulate_loop(const std::vector<IVec3> &p_loop, std::vector<int32_t> &r_indices) {
	r_indices.clear();
	const size_t n = p_loop.size();
	if (n < 3) {
		return;
	}
	const int axis = _loop_axis(p_loop);
	const int sign = _loop_sign(p_loop, axis);
	if (sign == 0) {
		return;
	}
	bool convex = true;
	for (size_t i = 0; i < n; i++) {
		const int o = _o2(p_loop[(i + n - 1) % n], p_loop[i], p_loop[(i + 1) % n], axis);
		if (o == -sign) {
			convex = false;
			break;
		}
	}
	if (convex) {
		for (int32_t i = 1; i + 1 < int32_t(n); i++) {
			_push_tri(r_indices, p_loop, 0, i, i + 1);
		}
		return;
	}
	std::vector<int32_t> idx(n);
	for (size_t i = 0; i < n; i++) {
		idx[i] = int32_t(i);
	}
	int guard = int(n) * int(n) + 8;
	while (idx.size() > 3 && guard-- > 0) {
		bool cut = false;
		const int m = int(idx.size());
		for (int i = 0; i < m; i++) {
			const int32_t ia = idx[(i + m - 1) % m];
			const int32_t ib = idx[size_t(i)];
			const int32_t ic = idx[(i + 1) % m];
			const IVec3 &a = p_loop[size_t(ia)];
			const IVec3 &b = p_loop[size_t(ib)];
			const IVec3 &c = p_loop[size_t(ic)];
			const int o = _o2(a, b, c, axis);
			if (o == 0) {
				if (_on_closed_seg_2d(b, a, c, axis)) {
					idx.erase(idx.begin() + i);
					cut = true;
					break;
				}
				continue;
			}
			if (o != sign) {
				continue;
			}
			bool packed = false;
			for (int k = 0; k < m; k++) {
				if (k == (i + m - 1) % m || k == i || k == (i + 1) % m) {
					continue;
				}
				if (_point_in_tri_closed_2d(p_loop[size_t(idx[size_t(k)])], a, b, c, axis)) {
					packed = true;
					break;
				}
			}
			if (packed) {
				continue;
			}
			_push_tri(r_indices, p_loop, ia, ib, ic);
			idx.erase(idx.begin() + i);
			cut = true;
			break;
		}
		if (!cut) {
			break;
		}
	}
	if (idx.size() == 3) {
		_push_tri(r_indices, p_loop, idx[0], idx[1], idx[2]);
	}
}

} // namespace slab
