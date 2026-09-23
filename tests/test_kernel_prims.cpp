#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/serialize.hpp"
#include "kernel/ops/primitives.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;


static int euler(const Mesh &p_mesh) {
	return p_mesh.vertex_count() - p_mesh.edge_count() + p_mesh.face_count();
}

static std::vector<IVec3> sorted_positions(const Mesh &p_mesh) {
	std::vector<VertexId> verts;
	p_mesh.all_vertices(verts);
	std::vector<IVec3> out;
	out.reserve(verts.size());
	for (const VertexId v : verts) {
		out.push_back(p_mesh.position_i(v));
	}
	std::sort(out.begin(), out.end());
	return out;
}

static IVec3 min_corner(const Mesh &p_mesh) {
	const std::vector<IVec3> points = sorted_positions(p_mesh);
	IVec3 out = points[0];
	for (const IVec3 &p : points) {
		out.x = std::min(out.x, p.x);
		out.y = std::min(out.y, p.y);
		out.z = std::min(out.z, p.z);
	}
	return out;
}

static Mesh build_arch(float p_span, float p_depth, int p_segments, float p_thickness, double p_arc, const char *p_what) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::arch(edit, p_span, p_depth, p_segments, p_thickness, p_arc).ok(), p_what);
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), p_what);
	return mesh;
}

static std::vector<IVec3> legacy_arch_loop(float p_span, float p_depth, int p_segments, float p_thickness, int32_t &r_depth) {
	IVec3 sx;
	IVec3 sz;
	IVec3 st;
	quantize(godot::Vector3(p_span, 0, 0), sx);
	quantize(godot::Vector3(0, 0, p_depth), sz);
	quantize(godot::Vector3(p_thickness, 0, 0), st);
	const int32_t outer_r = sx.x / 2;
	const int32_t inner_r = outer_r - st.x;
	const int32_t cx = outer_r;
	std::vector<IVec3> loop;
	for (int i = 0; i <= p_segments; i++) {
		const double angle = Math_PI * double(p_segments - i) / double(p_segments);
		const int64_t x = int64_t(cx) + int64_t(godot::Math::round(double(outer_r) * godot::Math::cos(angle)));
		const int64_t y = int64_t(godot::Math::round(double(outer_r) * godot::Math::sin(angle)));
		loop.push_back(IVec3{ int32_t(x), int32_t(y), 0 });
	}
	loop.push_back(IVec3{ cx + inner_r, 0, 0 });
	for (int i = 1; i <= p_segments; i++) {
		const double angle = Math_PI * double(i) / double(p_segments);
		const int64_t x = int64_t(cx) + int64_t(godot::Math::round(double(inner_r) * godot::Math::cos(angle)));
		const int64_t y = int64_t(godot::Math::round(double(inner_r) * godot::Math::sin(angle)));
		loop.push_back(IVec3{ int32_t(x), int32_t(y), 0 });
	}
	r_depth = sz.z;
	return loop;
}

SLAB_TEST(plane_is_a_closed_slab) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::plane(edit, godot::Vector2(2, 3), 0.5f).ok(), "plane op");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "plane commit");
	expect_eq(mesh.face_count(), 6, "plane faces");
	expect_eq(euler(mesh), 2, "plane euler");
	expect_near(mesh.signed_volume(), 3.0, 0.01, "plane volume");
	expect(validate(mesh).ok(), "plane validate");
}

SLAB_TEST(plane_zero_thickness_rejected) {
	MeshEdit edit = MeshEdit::empty();
	const MeshFault fault = ops::plane(edit, godot::Vector2(2, 3), 0.0f);
	expect(!fault.ok(), "plane zero thickness");
	expect_eq(int(fault.code), int(MeshError::DEGENERATE_FACE), "plane zero thickness code");
}

SLAB_TEST(stair_is_one_solid_under_the_box) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::stair(edit, godot::Vector3(4, 2, 4), 4).ok(), "stair op");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "stair commit");
	expect(mesh.signed_volume() > 0.0, "stair volume positive");
	expect(mesh.signed_volume() < 32.0, "stair volume under bounding box");
	expect_eq(euler(mesh), 2, "stair euler");
	expect(mesh.face_count() > 6, "stair faces");
	expect(validate(mesh).ok(), "stair validate");
}

SLAB_TEST(cylinder_octagon_near_pi_volume) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::cylinder(edit, 1.0f, 2.0f, 8).ok(), "cylinder op");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "cylinder commit");
	expect_eq(euler(mesh), 2, "cylinder euler");
	const double want = 2.0 * Math_PI;
	expect_near(mesh.signed_volume(), want, want * 0.15, "cylinder volume");
	expect(validate(mesh).ok(), "cylinder validate");
}

SLAB_TEST(cylinder_two_sides_rejected) {
	MeshEdit edit = MeshEdit::empty();
	const MeshFault fault = ops::cylinder(edit, 1.0f, 2.0f, 2);
	expect(!fault.ok(), "cylinder two sides");
	expect_eq(int(fault.code), int(MeshError::DEGENERATE_FACE), "cylinder two sides code");
}

SLAB_TEST(prism_matches_box_lamina) {
	IVec3 sx;
	IVec3 sz;
	quantize(godot::Vector3(2, 0, 0), sx);
	quantize(godot::Vector3(0, 0, 2), sz);
	IVec3 sh;
	quantize(godot::Vector3(0, 3, 0), sh);
	const IVec3 loop[4] = {
		IVec3{ 0, 0, 0 },
		IVec3{ 0, 0, sz.z },
		IVec3{ sx.x, 0, sz.z },
		IVec3{ sx.x, 0, 0 },
	};
	MeshEdit edit = MeshEdit::empty();
	expect(ops::prism(edit, loop, 4, sh.y).ok(), "prism op");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "prism commit");
	expect_eq(mesh.face_count(), 6, "prism faces");
	expect_eq(euler(mesh), 2, "prism euler");
	expect_near(mesh.signed_volume(), 12.0, 0.01, "prism volume");
	expect(validate(mesh).ok(), "prism validate");
}

SLAB_TEST(sweep_square_along_x) {
	IVec3 path[2] = {
		IVec3{ 0, 0, 0 },
		IVec3{ 0, 0, 0 },
	};
	quantize(godot::Vector3(4, 0, 0), path[1]);
	const IVec3 profile[4] = {
		IVec3{ 0, 0, 0 },
		IVec3{ LATTICE, 0, 0 },
		IVec3{ LATTICE, LATTICE, 0 },
		IVec3{ 0, LATTICE, 0 },
	};
	MeshEdit edit = MeshEdit::empty();
	expect(ops::sweep(edit, path, 2, profile, 4, false).ok(), "sweep op");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "sweep commit");
	expect_eq(euler(mesh), 2, "sweep euler");
	expect_near(mesh.signed_volume(), 4.0, 0.01, "sweep volume");
	expect(validate(mesh).ok(), "sweep validate");
}

SLAB_TEST(arch_is_a_thickened_half_tube) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::arch(edit, 4.0f, 1.0f, 8, 0.5f, Math_PI).ok(), "arch op");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "arch commit");
	expect(mesh.signed_volume() > 0.0, "arch volume positive");
	expect(mesh.signed_volume() < 8.0, "arch volume under bounding box");
	expect_eq(euler(mesh), 2, "arch euler");
	expect(mesh.face_count() > 6, "arch has more faces than a box");
	expect(validate(mesh).ok(), "arch validate");
}

SLAB_TEST(arch_half_circle_is_the_legacy_mesh) {
	struct Case {
		float span;
		float depth;
		float thickness;
	};
	const Case cases[3] = {
		{ 4.0f, 1.0f, 0.5f },
		{ 2.0f, 2.0f, 0.25f },
		{ 8.0f, 1.0f, 1.0f },
	};
	const int segment_counts[4] = { 4, 8, 16, 32 };
	for (const Case &c : cases) {
		for (const int segments : segment_counts) {
			char what[96];
			std::snprintf(what, sizeof(what), "legacy arch span %g depth %g thickness %g segments %d", double(c.span), double(c.depth), double(c.thickness), segments);
			int32_t depth = 0;
			std::vector<IVec3> want = legacy_arch_loop(c.span, c.depth, segments, c.thickness, depth);
			const size_t profile = want.size();
			for (size_t i = 0; i < profile; i++) {
				want.push_back(IVec3{ want[i].x, want[i].y, depth });
			}
			std::sort(want.begin(), want.end());
			const Mesh mesh = build_arch(c.span, c.depth, segments, c.thickness, Math_PI, what);
			const std::vector<IVec3> got = sorted_positions(mesh);
			expect_eq(int(got.size()), int(want.size()), what);
			int mismatches = 0;
			const size_t shared = std::min(got.size(), want.size());
			for (size_t i = 0; i < shared; i++) {
				if (got[i] != want[i]) {
					mismatches++;
				}
			}
			mismatches += int(std::max(got.size(), want.size()) - shared);
			expect_eq(mismatches, 0, what);
		}
	}
}

SLAB_TEST(arch_at_180_degrees_is_the_old_half_tube) {
	const Mesh mesh = build_arch(4.0f, 1.0f, 8, 0.5f, Math_PI, "arch 180");
	expect_eq(mesh.vertex_count(), 36, "arch 180 verts");
	expect_eq(mesh.face_count(), 20, "arch 180 faces");
	expect_eq(euler(mesh), 2, "arch 180 euler");
	expect(validate(mesh).ok(), "arch 180 validate");
	expect_near(mesh.signed_volume(), 2.678646, 1e-5, "arch 180 volume");
	const double unit = 1.0 / double(LATTICE);
	const godot::AABB aabb = mesh.local_aabb();
	expect_near(double(aabb.position.x), 0.0, unit, "arch 180 aabb x");
	expect_near(double(aabb.position.y), 0.0, unit, "arch 180 aabb y");
	expect_near(double(aabb.position.z), 0.0, unit, "arch 180 aabb z");
	expect_near(double(aabb.size.x), 4.0, unit, "arch 180 aabb width");
	expect_near(double(aabb.size.y), 2.0, unit, "arch 180 aabb height");
	expect_near(double(aabb.size.z), 1.0, unit, "arch 180 aabb depth");
}

SLAB_TEST(arch_under_180_is_a_segmental_band_on_the_floor) {
	const Mesh half = build_arch(4.0f, 1.0f, 8, 0.5f, Math_PI, "arch 180");
	const Mesh mesh = build_arch(4.0f, 1.0f, 8, 0.5f, Math_PI * 0.5, "arch 90");
	expect_eq(mesh.vertex_count(), 36, "arch 90 verts");
	expect_eq(euler(mesh), 2, "arch 90 euler");
	expect(validate(mesh).ok(), "arch 90 validate");
	const IVec3 corner = min_corner(mesh);
	expect_eq(corner.x, 0, "arch 90 sits at x 0");
	expect_eq(corner.y, 0, "arch 90 feet on the floor");
	expect_eq(corner.z, 0, "arch 90 sits at z 0");
	expect(mesh.signed_volume() > 0.0, "arch 90 volume positive");
	expect(mesh.signed_volume() < half.signed_volume(), "arch 90 encloses less than the half circle");
	expect_near(mesh.signed_volume(), 1.366517, 1e-5, "arch 90 volume");
	const double unit = 1.0 / double(LATTICE);
	const godot::AABB aabb = mesh.local_aabb();
	expect_near(double(aabb.size.x), 2.828125, unit, "arch 90 aabb width");
	expect_near(double(aabb.size.y), 0.939453, unit, "arch 90 aabb height");
	expect_near(double(aabb.size.z), 1.0, unit, "arch 90 aabb depth");
	const std::vector<IVec3> points = sorted_positions(mesh);
	IVec3 crown = points[0];
	int32_t max_x = points[0].x;
	for (const IVec3 &p : points) {
		if (p.y > crown.y) {
			crown = p;
		}
		max_x = std::max(max_x, p.x);
	}
	expect(std::abs(2 * crown.x - max_x) <= 1, "arch 90 crown sits on the mid line");
}

SLAB_TEST(arch_over_180_is_a_horseshoe_and_still_one_solid) {
	const Mesh half = build_arch(4.0f, 1.0f, 8, 0.5f, Math_PI, "arch 180");
	const Mesh mesh = build_arch(4.0f, 1.0f, 8, 0.5f, Math_PI * 1.5, "arch 270");
	expect_eq(mesh.vertex_count(), 36, "arch 270 verts");
	expect_eq(euler(mesh), 2, "arch 270 euler");
	expect(validate(mesh).ok(), "arch 270 validate");
	const IVec3 corner = min_corner(mesh);
	expect_eq(corner.x, 0, "arch 270 sits at x 0");
	expect_eq(corner.y, 0, "arch 270 feet on the floor");
	expect_eq(corner.z, 0, "arch 270 sits at z 0");
	expect(mesh.signed_volume() > half.signed_volume(), "arch 270 encloses more than the half circle");
	expect_near(mesh.signed_volume(), 3.891511, 1e-5, "arch 270 volume");
	const double unit = 1.0 / double(LATTICE);
	const godot::AABB aabb = mesh.local_aabb();
	expect(double(aabb.size.x) <= 4.0, "arch 270 stays inside the span");
	expect(double(aabb.size.y) > 2.0, "arch 270 hangs below the springing line");
	expect_near(double(aabb.size.x), 3.923828, unit, "arch 270 aabb width");
	expect_near(double(aabb.size.y), 3.414062, unit, "arch 270 aabb height");
	expect_near(double(aabb.size.z), 1.0, unit, "arch 270 aabb depth");
}

SLAB_TEST(arch_at_360_degrees_is_a_closed_annular_solid) {
	const Mesh mesh = build_arch(4.0f, 1.0f, 8, 0.5f, Math_TAU, "arch 360");
	expect_eq(mesh.vertex_count(), 32, "arch 360 verts");
	expect_eq(mesh.face_count(), 32, "arch 360 faces");
	expect_eq(euler(mesh), 0, "arch 360 euler");
	expect(mesh.signed_volume() > 0.0, "arch 360 volume positive");
	expect_near(mesh.signed_volume(), 4.949219, 1e-5, "arch 360 volume");
	expect(validate(mesh).ok(), "arch 360 validate");
	const double unit = 1.0 / double(LATTICE);
	const godot::AABB aabb = mesh.local_aabb();
	expect_near(double(aabb.position.x), 0.0, unit, "arch 360 aabb x");
	expect_near(double(aabb.position.y), 0.0, unit, "arch 360 aabb y");
	expect_near(double(aabb.position.z), 0.0, unit, "arch 360 aabb z");
	expect_near(double(aabb.size.x), 4.0, unit, "arch 360 aabb width");
	expect_near(double(aabb.size.y), 4.0, unit, "arch 360 aabb height");
	expect_near(double(aabb.size.z), 1.0, unit, "arch 360 aabb depth");
}

SLAB_TEST(arch_arc_clamps_to_the_representable_band) {
	const Mesh low = build_arch(4.0f, 1.0f, 8, 0.5f, 0.0, "arch arc 0");
	const Mesh narrowest = build_arch(4.0f, 1.0f, 8, 0.5f, ops::ARCH_ARC_MIN, "arch arc min");
	expect_eq(low.vertex_count(), narrowest.vertex_count(), "arc 0 clamps up to the narrowest arch");
	expect_near(low.signed_volume(), narrowest.signed_volume(), 1e-9, "arc 0 volume matches the narrowest arch");
	const Mesh high = build_arch(4.0f, 1.0f, 8, 0.5f, 12.0, "arch arc 12");
	const Mesh widest = build_arch(4.0f, 1.0f, 8, 0.5f, ops::ARCH_ARC_MAX, "arch arc max");
	expect_eq(high.vertex_count(), widest.vertex_count(), "arc 12 clamps down to the widest arch");
	expect_near(high.signed_volume(), widest.signed_volume(), 1e-9, "arc 12 volume matches the widest arch");
	expect(validate(narrowest).ok(), "narrowest arch validate");
	expect(validate(widest).ok(), "widest arch validate");
}

SLAB_TEST(arch_thickness_at_half_the_span_is_refused) {
	MeshEdit edit = MeshEdit::empty();
	const MeshFault fault = ops::arch(edit, 4.0f, 1.0f, 8, 2.0f, Math_PI);
	expect(!fault.ok(), "arch thickness at half the span");
	expect_eq(int(fault.code), int(MeshError::DEGENERATE_FACE), "arch thickness at half the span code");
}

SLAB_TEST(primitive_counts_clamp_to_the_published_bounds) {
	MeshEdit stair_high = MeshEdit::empty();
	MeshEdit stair_max = MeshEdit::empty();
	MeshEdit stair_low = MeshEdit::empty();
	MeshEdit stair_min = MeshEdit::empty();
	expect(ops::stair(stair_high, godot::Vector3(4, 2, 4), 99).ok(), "stair 99 op");
	expect(ops::stair(stair_max, godot::Vector3(4, 2, 4), ops::STAIR_STEPS_MAX).ok(), "stair max op");
	expect(ops::stair(stair_low, godot::Vector3(4, 2, 4), 0).ok(), "stair 0 op");
	expect(ops::stair(stair_min, godot::Vector3(4, 2, 4), ops::STAIR_STEPS_MIN).ok(), "stair min op");
	expect_eq(stair_high.scratch().face_count(), stair_max.scratch().face_count(), "stair 99 clamps to the max");
	expect_eq(stair_low.scratch().face_count(), stair_min.scratch().face_count(), "stair 0 clamps to the min");
	expect(stair_max.scratch().face_count() > stair_min.scratch().face_count(), "stair bounds are distinct");

	MeshEdit cylinder_high = MeshEdit::empty();
	MeshEdit cylinder_max = MeshEdit::empty();
	expect(ops::cylinder(cylinder_high, 1.0f, 2.0f, 99).ok(), "cylinder 99 op");
	expect(ops::cylinder(cylinder_max, 1.0f, 2.0f, ops::CYLINDER_SIDES_MAX).ok(), "cylinder max op");
	expect_eq(cylinder_high.scratch().face_count(), cylinder_max.scratch().face_count(), "cylinder 99 clamps to the max");
	expect_eq(cylinder_max.scratch().face_count(), ops::CYLINDER_SIDES_MAX + 2, "cylinder max faces");

	MeshEdit arch_high = MeshEdit::empty();
	MeshEdit arch_max = MeshEdit::empty();
	MeshEdit arch_low = MeshEdit::empty();
	MeshEdit arch_min = MeshEdit::empty();
	expect(ops::arch(arch_high, 4.0f, 1.0f, 99, 0.5f, Math_PI).ok(), "arch 99 op");
	expect(ops::arch(arch_max, 4.0f, 1.0f, ops::ARCH_SEGMENTS_MAX, 0.5f, Math_PI).ok(), "arch max op");
	expect(ops::arch(arch_low, 4.0f, 1.0f, 1, 0.5f, Math_PI).ok(), "arch 1 op");
	expect(ops::arch(arch_min, 4.0f, 1.0f, ops::ARCH_SEGMENTS_MIN, 0.5f, Math_PI).ok(), "arch min op");
	expect_eq(arch_high.scratch().face_count(), arch_max.scratch().face_count(), "arch 99 clamps to the max");
	expect_eq(arch_low.scratch().face_count(), arch_min.scratch().face_count(), "arch 1 clamps to the min");
	expect_eq(arch_max.scratch().face_count(), 2 * (ops::ARCH_SEGMENTS_MAX + 1) + 2, "arch max faces");
}

static const IVec3 sweep_profile[] = {
	{ -LATTICE / 4, -LATTICE / 4, 0 }, { LATTICE / 4, -LATTICE / 4, 0 },
	{ LATTICE / 4, LATTICE / 4, 0 }, { -LATTICE / 4, LATTICE / 4, 0 },
};

SLAB_TEST(closed_sweep_shares_seam_and_has_no_caps) {
	const IVec3 path[] = { { 0, 0, 0 }, { 4 * LATTICE, 0, 0 }, { 4 * LATTICE, 0, 4 * LATTICE }, { 0, 0, 4 * LATTICE } };
	MeshEdit edit = MeshEdit::empty();
	expect(ops::sweep(edit, path, 4, sweep_profile, 4, true).ok(), "closed sweep assembles");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "closed sweep commits under ordinary validator");
	expect(validate(mesh).ok(), "closed sweep validates");
	expect_eq(mesh.vertex_count(), 16, "four shared rings, no duplicate seam vertices");
	expect_eq(mesh.face_count(), 32, "only triangulated cyclic walls, no end caps");
	expect_eq(euler(mesh), 0, "closed tube has torus topology");
	expect(mesh.signed_volume() > 0, "closed sweep has outward winding");
	Mesh loaded;
	expect(deserialize(serialize(mesh), loaded).ok(), "closed sweep remains editable after reload");
	expect_eq(euler(loaded), 0, "reload preserves torus topology");
}

SLAB_TEST(closed_sweep_transports_frames_on_nonplanar_loop) {
	std::vector<IVec3> path;
	for (int i = 0; i < 12; ++i) {
		const double angle = double(i) * Math_TAU / 12;
		IVec3 p;
		quantize(godot::Vector3(4 * std::cos(angle), 0.7 * std::sin(angle * 2) + 0.2 * std::cos(angle * 3), 4 * std::sin(angle)), p);
		path.push_back(p);
	}
	for (int direction = 0; direction < 2; ++direction) {
		MeshEdit edit = MeshEdit::empty();
		expect(ops::sweep(edit, path.data(), int(path.size()), sweep_profile, 4, true).ok(), "nonplanar sweep assembles");
		Mesh mesh;
		expect(std::move(edit).commit(mesh).ok(), "nonplanar sweep commits");
		expect(validate(mesh).ok(), "transported frames do not twist faces into intersections");
		expect_eq(mesh.vertex_count(), 48, "one shared ring per nonplanar path point");
		expect_eq(euler(mesh), 0, "nonplanar tube is manifold torus");
		expect(mesh.signed_volume() > 1.0, "reversed path still winds outward");
		std::reverse(path.begin(), path.end());
	}
}

SLAB_TEST(sweep_handles_vertical_paths_and_repeated_closure_endpoint) {
	const IVec3 vertical[] = { { 0, 0, 0 }, { 0, 4 * LATTICE, 0 }, { 3 * LATTICE, 6 * LATTICE, LATTICE } };
	MeshEdit open = MeshEdit::empty();
	expect(ops::sweep(open, vertical, 3, sweep_profile, 4, false).ok(), "vertical open sweep assembles");
	Mesh mesh;
	expect(std::move(open).commit(mesh).ok(), "vertical open sweep caps remain planar triangles");
	expect_eq(euler(mesh), 2, "open sweep is capped sphere topology");
	const IVec3 closed[] = { { 0, 0, 0 }, { 4 * LATTICE, 0, 0 }, { 4 * LATTICE, 0, 4 * LATTICE }, { 0, 0, 4 * LATTICE }, { 0, 0, 0 } };
	MeshEdit edit = MeshEdit::empty();
	expect(ops::sweep(edit, closed, 5, sweep_profile, 4, true).ok(), "repeated endpoint is accepted once");
	expect(std::move(edit).commit(mesh).ok(), "repeated endpoint closes manifold");
	expect_eq(mesh.vertex_count(), 16, "endpoint normalization creates no extra ring");
}

SLAB_TEST(sweep_rejects_invalid_loops_without_replacing_live_mesh) {
	const std::vector<std::vector<IVec3>> invalid = {
		{ {0,0,0}, {LATTICE,0,0} },
		{ {0,0,0}, {LATTICE,0,0}, {LATTICE,0,0}, {0,0,LATTICE} },
		{ {0,0,0}, {LATTICE,0,0}, {-LATTICE,0,0} },
		// A ring wider than this path folds through its neighbours.
		{ {0,0,0}, {LATTICE/8,0,0}, {LATTICE/8,0,LATTICE/8}, {0,0,LATTICE/8} },
		// The closing segment crosses the middle segment, in XZ rather than XY.
		{ {-2*LATTICE,0,-2*LATTICE}, {2*LATTICE,0,-2*LATTICE}, {-2*LATTICE,0,2*LATTICE}, {2*LATTICE,0,2*LATTICE} },
	};
	Mesh mesh;
	MeshEdit seed = MeshEdit::empty();
	expect(ops::box(seed, godot::Vector3(1,1,1)).ok(), "seed valid mesh");
	expect(std::move(seed).commit(mesh).ok(), "seed committed");
	const auto before = serialize(mesh);
	for (const auto &path : invalid) {
		MeshEdit edit = MeshEdit::empty();
		MeshFault fault = ops::sweep(edit, path.data(), int(path.size()), sweep_profile, 4, true);
		if (fault.ok()) fault = std::move(edit).commit(mesh);
		expect(!fault.ok(), "invalid closed path refused");
		expect(serialize(mesh) == before, "failed sweep leaves committed mesh unchanged");
	}
}
