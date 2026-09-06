#include "primitives.hpp"

#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

namespace slab {
namespace ops {

namespace {

static int _clamp_int(int p_v, int p_lo, int p_hi) {
	if (p_v < p_lo) {
		return p_lo;
	}
	if (p_v > p_hi) {
		return p_hi;
	}
	return p_v;
}

static double _clamp_double(double p_v, double p_lo, double p_hi) {
	if (p_v < p_lo) {
		return p_lo;
	}
	if (p_v > p_hi) {
		return p_hi;
	}
	return p_v;
}

static IVec3 _polar(int32_t p_radius, double p_angle) {
	return IVec3{
		int32_t(godot::Math::round(double(p_radius) * godot::Math::cos(p_angle))),
		int32_t(godot::Math::round(double(p_radius) * godot::Math::sin(p_angle))),
		0
	};
}

static MeshFault _move_cap(MeshEdit &p_edit, FaceId p_cap, const IVec3 &p_delta) {
	std::vector<VertexId> corners;
	p_edit.scratch().face_corners(p_cap, corners);
	for (const VertexId v : corners) {
		IVec3 p = p_edit.scratch().position_i(v);
		p.x += p_delta.x;
		p.y += p_delta.y;
		p.z += p_delta.z;
		p_edit.move_vertex(v, p);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	return p_edit.last_fault();
}

static MeshFault _extrude_lamina(MeshEdit &p_edit, const IVec3 *p_loop, int p_count, const IVec3 &p_delta) {
	const FaceId base = p_edit.make_lamina(p_loop, p_count);
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	const FaceId cap = p_edit.lift_loop(base);
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	return _move_cap(p_edit, cap, p_delta);
}

static int _sign64(int64_t p_v) {
	if (p_v > 0) {
		return 1;
	}
	if (p_v < 0) {
		return -1;
	}
	return 0;
}

static int _orient2d(int64_t p_ax, int64_t p_ay, int64_t p_bx, int64_t p_by, int64_t p_cx, int64_t p_cy) {
	const int64_t v = (p_bx - p_ax) * (p_cy - p_ay) - (p_by - p_ay) * (p_cx - p_ax);
	return _sign64(v);
}

static bool _segments_cross(const IVec3 &p_a0, const IVec3 &p_a1, const IVec3 &p_b0, const IVec3 &p_b1) {
	const int o1 = _orient2d(p_a0.x, p_a0.y, p_a1.x, p_a1.y, p_b0.x, p_b0.y);
	const int o2 = _orient2d(p_a0.x, p_a0.y, p_a1.x, p_a1.y, p_b1.x, p_b1.y);
	const int o3 = _orient2d(p_b0.x, p_b0.y, p_b1.x, p_b1.y, p_a0.x, p_a0.y);
	const int o4 = _orient2d(p_b0.x, p_b0.y, p_b1.x, p_b1.y, p_a1.x, p_a1.y);
	return o1 != o2 && o3 != o4;
}

static bool _loop_self_intersects(const IVec3 *p_loop, int p_count) {
	if (p_count < 4) {
		return false;
	}
	for (int i = 0; i < p_count; i++) {
		const IVec3 a0 = p_loop[i];
		const IVec3 a1 = p_loop[(i + 1) % p_count];
		for (int j = i + 2; j < p_count; j++) {
			if (j == p_count - 1 && i == 0) {
				continue;
			}
			const IVec3 b0 = p_loop[j];
			const IVec3 b1 = p_loop[(j + 1) % p_count];
			if (_segments_cross(a0, a1, b0, b1)) {
				return true;
			}
		}
	}
	return false;
}

static bool _loop_planar_y(const IVec3 *p_loop, int p_count, int32_t &r_y) {
	if (p_count < 1) {
		return false;
	}
	r_y = p_loop[0].y;
	for (int i = 1; i < p_count; i++) {
		if (p_loop[i].y != r_y) {
			return false;
		}
	}
	return true;
}

static bool _ring_frame(const IVec3 &p_t, IVec3 &r_u, IVec3 &r_v) {
	const int32_t ax = p_t.x < 0 ? -p_t.x : p_t.x;
	const int32_t ay = p_t.y < 0 ? -p_t.y : p_t.y;
	const int32_t az = p_t.z < 0 ? -p_t.z : p_t.z;
	if (ax == 0 && ay == 0 && az == 0) {
		return false;
	}
	if (ax >= ay && ax >= az) {
		r_u = IVec3{ 0, LATTICE, 0 };
		r_v = IVec3{ 0, 0, LATTICE };
	} else if (ay >= ax && ay >= az) {
		r_u = IVec3{ LATTICE, 0, 0 };
		r_v = IVec3{ 0, 0, LATTICE };
	} else {
		r_u = IVec3{ LATTICE, 0, 0 };
		r_v = IVec3{ 0, LATTICE, 0 };
	}
	return true;
}

static IVec3 _ring_point(const IVec3 &p_origin, const IVec3 &p_u, const IVec3 &p_v, const IVec3 &p_prof) {
	return IVec3{
		int32_t(int64_t(p_origin.x) + (int64_t(p_prof.x) * p_u.x + int64_t(p_prof.y) * p_v.x) / LATTICE),
		int32_t(int64_t(p_origin.y) + (int64_t(p_prof.x) * p_u.y + int64_t(p_prof.y) * p_v.y) / LATTICE),
		int32_t(int64_t(p_origin.z) + (int64_t(p_prof.x) * p_u.z + int64_t(p_prof.y) * p_v.z) / LATTICE)
	};
}

static bool _path_segments_cross(const IVec3 *p_path, int p_count) {
	if (p_count < 4) {
		return false;
	}
	for (int i = 0; i < p_count - 1; i++) {
		for (int j = i + 2; j < p_count - 1; j++) {
			if (i == 0 && j == p_count - 2) {
				continue;
			}
			if (_segments_cross(p_path[i], p_path[i + 1], p_path[j], p_path[j + 1])) {
				return true;
			}
		}
	}
	return false;
}

static MeshFault _bad(MeshError p_code) {
	MeshFault f;
	f.code = p_code;
	return f;
}

} // namespace

MeshFault box(MeshEdit &p_edit, const godot::Vector3 &p_size) {
	IVec3 sx;
	IVec3 sy;
	IVec3 sz;
	if (!quantize(godot::Vector3(p_size.x, 0, 0), sx) || !quantize(godot::Vector3(0, p_size.y, 0), sy) || !quantize(godot::Vector3(0, 0, p_size.z), sz)) {
		return _bad(MeshError::COORD_OUT_OF_RANGE);
	}
	if (sx.x == 0 || sy.y == 0 || sz.z == 0) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const IVec3 loop[4] = {
		IVec3{ 0, 0, 0 },
		IVec3{ 0, 0, sz.z },
		IVec3{ sx.x, 0, sz.z },
		IVec3{ sx.x, 0, 0 },
	};
	return _extrude_lamina(p_edit, loop, 4, IVec3{ 0, sy.y, 0 });
}

MeshFault plane(MeshEdit &p_edit, const godot::Vector2 &p_size, float p_thickness) {
	IVec3 sx;
	IVec3 sz;
	IVec3 st;
	if (!quantize(godot::Vector3(p_size.x, 0, 0), sx) || !quantize(godot::Vector3(0, 0, p_size.y), sz) || !quantize(godot::Vector3(0, p_thickness, 0), st)) {
		return _bad(MeshError::COORD_OUT_OF_RANGE);
	}
	if (sx.x == 0 || sz.z == 0 || st.y == 0) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const IVec3 loop[4] = {
		IVec3{ 0, 0, 0 },
		IVec3{ 0, 0, sz.z },
		IVec3{ sx.x, 0, sz.z },
		IVec3{ sx.x, 0, 0 },
	};
	return _extrude_lamina(p_edit, loop, 4, IVec3{ 0, st.y, 0 });
}

MeshFault stair(MeshEdit &p_edit, const godot::Vector3 &p_size, int p_steps) {
	IVec3 sx;
	IVec3 sy;
	IVec3 sz;
	if (!quantize(godot::Vector3(p_size.x, 0, 0), sx) || !quantize(godot::Vector3(0, p_size.y, 0), sy) || !quantize(godot::Vector3(0, 0, p_size.z), sz)) {
		return _bad(MeshError::COORD_OUT_OF_RANGE);
	}
	if (sx.x == 0 || sy.y == 0 || sz.z == 0) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const int steps = _clamp_int(p_steps, STAIR_STEPS_MIN, STAIR_STEPS_MAX);
	const int32_t step_w = sx.x / steps;
	const int32_t step_h = sy.y / steps;
	if (step_w == 0 || step_h == 0) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	std::vector<IVec3> loop;
	loop.push_back(IVec3{ 0, 0, 0 });
	for (int i = 0; i < steps; i++) {
		loop.push_back(IVec3{ loop.back().x, (i + 1) * step_h, 0 });
		loop.push_back(IVec3{ (i + 1) * step_w, (i + 1) * step_h, 0 });
	}
	loop.push_back(IVec3{ sx.x, 0, 0 });
	std::reverse(loop.begin(), loop.end());
	if (_loop_self_intersects(loop.data(), int(loop.size()))) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	return _extrude_lamina(p_edit, loop.data(), int(loop.size()), IVec3{ 0, 0, sz.z });
}

MeshFault cylinder(MeshEdit &p_edit, float p_radius, float p_height, int p_sides) {
	if (p_sides < CYLINDER_SIDES_MIN) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const int sides = _clamp_int(p_sides, CYLINDER_SIDES_MIN, CYLINDER_SIDES_MAX);
	IVec3 sr;
	IVec3 sh;
	if (!quantize(godot::Vector3(p_radius, 0, 0), sr) || !quantize(godot::Vector3(0, p_height, 0), sh)) {
		return _bad(MeshError::COORD_OUT_OF_RANGE);
	}
	if (sr.x == 0 || sh.y == 0) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	std::vector<IVec3> loop(sides);
	for (int i = 0; i < sides; i++) {
		const double angle = -Math_TAU * double(i) / double(sides);
		const int64_t x = int64_t(godot::Math::round(double(sr.x) * godot::Math::cos(angle)));
		const int64_t z = int64_t(godot::Math::round(double(sr.x) * godot::Math::sin(angle)));
		loop[i] = IVec3{ int32_t(x), 0, int32_t(z) };
	}
	return _extrude_lamina(p_edit, loop.data(), sides, IVec3{ 0, sh.y, 0 });
}

MeshFault arch(MeshEdit &p_edit, float p_span, float p_depth, int p_segments, float p_thickness, double p_arc) {
	const int segments = _clamp_int(p_segments, ARCH_SEGMENTS_MIN, ARCH_SEGMENTS_MAX);
	const double arc = _clamp_double(p_arc, ARCH_ARC_MIN, ARCH_ARC_MAX);
	IVec3 sx;
	IVec3 sz;
	IVec3 st;
	if (!quantize(godot::Vector3(p_span, 0, 0), sx) || !quantize(godot::Vector3(0, 0, p_depth), sz) || !quantize(godot::Vector3(p_thickness, 0, 0), st)) {
		return _bad(MeshError::COORD_OUT_OF_RANGE);
	}
	if (sx.x == 0 || sz.z == 0 || st.x == 0) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const int32_t outer_r = sx.x / 2;
	const int32_t inner_r = outer_r - st.x;
	if (outer_r == 0 || inner_r <= 0) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const double half = arc * 0.5;
	const double hi = Math_PI * 0.5 + half;
	const double lo = Math_PI * 0.5 - half;
	const auto angle_at = [&](int p_i) {
		return lo + (hi - lo) * double(segments - p_i) / double(segments);
	};
	std::vector<IVec3> loop;
	loop.reserve(size_t(segments + 1) * 2);
	for (int i = 0; i <= segments; i++) {
		loop.push_back(_polar(outer_r, angle_at(i)));
	}
	for (int k = 0; k <= segments; k++) {
		loop.push_back(_polar(inner_r, angle_at(segments - k)));
	}
	int32_t min_x = loop[0].x;
	int32_t min_y = loop[0].y;
	for (const IVec3 &p : loop) {
		min_x = std::min(min_x, p.x);
		min_y = std::min(min_y, p.y);
	}
	for (IVec3 &p : loop) {
		p.x -= min_x;
		p.y -= min_y;
	}
	if (_loop_self_intersects(loop.data(), int(loop.size()))) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	std::reverse(loop.begin(), loop.end());
	return _extrude_lamina(p_edit, loop.data(), int(loop.size()), IVec3{ 0, 0, sz.z });
}

MeshFault prism(MeshEdit &p_edit, const IVec3 *p_loop, int p_count, int32_t p_height) {
	if (p_loop == nullptr || p_count < 3) {
		return _bad(MeshError::LOOP_TOO_SHORT);
	}
	if (p_height == 0) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	int32_t y0 = 0;
	if (!_loop_planar_y(p_loop, p_count, y0)) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	if (_loop_self_intersects(p_loop, p_count)) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	return _extrude_lamina(p_edit, p_loop, p_count, IVec3{ 0, p_height, 0 });
}

MeshFault sweep(MeshEdit &p_edit, const IVec3 *p_path, int p_path_count, const IVec3 *p_profile, int p_profile_count, bool p_closed) {
	if (p_path == nullptr || p_path_count < 2) {
		return _bad(MeshError::LOOP_TOO_SHORT);
	}
	if (p_profile == nullptr || p_profile_count < 3) {
		return _bad(MeshError::LOOP_TOO_SHORT);
	}
	if (_loop_self_intersects(p_profile, p_profile_count)) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	if (_path_segments_cross(p_path, p_path_count)) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const int segments = p_closed ? p_path_count : p_path_count - 1;
	for (int i = 0; i < segments; i++) {
		const int src = i;
		const int dst = p_closed ? (i + 1) % p_path_count : i + 1;
		const IVec3 t{
			p_path[dst].x - p_path[src].x,
			p_path[dst].y - p_path[src].y,
			p_path[dst].z - p_path[src].z
		};
		IVec3 u;
		IVec3 v;
		if (!_ring_frame(t, u, v)) {
			return _bad(MeshError::DEGENERATE_FACE);
		}
	}
	IVec3 u0;
	IVec3 v0;
	{
		const int dst0 = p_closed ? 1 % p_path_count : 1;
		const IVec3 t0{
			p_path[dst0].x - p_path[0].x,
			p_path[dst0].y - p_path[0].y,
			p_path[dst0].z - p_path[0].z
		};
		if (!_ring_frame(t0, u0, v0)) {
			return _bad(MeshError::DEGENERATE_FACE);
		}
	}
	std::vector<IVec3> ring(p_profile_count);
	for (int i = 0; i < p_profile_count; i++) {
		ring[i] = _ring_point(p_path[0], u0, v0, p_profile[i]);
	}
	FaceId cap = p_edit.make_lamina(ring.data(), p_profile_count);
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	for (int s = 0; s < segments; s++) {
		const int src = s;
		const int dst = p_closed ? (s + 1) % p_path_count : s + 1;
		const IVec3 t{
			p_path[dst].x - p_path[src].x,
			p_path[dst].y - p_path[src].y,
			p_path[dst].z - p_path[src].z
		};
		IVec3 u;
		IVec3 v;
		if (!_ring_frame(t, u, v)) {
			return _bad(MeshError::DEGENERATE_FACE);
		}
		cap = p_edit.lift_loop(cap);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
		std::vector<VertexId> corners;
		p_edit.scratch().face_corners(cap, corners);
		if (int(corners.size()) != p_profile_count) {
			return _bad(MeshError::DEGENERATE_FACE);
		}
		for (int i = 0; i < p_profile_count; i++) {
			const IVec3 pos = _ring_point(p_path[dst], u, v, p_profile[i]);
			p_edit.move_vertex(corners[i], pos);
			if (!p_edit.last_fault().ok()) {
				return p_edit.last_fault();
			}
		}
	}
	return p_edit.last_fault();
}

} // namespace ops
} // namespace slab
