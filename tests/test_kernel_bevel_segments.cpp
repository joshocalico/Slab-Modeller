#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/bevel.hpp"
#include "kernel/ops/primitives.hpp"

#include <algorithm>
#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;

static Mesh segmented_box() {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 3, 2)).ok(), "make segmented bevel box");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "commit segmented bevel box");
	return mesh;
}

static EdgeId first_segmented_edge(const Mesh &p_mesh) {
	std::vector<EdgeId> edges;
	p_mesh.all_edges(edges);
	return edges.empty() ? EdgeId{} : edges.front();
}

static int euler_characteristic(const Mesh &p_mesh) {
	return p_mesh.vertex_count() - p_mesh.edge_count() + p_mesh.face_count();
}

SLAB_TEST(four_segment_bevel_builds_a_rounded_transition) {
	const Mesh box = segmented_box();
	const EdgeId edge = first_segmented_edge(box);
	FaceId side_a;
	FaceId side_b;
	box.edge_faces(edge, side_a, side_b);
	const godot::Vector3 normal_a = box.face_normal(side_a);
	const godot::Vector3 normal_b = box.face_normal(side_b);

	MeshEdit flat_edit(box);
	expect(ops::bevel(flat_edit, { edge }, 0.3f, 1).ok(), "flat comparison bevel");
	Mesh flat;
	expect(std::move(flat_edit).commit(flat).ok(), "flat comparison commits");

	MeshEdit rounded_edit(box);
	const MeshFault rounded_fault = ops::bevel(rounded_edit, { edge }, 0.3f, 4);
	expect_eq(int(rounded_fault.code), int(MeshError::OK), "four segment bevel");
	Mesh rounded;
	expect(std::move(rounded_edit).commit(rounded).ok(), "rounded bevel commits");
	expect(validate(rounded).ok(), "rounded bevel validates");
	expect_eq(rounded.vertex_count(), 16, "four segments add six profile vertices");
	expect_eq(rounded.edge_count(), 24, "four segments add nine profile edges");
	expect_eq(rounded.face_count(), 10, "four segments replace one chamfer with four bands");
	expect_eq(euler_characteristic(rounded), 2, "rounded bevel remains closed genus zero");
	expect(rounded.signed_volume() > flat.signed_volume(), "rounded profile retains more volume than a flat chamfer");
	expect(rounded.signed_volume() < box.signed_volume(), "rounded profile still removes the corner");

	std::vector<FaceId> faces;
	rounded.all_faces(faces);
	std::vector<double> slopes;
	for (const FaceId face : faces) {
		const godot::Vector3 normal = rounded.face_normal(face);
		const double a = normal.dot(normal_a);
		const double b = normal.dot(normal_b);
		if (a > 0.05 && b > 0.05) {
			slopes.push_back(a / b);
		}
	}
	expect_eq(int(slopes.size()), 4, "rounded transition has four chamfer bands");
	std::sort(slopes.begin(), slopes.end());
	for (size_t i = 1; i < slopes.size(); i++) {
		expect(std::abs(slopes[i] - slopes[i - 1]) > 0.01, "successive bands have distinct normals");
	}
}

SLAB_TEST(one_segment_overload_is_the_legacy_chamfer) {
	const Mesh box = segmented_box();
	const EdgeId edge = first_segmented_edge(box);
	MeshEdit legacy_edit(box);
	MeshEdit overload_edit(box);
	expect(ops::bevel(legacy_edit, { edge }, 0.25f).ok(), "legacy bevel");
	expect(ops::bevel(overload_edit, { edge }, 0.25f, 1).ok(), "one segment overload");
	Mesh legacy;
	Mesh overload;
	expect(std::move(legacy_edit).commit(legacy).ok(), "legacy commit");
	expect(std::move(overload_edit).commit(overload).ok(), "overload commit");
	expect_eq(overload.vertex_count(), legacy.vertex_count(), "one segment vertex count");
	expect_eq(overload.edge_count(), legacy.edge_count(), "one segment edge count");
	expect_eq(overload.face_count(), legacy.face_count(), "one segment face count");
	expect_near(overload.signed_volume(), legacy.signed_volume(), 0.000001, "one segment volume is unchanged");
}

SLAB_TEST(bevel_segment_count_clamps_to_published_bounds) {
	const Mesh box = segmented_box();
	const EdgeId edge = first_segmented_edge(box);
	MeshEdit below(box);
	expect(ops::bevel(below, { edge }, 0.3f, 0).ok(), "zero segments clamps to one");
	Mesh low;
	expect(std::move(below).commit(low).ok(), "low clamp commits");
	expect_eq(low.face_count(), 7, "low clamp is one chamfer face");

	MeshEdit above(box);
	expect(ops::bevel(above, { edge }, 0.3f, 99).ok(), "large segment count clamps to sixteen");
	Mesh high;
	expect(std::move(above).commit(high).ok(), "high clamp commits");
	expect_eq(high.face_count(), 22, "high clamp makes sixteen bands");
	expect_eq(euler_characteristic(high), 2, "high clamp remains closed");
}

SLAB_TEST(segmented_bevel_rejects_lattice_collapsed_profiles_before_mutation) {
	const Mesh box = segmented_box();
	MeshEdit edit(box);
	const MeshFault fault = ops::bevel(edit, { first_segmented_edge(box) }, 2.0f / float(LATTICE), 16);
	expect_eq(int(fault.code), int(MeshError::SNAP_COLLAPSED_TOPOLOGY), "collapsed samples report snap topology");
	expect_eq(edit.scratch().vertex_count(), box.vertex_count(), "collapsed profile adds no vertices");
	expect_eq(edit.scratch().edge_count(), box.edge_count(), "collapsed profile adds no edges");
	expect_eq(edit.scratch().face_count(), box.face_count(), "collapsed profile adds no faces");
}

SLAB_TEST(three_segment_bevel_preserves_face_attributes) {
	const Mesh box = segmented_box();
	MeshEdit edit(box);
	std::vector<FaceId> faces;
	box.all_faces(faces);
	FaceAttrs attrs;
	attrs.material_slot = 23;
	attrs.uv_scale = godot::Vector2(2.0f, 3.0f);
	attrs.smooth = true;
	for (const FaceId face : faces) {
		edit.set_attrs(face, attrs);
	}
	expect(ops::bevel(edit, { first_segmented_edge(box) }, 0.25f, 3).ok(), "painted segmented bevel");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "painted segmented bevel commits");
	out.all_faces(faces);
	for (const FaceId face : faces) {
		const FaceAttrs got = out.attrs(face);
		expect_eq(got.material_slot, 23, "bevel band preserves material");
		expect_near(got.uv_scale.y, 3.0, 0.0001, "bevel band preserves uv scale");
		expect(got.smooth, "bevel band preserves smoothing");
	}
}

SLAB_TEST(segmented_bevel_handles_three_selected_edges) {
	const Mesh box = segmented_box();
	std::vector<EdgeId> edges;
	box.all_edges(edges);
	std::vector<EdgeId> selected;
	std::vector<uint32_t> used;
	for (const EdgeId edge : edges) {
		VertexId a;
		VertexId b;
		box.edge_vertices(edge, a, b);
		if (std::find(used.begin(), used.end(), a.slot) != used.end() || std::find(used.begin(), used.end(), b.slot) != used.end()) continue;
		selected.push_back(edge);
		used.push_back(a.slot);
		used.push_back(b.slot);
		if (selected.size() == 3) break;
	}
	expect_eq(int(selected.size()), 3, "box has three independently seatable edges");
	MeshEdit edit(box);
	expect(ops::bevel(edit, selected, 0.15f, 3).ok(), "bevel three selected edges");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "three rounded edges commit");
	expect(validate(out).ok(), "three rounded edges are closed and embedded");
	expect_eq(euler_characteristic(out), 2, "three rounded edges keep Euler characteristic");
	std::vector<FaceId> faces;
	out.all_faces(faces);
	for (const FaceId face : faces) {
		expect(out.face_normal(face).length() > 0.9f, "multi-bevel faces have usable normals");
	}
}

SLAB_TEST(segmented_bevel_builds_a_joint_three_edge_corner) {
	const Mesh box = segmented_box();
	std::vector<VertexId> vertices;
	box.all_vertices(vertices);
	std::vector<EdgeId> selected;
	box.vertex_edges(vertices.front(), selected);
	expect_eq(int(selected.size()), 3, "box corner has three incident edges");
	MeshEdit edit(box);
	std::vector<std::pair<IVec3, IVec3>> original_edges;
	for (const EdgeId edge : selected) {
		VertexId a;
		VertexId b;
		box.edge_vertices(edge, a, b);
		original_edges.push_back({ box.position_i(a), box.position_i(b) });
	}
	const MeshFault fault = ops::bevel(edit, selected, 0.15f, 3);
	expect_eq(int(fault.code), int(MeshError::OK), "joint corner bevel succeeds");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "joint corner commits");
	expect(validate(out).ok(), "joint corner is closed and embedded");
	expect_eq(euler_characteristic(out), 2, "joint corner keeps Euler characteristic");
	std::vector<EdgeId> out_edges;
	out.all_edges(out_edges);
	for (const auto &original : original_edges) {
		bool remains = false;
		for (const EdgeId edge : out_edges) {
			VertexId a;
			VertexId b;
			out.edge_vertices(edge, a, b);
			const IVec3 pa = out.position_i(a);
			const IVec3 pb = out.position_i(b);
			remains = remains || ((pa == original.first && pb == original.second) || (pa == original.second && pb == original.first));
		}
		expect(!remains, "every selected incident edge is geometrically retired");
	}
	expect(out.signed_volume() > 0.0 && out.signed_volume() < box.signed_volume(), "joint corner removes finite volume");
	std::vector<FaceId> faces;
	out.all_faces(faces);
	for (const FaceId face : faces) {
		expect(out.face_normal(face).length() > 0.9f, "joint corner faces have usable normals");
	}
}
