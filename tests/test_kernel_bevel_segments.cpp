#include "harness.hpp"
#include "mesh_signature.hpp"

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

static Mesh thin_roof_box() {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(4.4f, 0.2f, 4.4f)).ok(), "make thin roof box");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "commit thin roof box");
	return mesh;
}

static std::vector<EdgeId> top_perimeter(const Mesh &p_mesh) {
	std::vector<VertexId> vertices;
	p_mesh.all_vertices(vertices);
	int32_t max_y = INT32_MIN;
	for (const VertexId vertex : vertices) max_y = std::max(max_y, p_mesh.position_i(vertex).y);
	std::vector<EdgeId> edges;
	std::vector<EdgeId> result;
	p_mesh.all_edges(edges);
	for (const EdgeId edge : edges) {
		VertexId a;
		VertexId b;
		p_mesh.edge_vertices(edge, a, b);
		if (p_mesh.position_i(a).y == max_y && p_mesh.position_i(b).y == max_y) result.push_back(edge);
	}
	return result;
}

static std::vector<IVec3> sorted_positions(const Mesh &p_mesh) {
	std::vector<VertexId> vertices;
	p_mesh.all_vertices(vertices);
	std::vector<IVec3> result;
	for (const VertexId vertex : vertices) result.push_back(p_mesh.position_i(vertex));
	std::sort(result.begin(), result.end(), [](const IVec3 &a, const IVec3 &b) {
		if (a.x != b.x) return a.x < b.x;
		if (a.y != b.y) return a.y < b.y;
		return a.z < b.z;
	});
	return result;
}

static Mesh bevel_painted_top_perimeter(int p_segments, bool p_reverse) {
	const Mesh source = thin_roof_box();
	MeshEdit edit(source);
	std::vector<FaceId> faces;
	source.all_faces(faces);
	FaceAttrs attrs;
	attrs.material_slot = 31;
	attrs.uv_scale = godot::Vector2(2.5f, 3.5f);
	attrs.uv_offset = godot::Vector2(0.125f, 0.375f);
	attrs.uv_rotation = 27.0f;
	for (const FaceId face : faces) edit.set_attrs(face, attrs);
	std::vector<EdgeId> edges = top_perimeter(source);
	if (p_reverse) std::reverse(edges.begin(), edges.end());
	expect_eq(int(edges.size()), 4, "thin roof has four top perimeter edges");
	const MeshFault fault = ops::bevel(edit, edges, 0.03f, p_segments);
	expect_eq(int(fault.code), int(MeshError::OK), "connected top perimeter bevel runs");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "connected top perimeter bevel commits");
	return out;
}

static void expect_painted_valid_perimeter(const Mesh &p_mesh, const char *p_label) {
	expect(validate(p_mesh).ok(), p_label);
	expect(p_mesh.signed_volume() > 0.0, "connected perimeter keeps positive volume");
	expect_eq(euler_characteristic(p_mesh), 2, "connected perimeter stays closed genus zero");
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	for (const FaceId face : faces) {
		const FaceAttrs attrs = p_mesh.attrs(face);
		expect_eq(attrs.material_slot, 31, "connected perimeter preserves material inheritance");
		expect_near(attrs.uv_scale.x, 2.5, 0.0001, "connected perimeter preserves UV scale");
		expect_near(attrs.uv_offset.y, 0.375, 0.0001, "connected perimeter preserves UV offset");
		expect_near(attrs.uv_rotation, 27.0, 0.0001, "connected perimeter preserves UV rotation");
	}
}

SLAB_TEST(connected_top_perimeter_bevels_flat_and_round) {
	const Mesh flat = bevel_painted_top_perimeter(1, false);
	const Mesh rounded = bevel_painted_top_perimeter(3, false);
	expect_painted_valid_perimeter(flat, "flat connected perimeter validates");
	expect_painted_valid_perimeter(rounded, "rounded connected perimeter validates");
	expect(rounded.face_count() > flat.face_count(), "three segments add rounded perimeter bands");
}

SLAB_TEST(connected_top_perimeter_is_selection_order_invariant) {
	const Mesh forward = bevel_painted_top_perimeter(3, false);
	const Mesh reverse = bevel_painted_top_perimeter(3, true);
	expect(sorted_positions(forward) == sorted_positions(reverse), "reordered perimeter has identical vertex positions");
	expect_eq(forward.face_count(), reverse.face_count(), "reordered perimeter has identical face count");
	expect_near(forward.signed_volume(), reverse.signed_volume(), 0.000001, "reordered perimeter has identical volume");
}

SLAB_TEST(connected_top_perimeter_all_orders_keep_exact_geometry_and_attributes) {
	const Mesh source = thin_roof_box();
	std::vector<EdgeId> perimeter = top_perimeter(source);
	std::vector<int> order = { 0, 1, 2, 3 };
	slabtest::MeshSignature expected;
	int permutations = 0;
	do {
		MeshEdit edit(source);
		std::vector<FaceId> faces;
		source.all_faces(faces);
		for (size_t i = 0; i < faces.size(); i++) {
			FaceAttrs attrs;
			attrs.material_slot = uint16_t(40 + i);
			attrs.uv_scale = godot::Vector2(1.0f + float(i), 2.0f + float(i));
			attrs.uv_offset = godot::Vector2(0.01f * float(i), 0.02f * float(i));
			attrs.uv_rotation = float(i * 7);
			edit.set_attrs(faces[i], attrs);
		}
		std::vector<EdgeId> selected;
		for (const int at : order) selected.push_back(perimeter[size_t(at)]);
		expect(ops::bevel(edit, selected, 0.03f, 3).ok(), "every perimeter order bevels");
		Mesh result;
		expect(std::move(edit).commit(result).ok(), "every perimeter order commits");
		const slabtest::MeshSignature signature = slabtest::mesh_signature(result);
		if (permutations == 0) expected = signature;
		else expect(signature == expected, "every perimeter order has identical face geometry and attributes");
		permutations++;
	} while (std::next_permutation(order.begin(), order.end()));
	expect_eq(permutations, 24, "all perimeter permutations covered");
}

SLAB_TEST(connected_top_perimeter_keeps_requested_source_width) {
	const Mesh result = bevel_painted_top_perimeter(3, false);
	std::vector<FaceId> faces;
	result.all_faces(faces);
	bool found_inset_top = false;
	for (const FaceId face : faces) {
		std::vector<VertexId> corners;
		result.face_corners(face, corners);
		if (corners.size() != 4) continue;
		int32_t min_x = INT32_MAX, max_x = INT32_MIN, min_z = INT32_MAX, max_z = INT32_MIN;
		bool top = true;
		for (const VertexId corner : corners) {
			const IVec3 point = result.position_i(corner);
			top = top && point.y == 205;
			min_x = std::min(min_x, point.x); max_x = std::max(max_x, point.x);
			min_z = std::min(min_z, point.z); max_z = std::max(max_z, point.z);
		}
		if (!top) continue;
		found_inset_top = true;
		expect_eq(min_x, 31, "top inset keeps requested x width");
		expect_eq(min_z, 31, "top inset keeps requested z width");
		expect_eq(max_x, 4475, "opposite x inset keeps requested width");
		expect_eq(max_z, 4475, "opposite z inset keeps requested width");
	}
	expect(found_inset_top, "connected bevel retains one inset top face");
}

SLAB_TEST(connected_open_chain_builds_shared_corner_and_endpoint_profiles) {
	const Mesh source = thin_roof_box();
	const std::vector<EdgeId> perimeter = top_perimeter(source);
	std::vector<EdgeId> chain;
	chain.push_back(perimeter.front());
	VertexId first_a;
	VertexId first_b;
	source.edge_vertices(perimeter.front(), first_a, first_b);
	for (size_t i = 1; i < perimeter.size(); i++) {
		VertexId a;
		VertexId b;
		source.edge_vertices(perimeter[i], a, b);
		if (a.slot == first_a.slot || a.slot == first_b.slot || b.slot == first_a.slot || b.slot == first_b.slot) {
			chain.push_back(perimeter[i]);
			break;
		}
	}
	expect_eq(int(chain.size()), 2, "open chain finds two adjacent perimeter edges");
	MeshEdit edit(source);
	expect(ops::bevel(edit, chain, 0.03f, 3).ok(), "open two-edge chain bevels");
	Mesh result;
	expect(std::move(edit).commit(result).ok(), "open two-edge chain commits");
	expect(validate(result).ok(), "open two-edge chain validates");
	expect(result.signed_volume() > 0.0, "open two-edge chain keeps positive volume");
	expect_eq(euler_characteristic(result), 2, "open two-edge chain stays closed genus zero");
	expect(result.face_count() > source.face_count(), "open chain emits rounded bands and endpoint profiles");
}

SLAB_TEST(connected_roof_bevel_preserves_an_untouched_bottom_uv_seam) {
	const Mesh source = thin_roof_box();
	std::vector<EdgeId> edges;
	source.all_edges(edges);
	EdgeId bottom;
	IVec3 bottom_a;
	IVec3 bottom_b;
	for (const EdgeId edge : edges) {
		VertexId a;
		VertexId b;
		source.edge_vertices(edge, a, b);
		if (source.position_i(a).y == 0 && source.position_i(b).y == 0) {
			bottom = edge;
			bottom_a = source.position_i(a);
			bottom_b = source.position_i(b);
			break;
		}
	}
	expect(source.alive(bottom), "roof source has an untouched bottom edge");
	MeshEdit edit(source);
	edit.set_uv_seam(bottom, true);
	expect(ops::bevel(edit, top_perimeter(source), 0.03f, 3).ok(), "roof perimeter bevel with unrelated seam runs");
	Mesh result;
	expect(std::move(edit).commit(result).ok(), "roof perimeter bevel with unrelated seam commits");
	bool preserved = false;
	result.all_edges(edges);
	for (const EdgeId edge : edges) {
		VertexId a;
		VertexId b;
		result.edge_vertices(edge, a, b);
		const IVec3 pa = result.position_i(a);
		const IVec3 pb = result.position_i(b);
		if ((pa == bottom_a && pb == bottom_b) || (pa == bottom_b && pb == bottom_a)) {
			preserved = result.edge_uv_seam(edge);
			break;
		}
	}
	expect(preserved, "connected roof bevel preserves the untouched bottom UV seam");
}

SLAB_TEST(unsupported_connected_valence_is_atomic) {
	const Mesh source = thin_roof_box();
	MeshEdit edit(source);
	std::vector<EdgeId> all_edges;
	source.all_edges(all_edges);
	const MeshFault fault = ops::bevel(edit, all_edges, 0.05f, 3);
	expect(!fault.ok(), "all-edge degree-three selection remains explicitly unsupported");
	expect(slabtest::mesh_signature(edit.scratch()) == slabtest::mesh_signature(source), "rejected connected selection leaves scratch unchanged");
	Mesh committed;
	expect(std::move(edit).commit(committed).ok(), "rejected connected selection does not poison the edit");
	expect(slabtest::mesh_signature(committed) == slabtest::mesh_signature(source), "rejected edit commits the exact source mesh");
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
