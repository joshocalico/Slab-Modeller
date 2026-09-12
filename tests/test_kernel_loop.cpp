#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/loop.hpp"
#include "kernel/ops/primitives.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;

static Mesh loop_box() {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(4, 3, 2)).ok(), "make box");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "commit box");
	return mesh;
}

static EdgeId first_edge(const Mesh &p_mesh) {
	std::vector<EdgeId> edges;
	p_mesh.all_edges(edges);
	return edges.empty() ? EdgeId{} : edges.front();
}

static bool has_position(const Mesh &p_mesh, const IVec3 &p_position) {
	std::vector<VertexId> vertices;
	p_mesh.all_vertices(vertices);
	for (const VertexId vertex : vertices) {
		if (p_mesh.position_i(vertex) == p_position) {
			return true;
		}
	}
	return false;
}

SLAB_TEST(loop_preview_and_three_cuts_share_exact_positions) {
	const Mesh box = loop_box();
	const EdgeId edge = first_edge(box);
	const std::vector<float> positions = { 0.25f, 0.5f, 0.75f };
	std::vector<std::pair<IVec3, IVec3>> preview;
	expect(ops::loop_segments(box, edge, positions, preview).ok(), "preview three loops");
	expect_eq(int(preview.size()), 12, "three loops cross four box faces");

	MeshEdit edit(box);
	expect(ops::insert_loops(edit, edge, positions).ok(), "insert three loops");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "commit three loops");
	expect(validate(out).ok(), "three loops validate");
	expect_eq(out.vertex_count(), 20, "three loops add twelve vertices");
	expect_eq(out.edge_count(), 36, "three loops add twenty-four edges");
	expect_eq(out.face_count(), 18, "three loops split twelve faces");
	expect_near(out.signed_volume(), box.signed_volume(), 0.0001, "loops preserve volume");
	for (const auto &segment : preview) {
		expect(has_position(out, segment.first), "preview first endpoint is committed exactly");
		expect(has_position(out, segment.second), "preview second endpoint is committed exactly");
	}
}

SLAB_TEST(loop_cut_positions_may_be_unsorted) {
	const Mesh box = loop_box();
	MeshEdit edit(box);
	expect(ops::insert_loops(edit, first_edge(box), { 0.8f, 0.2f, 0.6f }).ok(), "insert unsorted positions");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "commit unsorted positions");
	expect_eq(out.vertex_count(), 20, "unsorted positions all survive");
	expect(validate(out).ok(), "unsorted result validates");
}

SLAB_TEST(loop_cuts_copy_all_face_attributes) {
	const Mesh box = loop_box();
	MeshEdit edit(box);
	std::vector<FaceId> faces;
	box.all_faces(faces);
	FaceAttrs attrs;
	attrs.uv_scale = godot::Vector2(2.5f, 3.5f);
	attrs.uv_offset = godot::Vector2(0.2f, 0.4f);
	attrs.uv_rotation = 0.3f;
	attrs.uv_axis = UvAxis::Z;
	attrs.material_slot = 17;
	attrs.smooth = true;
	for (const FaceId face : faces) {
		edit.set_attrs(face, attrs);
	}
	expect(ops::insert_loops(edit, first_edge(box), { 0.3f, 0.7f }).ok(), "insert painted loops");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "commit painted loops");
	out.all_faces(faces);
	for (const FaceId face : faces) {
		const FaceAttrs got = out.attrs(face);
		expect_eq(got.material_slot, 17, "material copied");
		expect_near(got.uv_scale.x, 2.5, 0.0001, "uv scale copied");
		expect_near(got.uv_offset.y, 0.4, 0.0001, "uv offset copied");
		expect_near(got.uv_rotation, 0.3, 0.0001, "uv rotation copied");
		expect_eq(int(got.uv_axis), int(UvAxis::Z), "uv axis copied");
		expect(got.smooth, "smooth copied");
	}
}

SLAB_TEST(loop_cuts_reject_invalid_positions_without_mutating) {
	const Mesh box = loop_box();
	const std::vector<std::vector<float>> invalid = {
		{}, { 0.0f }, { 1.0f }, { -0.1f }, { 1.1f }, { 0.4f, 0.4f },
		{ std::numeric_limits<float>::quiet_NaN() }, { std::numeric_limits<float>::infinity() },
		{ 0.00001f, 0.00002f },
	};
	for (const auto &positions : invalid) {
		MeshEdit edit(box);
		expect(!ops::insert_loops(edit, first_edge(box), positions).ok(), "invalid positions rejected");
		expect_eq(edit.scratch().vertex_count(), box.vertex_count(), "invalid positions keep vertices");
		expect_eq(edit.scratch().edge_count(), box.edge_count(), "invalid positions keep edges");
		expect_eq(edit.scratch().face_count(), box.face_count(), "invalid positions keep faces");
	}
}

SLAB_TEST(loop_preview_terminates_at_a_concave_ngon) {
	const IVec3 concave[] = {
		{ -2048, 0, 2048 }, { 0, 0, 512 }, { 2048, 0, 2048 },
		{ 2048, 0, -2048 }, { -2048, 0, -2048 },
	};
	MeshEdit edit = MeshEdit::empty();
	expect(ops::prism(edit, concave, 5, 2048).ok(), "make concave prism");
	Mesh prism;
	expect(std::move(edit).commit(prism).ok(), "commit concave prism");

	std::vector<FaceId> faces;
	prism.all_faces(faces);
	EdgeId cap_edge;
	for (const FaceId face : faces) {
		std::vector<VertexId> corners;
		prism.face_corners(face, corners);
		if (corners.size() == 5) {
			std::vector<EdgeId> edges;
			prism.face_edges(face, edges);
			cap_edge = edges.front();
			break;
		}
	}
	std::vector<std::pair<IVec3, IVec3>> preview;
	expect(ops::loop_segments(prism, cap_edge, { 0.5f }, preview).ok(), "quad side previews up to ngon");
	expect_eq(int(preview.size()), 1, "ngon terminates after adjacent quad");
	MeshEdit cut(prism);
	expect(ops::insert_loops(cut, cap_edge, { 0.5f }).ok(), "insert terminated strip");
	Mesh out;
	expect(std::move(cut).commit(out).ok(), "terminated strip remains a solid");
	expect(validate(out).ok(), "terminated strip validates");
}
