#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/boolean.hpp"
#include "kernel/ops/edit.hpp"
#include "kernel/ops/plane_cut.hpp"
#include "kernel/ops/primitives.hpp"

#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;

static Mesh cut_box(const godot::Vector3 &p_size) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, p_size).ok(), "box");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "box commit");
	return mesh;
}

static Mesh cut_shifted(const Mesh &p_mesh, const godot::Vector3 &p_delta) {
	Mesh result = p_mesh;
	MeshEdit edit(result);
	std::vector<VertexId> vertices;
	result.all_vertices(vertices);
	expect(ops::move_vertices(edit, vertices, p_delta).ok(), "move solid");
	expect(std::move(edit).commit(result).ok(), "move commit");
	return result;
}

static int cap_faces(const Mesh &p_mesh, const IVec3 &p_origin, const IVec3 &p_normal,
		float p_expected_normal_x, uint32_t p_material) {
	int count = 0;
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	for (const FaceId id : faces) {
		std::vector<VertexId> corners;
		p_mesh.face_corners(id, corners);
		bool on_plane = true;
		for (const VertexId v : corners) {
			const IVec3 p = p_mesh.position_i(v);
			const __int128 side = (__int128(p.x) - p_origin.x) * p_normal.x +
					(__int128(p.y) - p_origin.y) * p_normal.y +
					(__int128(p.z) - p_origin.z) * p_normal.z;
			on_plane &= side == 0;
		}
		if (on_plane) {
			count++;
			expect(p_mesh.face_normal(id).x > p_expected_normal_x, "cap winding faces out of retained solid");
			expect_eq(p_mesh.attrs(id).material_slot, p_material, "cap material");
		}
	}
	return count;
}

SLAB_TEST(plane_cut_halves_box_and_caps_with_outward_normal) {
	Mesh mesh = cut_shifted(cut_box(godot::Vector3(4, 2, 2)), godot::Vector3(-2, -1, -1));
	MeshEdit edit(mesh);
	FaceAttrs cap;
	cap.material_slot = 19;
	cap.uv_scale = godot::Vector2(3, 5);
	expect(ops::plane_cut(edit, IVec3{ 0, 0, 0 }, IVec3{ 1, 0, 0 }, ops::PlaneSide::NEGATIVE, cap).ok(), "plane cut");
	Mesh half;
	const MeshFault committed = std::move(edit).commit(half);
	expect_eq(int(committed.code), int(MeshError::OK), "cut commit code");
	expect(validate(half).ok(), "cut is a closed embedded solid");
	expect_near(half.signed_volume(), 8.0, 0.001, "half box volume");
	expect(cap_faces(half, { 0, 0, 0 }, { 1, 0, 0 }, 0.99f, 19) >= 1, "cap exists");
}

SLAB_TEST(plane_cut_accepts_arbitrary_integer_plane) {
	Mesh mesh = cut_shifted(cut_box(godot::Vector3(4, 4, 4)), godot::Vector3(-2, -2, -2));
	MeshEdit edit(mesh);
	expect(ops::plane_cut(edit, IVec3{ 0, 0, 0 }, IVec3{ 2, -3, 5 }, ops::PlaneSide::POSITIVE).ok(), "oblique cut");
	Mesh half;
	const MeshFault committed = std::move(edit).commit(half);
	expect_eq(int(committed.code), int(MeshError::OK), "oblique commit code");
	expect(validate(half).ok(), "oblique result closed");
	expect(half.signed_volume() > 0.0, "oblique result positive volume");
	expect_near(half.signed_volume(), 32.0, 0.05, "central plane halves symmetric box");
}

SLAB_TEST(plane_cut_caps_a_section_through_a_cavity) {
	Mesh shell = cut_shifted(cut_box(godot::Vector3(4, 4, 4)), godot::Vector3(-2, -2, -2));
	const Mesh void_box = cut_shifted(cut_box(godot::Vector3(2, 2, 2)), godot::Vector3(-1, -1, -1));
	MeshEdit hollow(shell);
	expect(ops::boolean(hollow, void_box, 1).ok(), "make cavity");
	expect(std::move(hollow).commit(shell).ok(), "cavity commit");

	MeshEdit edit(shell);
	expect(ops::plane_cut(edit, { 0, 0, 0 }, { 1, 0, 0 }, ops::PlaneSide::NEGATIVE).ok(), "cut cavity");
	Mesh half_shell;
	const MeshFault committed = std::move(edit).commit(half_shell);
	expect_eq(int(committed.code), int(MeshError::OK), "cavity cut commit code");
	expect(validate(half_shell).ok(), "annular section is closed and embedded");
	expect_near(half_shell.signed_volume(), 28.0, 0.02, "half shell volume");
}

SLAB_TEST(plane_cut_handles_concave_solid_and_multiple_section_loops) {
	Mesh left = cut_shifted(cut_box(godot::Vector3(3, 2, 2)), godot::Vector3(-2, -1, -1));
	const Mesh arm = cut_shifted(cut_box(godot::Vector3(2, 2, 3)), godot::Vector3(-1, -1, -2));
	MeshEdit joined(left);
	expect(ops::boolean(joined, arm, 0).ok(), "make concave solid");
	expect(std::move(joined).commit(left).ok(), "concave commit");

	MeshEdit cut(left);
	expect(ops::plane_cut(cut, { 0, 0, 0 }, { 1, 0, 0 }, ops::PlaneSide::NEGATIVE).ok(), "cut concave solid");
	Mesh result;
	const MeshFault concave_committed = std::move(cut).commit(result);
	expect_eq(int(concave_committed.code), int(MeshError::OK), "concave cut commit code");
	expect(validate(result).ok(), "concave cut stays closed");
	expect(result.signed_volume() > 0.0, "concave cut has positive volume");

	Mesh two = left;
	const Mesh island = cut_shifted(cut_box(godot::Vector3(1, 1, 1)), godot::Vector3(-0.5f, 3, -0.5f));
	MeshEdit append(two);
	expect(append.append(island, false).ok(), "append second component");
	expect(std::move(append).commit(two).ok(), "two component commit");
	MeshEdit multi(two);
	expect(ops::plane_cut(multi, { 0, 0, 0 }, { 1, 0, 0 }, ops::PlaneSide::NEGATIVE).ok(), "cut multiple loops");
	Mesh multi_result;
	const MeshFault multi_committed = std::move(multi).commit(multi_result);
	expect_eq(int(multi_committed.code), int(MeshError::OK), "multiple loop commit code");
	expect(validate(multi_result).ok(), "multiple cap loops stay closed");
}

SLAB_TEST(plane_cut_no_intersection_is_stable_and_tangent_empty_is_reported) {
	Mesh box = cut_box(godot::Vector3(2, 2, 2));
	const double before = box.signed_volume();
	MeshEdit untouched(box);
	expect(ops::plane_cut(untouched, { -1024, 0, 0 }, { 1, 0, 0 }, ops::PlaneSide::POSITIVE).ok(), "coplanar supporting plane keeps box");
	Mesh same;
	expect(std::move(untouched).commit(same).ok(), "unchanged commit");
	expect_near(same.signed_volume(), before, 0.0, "no-intersection cut is unchanged");

	MeshEdit tangent(box);
	const MeshFault empty = ops::plane_cut(tangent, { 0, 0, 0 }, { 1, 0, 0 }, ops::PlaneSide::NEGATIVE);
	expect(!empty.ok(), "opposite tangent halfspace has no volume");
	expect_eq(int(empty.code), int(MeshError::RESULT_EMPTY), "tangent empty code");
}

SLAB_TEST(plane_cut_rejects_zero_normal_without_mutating) {
	Mesh box = cut_box(godot::Vector3(2, 2, 2));
	MeshEdit edit(box);
	const MeshFault fault = ops::plane_cut(edit, {}, {}, ops::PlaneSide::POSITIVE);
	expect(!fault.ok(), "zero normal rejected");
	expect_eq(int(fault.code), int(MeshError::DEGENERATE_FACE), "zero normal code");
	expect_near(edit.scratch().signed_volume(), box.signed_volume(), 0.0, "rejection does not mutate");
}
