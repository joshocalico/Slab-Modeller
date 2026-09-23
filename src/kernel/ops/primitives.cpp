#include "primitives.hpp"
#include "../triangulate.hpp"

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

// Minimal rotation between consecutive tangents preserves the profile frame.
// The antiparallel case has no unique frame and is rejected by the caller.
static godot::Vector3 _transport(const godot::Vector3 &p_u, const godot::Vector3 &p_from, const godot::Vector3 &p_to) {
	const godot::Vector3 axis = p_from.cross(p_to);
	const double sine = axis.length();
	godot::Vector3 u = p_u;
	if (sine > 1e-7) {
		u = u.rotated(axis / sine, std::atan2(sine, double(p_from.dot(p_to))));
	}
	return (u - p_to * u.dot(p_to)).normalized();
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
	if (arc == Math_TAU) {
		std::vector<IVec3> outer(segments);
		std::vector<IVec3> inner(segments);
		for (int i = 0; i < segments; i++) {
			const double angle = Math_PI * 0.5 - Math_TAU * double(i) / double(segments);
			outer[i] = _polar(outer_r, angle);
			inner[i] = _polar(inner_r, angle);
		}
		int32_t min_x = outer[0].x;
		int32_t min_y = outer[0].y;
		for (const IVec3 &p : outer) {
			min_x = std::min(min_x, p.x);
			min_y = std::min(min_y, p.y);
		}
		for (int i = 0; i < segments; i++) {
			outer[i].x -= min_x;
			outer[i].y -= min_y;
			inner[i].x -= min_x;
			inner[i].y -= min_y;
		}

		const IVec3 depth{ 0, 0, sz.z };
		const auto behind = [&](const IVec3 &p_point) {
			return IVec3{ p_point.x, p_point.y, depth.z };
		};
		std::vector<std::vector<IVec3>> faces;
		faces.reserve(size_t(segments) * 4);
		for (int i = 0; i < segments; i++) {
			const int next = (i + 1) % segments;
			const IVec3 outer_back = behind(outer[i]);
			const IVec3 outer_next_back = behind(outer[next]);
			const IVec3 inner_back = behind(inner[i]);
			const IVec3 inner_next_back = behind(inner[next]);
			faces.push_back({ outer[i], outer[next], inner[next], inner[i] });
			faces.push_back({ outer_back, inner_back, inner_next_back, outer_next_back });
			faces.push_back({ outer[i], outer_back, outer_next_back, outer[next] });
			faces.push_back({ inner[i], inner[next], inner_next_back, inner_back });
		}
		return p_edit.assemble(faces);
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
	if (p_path == nullptr || p_profile == nullptr || p_profile_count < 3) {
		return _bad(MeshError::LOOP_TOO_SHORT);
	}
	// Accept the common closed-polyline representation with a repeated endpoint.
	if (p_closed && p_path_count > 1 && p_path[0] == p_path[p_path_count - 1]) --p_path_count;
	if (p_path_count < (p_closed ? 3 : 2)) return _bad(MeshError::LOOP_TOO_SHORT);
	if (_loop_self_intersects(p_profile, p_profile_count)) return _bad(MeshError::DEGENERATE_FACE);
	__int128 profile_area = 0;
	for (int j = 0; j < p_profile_count; ++j) {
		const IVec3 &a = p_profile[j], &b = p_profile[(j + 1) % p_profile_count];
		if (a.z != 0 || a == b) return _bad(MeshError::DEGENERATE_FACE);
		profile_area += __int128(a.x) * b.y - __int128(a.y) * b.x;
	}
	if (profile_area == 0) return _bad(MeshError::DEGENERATE_FACE);
	std::vector<godot::Vector3> points, directions, tangents, frames;
	std::vector<double> distances(p_path_count, 0.0);
	for (int i = 0; i < p_path_count; ++i) {
		for (int j = 0; j < i; ++j) {
			if (p_path[i] == p_path[j]) return _bad(MeshError::DEGENERATE_FACE);
		}
		points.push_back(dequantize(p_path[i]));
	}
	const int segments = p_closed ? p_path_count : p_path_count - 1;
	double total_length = 0.0;
	for (int i = 0; i < segments; ++i) {
		const godot::Vector3 delta = points[(i + 1) % p_path_count] - points[i];
		directions.push_back(delta.normalized());
		total_length += delta.length();
		if (i + 1 < p_path_count) distances[i + 1] = total_length;
	}
	for (int i = 0; i < p_path_count; ++i) {
		godot::Vector3 tangent;
		if (!p_closed && i == 0) tangent = directions.front();
		else if (!p_closed && i == p_path_count - 1) tangent = directions.back();
		else tangent = directions[(i + segments - 1) % segments] + directions[i % segments];
		if (tangent.length_squared() < 1e-10) return _bad(MeshError::DEGENERATE_FACE);
		tangents.push_back(tangent.normalized());
	}
	const godot::Vector3 reference = std::abs(tangents[0].y) < 0.9 ? godot::Vector3(0, 1, 0) : godot::Vector3(1, 0, 0);
	frames.push_back(reference.cross(tangents[0]).normalized());
	for (int i = 1; i < p_path_count; ++i) {
		if (tangents[i - 1].dot(tangents[i]) < -0.999999) return _bad(MeshError::DEGENERATE_FACE);
		frames.push_back(_transport(frames.back(), tangents[i - 1], tangents[i]));
	}
	if (p_closed) {
		if (tangents.back().dot(tangents.front()) < -0.999999) return _bad(MeshError::DEGENERATE_FACE);
		const godot::Vector3 returned = _transport(frames.back(), tangents.back(), tangents.front());
		const double correction = std::atan2(double(tangents[0].dot(returned.cross(frames[0]))), double(returned.dot(frames[0])));
		// Spread holonomy over the entire loop, including the closing segment.
		for (int i = 1; i < p_path_count; ++i) frames[i] = frames[i].rotated(tangents[i], correction * distances[i] / total_length);
	}
	std::vector<std::vector<IVec3>> rings(p_path_count);
	for (int i = 0; i < p_path_count; ++i) {
		const godot::Vector3 v = tangents[i].cross(frames[i]);
		for (int j = 0; j < p_profile_count; ++j) {
			const IVec3 &profile = p_profile[profile_area > 0 ? j : p_profile_count - 1 - j];
			const godot::Vector3 position = points[i] + frames[i] * (double(profile.x) / LATTICE) + v * (double(profile.y) / LATTICE);
			IVec3 quantized;
			if (!quantize(position, quantized)) return _bad(MeshError::COORD_OUT_OF_RANGE);
			rings[i].push_back(quantized);
		}
	}
	std::vector<std::vector<IVec3>> loops;
	for (int i = 0; i < segments; ++i) {
		const int next = (i + 1) % p_path_count;
		for (int j = 0; j < p_profile_count; ++j) {
			const int k = (j + 1) % p_profile_count;
			// Triangles remain planar after frame transport and lattice quantization.
			loops.push_back({ rings[i][j], rings[i][k], rings[next][k] });
			loops.push_back({ rings[i][j], rings[next][k], rings[next][j] });
		}
	}
	if (!p_closed) {
		std::vector<IVec3> profile_loop;
		for (int j = 0; j < p_profile_count; ++j) profile_loop.push_back(p_profile[profile_area > 0 ? j : p_profile_count - 1 - j]);
		std::vector<int32_t> caps;
		triangulate_loop(profile_loop, caps);
		for (size_t i = 0; i + 2 < caps.size(); i += 3) {
			loops.push_back({ rings.front()[caps[i]], rings.front()[caps[i + 1]], rings.front()[caps[i + 2]] });
			loops.push_back({ rings.back()[caps[i]], rings.back()[caps[i + 2]], rings.back()[caps[i + 1]] });
		}
	}
	// Assemble shares the closing ring's vertices and half-edges. The ordinary
	// commit validator remains responsible for self-intersections and volume.
	const MeshFault assembled = p_edit.assemble(loops);
	if (!assembled.ok()) return assembled;
	// General assembly can repair collapsed boundaries. A sweep must retain
	// every authored ring/corner and triangle, or refuse the geometry.
	if (p_edit.scratch().vertex_count() != p_path_count * p_profile_count ||
			p_edit.scratch().face_count() != int(loops.size())) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	return assembled;
}

} // namespace ops
} // namespace slab
