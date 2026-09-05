#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/primitives.hpp"

#include <cmath>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;


static int euler(const Mesh &p_mesh) {
	return p_mesh.vertex_count() - p_mesh.edge_count() + p_mesh.face_count();
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
	expect(ops::arch(edit, godot::Vector3(4, 2, 1), 8, 0.5f).ok(), "arch op");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "arch commit");
	expect(mesh.signed_volume() > 0.0, "arch volume positive");
	expect(mesh.signed_volume() < 8.0, "arch volume under bounding box");
	expect_eq(euler(mesh), 2, "arch euler");
	expect(mesh.face_count() > 6, "arch has more faces than a box");
	expect(validate(mesh).ok(), "arch validate");
}

SLAB_TEST(closed_sweep_does_not_yet_commit) {
	IVec3 path[4];
	quantize(godot::Vector3(2, 0, 0), path[0]);
	quantize(godot::Vector3(0, 0, 2), path[1]);
	quantize(godot::Vector3(-2, 0, 0), path[2]);
	quantize(godot::Vector3(0, 0, -2), path[3]);
	const IVec3 profile[4] = {
		IVec3{ 0, 0, 0 },
		IVec3{ LATTICE / 2, 0, 0 },
		IVec3{ LATTICE / 2, LATTICE / 2, 0 },
		IVec3{ 0, LATTICE / 2, 0 },
	};
	MeshEdit edit = MeshEdit::empty();
	expect(ops::sweep(edit, path, 4, profile, 4, true).ok(), "closed sweep op");
	Mesh mesh;
	const MeshFault committed = std::move(edit).commit(mesh);
	expect(!committed.ok(), "closed sweep does not yet produce a torus");
}
