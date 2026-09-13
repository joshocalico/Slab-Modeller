#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/bevel.hpp"
#include "kernel/ops/bridge.hpp"
#include "kernel/ops/edit.hpp"
#include "kernel/ops/inset.hpp"
#include "kernel/ops/loop.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/ops/subdivide.hpp"
#include "kernel/ops/weld.hpp"

#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;

static Mesh unit_box() {
	MeshEdit edit = MeshEdit::empty();
	ops::box(edit, godot::Vector3(2, 3, 2));
	Mesh mesh;
	std::move(edit).commit(mesh);
	return mesh;
}

static int euler(const Mesh &p_mesh) {
	return p_mesh.vertex_count() - p_mesh.edge_count() + p_mesh.face_count();
}

static FaceId face_facing(const Mesh &p_mesh, const godot::Vector3 &p_dir) {
	FaceId best;
	float score = -2.0f;
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	for (const FaceId id : faces) {
		const float d = p_mesh.face_normal(id).dot(p_dir);
		if (d > score) {
			score = d;
			best = id;
		}
	}
	return best;
}

static FaceId top_face(const Mesh &p_mesh) {
	return face_facing(p_mesh, godot::Vector3(0, 1, 0));
}

static std::vector<FaceId> upward_faces(const Mesh &p_mesh) {
	std::vector<FaceId> out;
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	for (const FaceId id : faces) {
		if (p_mesh.face_normal(id).y > 0.99f) {
			out.push_back(id);
		}
	}
	return out;
}

static VertexId far_corner(const Mesh &p_mesh, VertexId p_from) {
	VertexId best;
	double reach = -1.0;
	std::vector<VertexId> all;
	p_mesh.all_vertices(all);
	for (const VertexId v : all) {
		const double d = (p_mesh.position(v) - p_mesh.position(p_from)).length();
		if (d > reach) {
			reach = d;
			best = v;
		}
	}
	return best;
}

static EdgeId edge_between(const Mesh &p_mesh, VertexId p_a, VertexId p_b) {
	std::vector<EdgeId> edges;
	p_mesh.vertex_edges(p_a, edges);
	for (const EdgeId id : edges) {
		VertexId x;
		VertexId y;
		p_mesh.edge_vertices(id, x, y);
		if (x.slot == p_b.slot || y.slot == p_b.slot) {
			return id;
		}
	}
	return EdgeId{};
}

SLAB_TEST(inset_keeps_the_cap_id_and_its_attrs) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);

	FaceAttrs attrs;
	attrs.uv_scale = godot::Vector2(2, 4);
	attrs.uv_offset = godot::Vector2(0.25f, 0.5f);
	attrs.material_slot = 5;

	MeshEdit edit(box);
	edit.set_attrs(top, attrs);
	const double cap_area_before = edit.scratch().face_area(top);
	expect(ops::inset(edit, { top }, 0.25f).ok(), "inset op");

	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "inset commit");
	expect(out.alive(top), "inset keeps the face id on the centre cap");
	expect_eq(out.face_count(), 10, "inset faces");
	expect_eq(out.vertex_count(), 12, "inset verts");
	expect_eq(out.edge_count(), 20, "inset edges");
	expect_eq(euler(out), 2, "inset euler");
	expect(out.signed_volume() > 0.0, "inset volume stays positive");
	expect_near(out.signed_volume(), 12.0, 0.0001, "an in-plane inset moves no volume");
	expect(out.face_area(top) < cap_area_before, "inset shrinks the cap");
	expect_near(out.face_area(top), 2.25, 0.0001, "cap is the 1.5 by 1.5 remainder");
	expect_eq(int(out.attrs(top).material_slot), 5, "cap keeps its material slot");
	expect_near(out.attrs(top).uv_scale.y, 4.0, 0.0001, "cap keeps its uv scale");
	expect_near(out.attrs(top).uv_offset.x, 0.25, 0.0001, "cap keeps its uv offset");

	std::vector<VertexId> cap_corners;
	out.face_corners(top, cap_corners);
	expect_eq(int(cap_corners.size()), 4, "cap keeps its corner count");
	for (const VertexId v : cap_corners) {
		expect_eq(out.position_i(v).y, 3072, "cap stays in the face plane");
	}
}

SLAB_TEST(inset_copies_attrs_onto_the_rim) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<FaceId> before;
	box.all_faces(before);

	FaceAttrs attrs;
	attrs.material_slot = 7;
	MeshEdit edit(box);
	edit.set_attrs(top, attrs);
	expect(ops::inset(edit, { top }, 0.25f).ok(), "inset op");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "inset commit");

	std::vector<FaceId> after;
	out.all_faces(after);
	int rim = 0;
	for (const FaceId id : after) {
		bool existed = false;
		for (const FaceId old : before) {
			if (old.slot == id.slot) {
				existed = true;
			}
		}
		if (existed) {
			continue;
		}
		rim++;
		expect_eq(int(out.attrs(id).material_slot), 7, "rim face copies the cap material slot");
		expect_near(out.face_normal(id).y, 1.0, 0.0001, "rim face stays in the cap plane");
	}
	expect_eq(rim, 4, "inset adds one rim face per original edge");
}

SLAB_TEST(inset_clamps_an_amount_that_would_invert) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);

	MeshEdit edit(box);
	expect(ops::inset(edit, { top }, 5.0f).ok(), "oversized inset op");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "oversized inset commit");
	expect_eq(out.face_count(), 10, "clamped inset faces");
	expect_eq(euler(out), 2, "clamped inset euler");
	expect(out.face_area(top) > 0.0, "clamped inset leaves a positive cap area");
	expect(out.face_area(top) < 4.0, "clamped inset still shrinks the cap");
	expect_near(out.signed_volume(), 12.0, 0.0001, "clamped inset moves no volume");
}

SLAB_TEST(inset_rejects_an_adjacent_selection) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	const FaceId side = face_facing(box, godot::Vector3(0, 0, -1));

	MeshEdit edit(box);
	const MeshFault faulted = ops::inset(edit, { top, side }, 0.25f);
	expect_eq(int(faulted.code), int(MeshError::ADJACENT_SELECTION), "inset of two faces sharing an edge");
	expect_eq(edit.scratch().face_count(), 6, "rejected inset leaves the mesh alone");

	const MeshFault twice = ops::inset(edit, { top, top }, 0.25f);
	expect_eq(int(twice.code), int(MeshError::ADJACENT_SELECTION), "inset of the same face twice");
}

SLAB_TEST(inset_rejects_a_stale_face) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	const FaceId stale{ top.slot, top.gen + 7 };

	MeshEdit edit(box);
	expect_eq(int(ops::inset(edit, { stale }, 0.25f).code), int(MeshError::STALE_HANDLE), "inset stale face");
	expect_eq(int(ops::inset(edit, { FaceId{ 9999, 1 } }, 0.25f).code), int(MeshError::STALE_HANDLE), "inset face past the end");
	expect_eq(edit.scratch().face_count(), 6, "rejected inset adds no faces");
	expect_eq(euler(edit.scratch()), 2, "rejected inset keeps euler at 2");
}

SLAB_TEST(subdivide_keeps_the_face_id_and_the_volume) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);

	FaceAttrs attrs;
	attrs.uv_scale = godot::Vector2(3, 3);
	attrs.material_slot = 4;

	MeshEdit edit(box);
	edit.set_attrs(top, attrs);
	expect(ops::subdivide(edit, { top }).ok(), "subdivide op");

	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "subdivide commit");
	expect(out.alive(top), "subdivide keeps the face id on one child");
	expect_eq(out.face_count(), 9, "subdivide faces");
	expect_eq(out.vertex_count(), 13, "subdivide verts");
	expect_eq(out.edge_count(), 20, "subdivide edges");
	expect_eq(euler(out), 2, "subdivide euler");
	expect_near(out.signed_volume(), 12.0, 0.01, "subdivide moves no volume");
	expect_eq(int(out.attrs(top).material_slot), 4, "kept child copies the material slot");
	expect_near(out.attrs(top).uv_scale.x, 3.0, 0.0001, "kept child copies the uv scale");

	std::vector<FaceId> faces;
	out.all_faces(faces);
	int children = 0;
	double child_area = 0.0;
	for (const FaceId id : faces) {
		std::vector<VertexId> ring;
		out.face_corners(id, ring);
		bool on_cap = true;
		for (const VertexId v : ring) {
			if (out.position_i(v).y != 3072) {
				on_cap = false;
			}
		}
		if (!on_cap) {
			continue;
		}
		children++;
		child_area += out.face_area(id);
		expect_eq(int(ring.size()), 4, "every subdivide child is a quad");
		expect_eq(int(out.attrs(id).material_slot), 4, "every subdivide child copies the material slot");
	}
	expect_eq(children, 4, "subdivide splits the quad into four quads");
	expect_near(child_area, 4.0, 0.0001, "the four children tile the original face");
}

SLAB_TEST(subdivide_turns_a_triangle_into_three_quads) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);

	MeshEdit edit(box);
	edit.split_face(top, corners[0], corners[2]);
	expect(edit.last_fault().ok(), "split the cap into two triangles");
	Mesh triangulated;
	expect(std::move(edit).commit(triangulated).ok(), "triangulated commit");
	expect_eq(triangulated.face_count(), 7, "triangulated faces");

	MeshEdit divide(triangulated);
	expect(ops::subdivide(divide, { top }).ok(), "subdivide a triangle");
	Mesh out;
	expect(std::move(divide).commit(out).ok(), "triangle subdivide commit");
	expect(out.alive(top), "triangle subdivide keeps the face id");
	expect_eq(out.face_count(), 9, "triangle subdivide faces");
	expect_eq(euler(out), 2, "triangle subdivide euler");
	expect_near(out.signed_volume(), 12.0, 0.01, "triangle subdivide moves no volume");
	std::vector<VertexId> kept;
	out.face_corners(top, kept);
	expect_eq(int(kept.size()), 4, "a subdivided triangle yields quads");
}

SLAB_TEST(subdivide_rejects_stale_and_adjacent_selections) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	const FaceId side = face_facing(box, godot::Vector3(0, 0, -1));
	const FaceId stale{ top.slot, top.gen + 7 };

	MeshEdit edit(box);
	expect_eq(int(ops::subdivide(edit, { stale }).code), int(MeshError::STALE_HANDLE), "subdivide stale face");
	expect_eq(int(ops::subdivide(edit, { FaceId{ 9999, 1 } }).code), int(MeshError::STALE_HANDLE), "subdivide face past the end");
	expect_eq(int(ops::subdivide(edit, { top, side }).code), int(MeshError::ADJACENT_SELECTION), "subdivide two faces sharing an edge");
	expect_eq(edit.scratch().face_count(), 6, "rejected subdivide leaves the mesh alone");
	expect_eq(edit.scratch().vertex_count(), 8, "rejected subdivide adds no vertices");
	expect_eq(euler(edit.scratch()), 2, "rejected subdivide keeps euler at 2");
}

SLAB_TEST(subdivide_two_opposite_faces_at_once) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	const FaceId bottom = face_facing(box, godot::Vector3(0, -1, 0));

	MeshEdit edit(box);
	expect(ops::subdivide(edit, { top, bottom }).ok(), "subdivide two non adjacent faces");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "two face subdivide commit");
	expect(out.alive(top), "first face keeps its id");
	expect(out.alive(bottom), "second face keeps its id");
	expect_eq(out.face_count(), 12, "two face subdivide faces");
	expect_eq(out.vertex_count(), 18, "two face subdivide verts");
	expect_eq(euler(out), 2, "two face subdivide euler");
	expect_near(out.signed_volume(), 12.0, 0.01, "two face subdivide moves no volume");
}

SLAB_TEST(merge_faces_consumes_a_connected_coplanar_region_in_any_input_order) {
	const Mesh box = unit_box();
	MeshEdit divided(box);
	expect(ops::subdivide(divided, { top_face(box) }).ok(), "subdivide top before merge");
	Mesh tiled;
	expect(std::move(divided).commit(tiled).ok(), "subdivided top commits");
	const std::vector<FaceId> caps = upward_faces(tiled);
	expect_eq(int(caps.size()), 4, "subdivide leaves four coplanar cap faces");

	const std::vector<std::vector<FaceId>> orders = {
		{ caps[2], caps[0], caps[3], caps[1] },
		{ caps[1], caps[3], caps[0], caps[2] },
	};
	for (const std::vector<FaceId> &order : orders) {
		MeshEdit merged(tiled);
		FaceAttrs first_attrs = merged.scratch().attrs(order[0]);
		first_attrs.material_slot = 17;
		merged.set_attrs(order[0], first_attrs);
		expect(ops::merge_faces(merged, order).ok(), "merge accepts a cyclic region in shuffled order");
		Mesh out;
		expect(std::move(merged).commit(out).ok(), "order-independent merge commits");
		expect_eq(out.face_count(), 6, "four cap tiles merge into one face");
		expect_eq(int(upward_faces(out).size()), 1, "merged cap is one face");
		expect(out.alive(order[0]), "merge keeps the first selected face id");
		expect_eq(int(out.attrs(order[0]).material_slot), 17, "merged face keeps the first selected face attributes");
		expect_eq(euler(out), 2, "merged solid keeps Euler characteristic");
		expect_near(out.signed_volume(), 12.0, 0.0001, "merge preserves volume");
		expect(validate(out).ok(), "merged solid validates");
	}
}

SLAB_TEST(merge_faces_refuses_folded_and_disconnected_regions_atomically) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	const FaceId side = face_facing(box, godot::Vector3(0, 0, -1));
	const FaceId bottom = face_facing(box, godot::Vector3(0, -1, 0));

	MeshEdit folded(box);
	const MeshFault folded_fault = ops::merge_faces(folded, { top, side });
	expect_eq(int(folded_fault.code), int(MeshError::DEGENERATE_FACE), "folded faces refuse merge");
	expect_eq(folded.scratch().face_count(), 6, "folded refusal changes no faces");
	expect(folded.scratch().alive(top) && folded.scratch().alive(side), "folded refusal keeps both face ids");

	MeshEdit disconnected(box);
	const MeshFault disconnected_fault = ops::merge_faces(disconnected, { top, bottom });
	expect_eq(int(disconnected_fault.code), int(MeshError::INVALID_SELECTION), "disconnected faces refuse merge");
	expect_eq(disconnected.scratch().face_count(), 6, "disconnected refusal changes no faces");
	expect(disconnected.scratch().alive(top) && disconnected.scratch().alive(bottom), "disconnected refusal keeps both face ids");

	MeshEdit inset(box);
	expect(ops::inset(inset, { top }, 0.25f).ok(), "inset creates a coplanar ring");
	Mesh ring;
	expect(std::move(inset).commit(ring).ok(), "inset ring commits");
	std::vector<FaceId> rim;
	for (const FaceId id : upward_faces(ring)) {
		if (id.slot != top.slot) {
			rim.push_back(id);
		}
	}
	expect_eq(int(rim.size()), 4, "inset has four rim faces around its cap hole");
	MeshEdit holed(ring);
	const MeshFault hole_fault = ops::merge_faces(holed, rim);
	expect_eq(int(hole_fault.code), int(MeshError::MULTIPLE_BOUNDARY_LOOPS), "a region with a hole has a typed merge refusal");
	expect_eq(holed.scratch().face_count(), ring.face_count(), "hole refusal changes no faces");
}

SLAB_TEST(merge_faces_cannot_clear_an_existing_edit_fault) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);
	MeshEdit poisoned(box);
	poisoned.split_face(top, corners[0], corners[2]);
	expect(poisoned.last_fault().ok(), "split creates a valid merge target");
	const std::vector<FaceId> split = upward_faces(poisoned.scratch());
	expect_eq(int(split.size()), 2, "split top has two faces to merge");
	poisoned.move_vertex(VertexId{ 9999, 1 }, IVec3{});
	expect_eq(int(poisoned.last_fault().code), int(MeshError::STALE_HANDLE), "stale move poisons the edit");
	const MeshFault merged = ops::merge_faces(poisoned, split);
	expect_eq(int(merged.code), int(MeshError::STALE_HANDLE), "merge returns the existing fault");
	expect_eq(poisoned.scratch().face_count(), 7, "merge leaves poisoned scratch unchanged");
	Mesh out;
	const MeshFault committed = std::move(poisoned).commit(out);
	expect_eq(int(committed.code), int(MeshError::STALE_HANDLE), "merge cannot make a poisoned edit commit");
}

SLAB_TEST(bevel_retires_the_edge_and_cuts_the_corner_off) {
	const Mesh box = unit_box();
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);
	const EdgeId edge = edge_between(box, corners[0], corners[1]);
	expect(box.alive(edge), "the top face has an edge between its first two corners");
	std::vector<FaceId> before;
	box.all_faces(before);

	MeshEdit edit(box);
	expect(ops::bevel(edit, { edge }, 0.25f).ok(), "bevel op");

	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "bevel commit");
	expect(!out.alive(edge), "bevel retires the beveled edge id");
	expect_eq(out.face_count(), 7, "bevel adds one face");
	expect_eq(out.vertex_count(), 10, "bevel splits each endpoint into two");
	expect_eq(out.edge_count(), 15, "bevel edges");
	expect_eq(euler(out), 2, "bevel euler");
	expect(out.signed_volume() > 0.0, "bevel keeps the volume positive");
	expect(out.signed_volume() < 12.0, "bevel takes material off the corner");
	expect_near(out.signed_volume(), 11.9375, 0.0001, "bevel removes a quarter metre wedge two metres long");

	std::vector<FaceId> after;
	out.all_faces(after);
	int fresh = 0;
	for (const FaceId id : after) {
		bool existed = false;
		for (const FaceId old : before) {
			if (old.slot == id.slot && old.gen == id.gen) {
				existed = true;
			}
		}
		if (!existed) {
			fresh++;
		}
	}
	expect_eq(fresh, 1, "bevel leaves exactly one face id that did not exist before");

	FaceId fa;
	FaceId fb;
	box.edge_faces(edge, fa, fb);
	const godot::Vector3 bisector = (box.face_normal(fa) + box.face_normal(fb)).normalized();
	const FaceId chamfer = face_facing(out, bisector);
	expect_near(out.face_normal(chamfer).dot(bisector), 1.0, 0.001, "the chamfer sits between the two original planes");
	expect_near(out.face_area(chamfer), 0.70710678, 0.001, "the chamfer spans a quarter metre on each adjacent face");
	std::vector<VertexId> chamfer_ring;
	out.face_corners(chamfer, chamfer_ring);
	expect_eq(int(chamfer_ring.size()), 4, "the chamfer is a clean quad");
	for (const FaceId id : after) {
		expect(out.face_normal(id).length() > 0.9f, "every face after a bevel reports a usable normal");
	}
}

SLAB_TEST(bevel_clamps_a_large_amount_to_the_shortest_rail) {
	const Mesh box = unit_box();
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);
	const EdgeId edge = edge_between(box, corners[0], corners[1]);

	MeshEdit edit(box);
	expect(ops::bevel(edit, { edge }, 2.0f).ok(), "bevel of an amount past the short rails");
	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "clamped bevel commit");
	expect(!out.alive(edge), "clamped bevel still retires the edge");
	expect_eq(out.face_count(), 7, "clamped bevel still adds one face");
	expect_eq(out.vertex_count(), 10, "clamped bevel still splits both endpoints");
	expect(out.signed_volume() < 12.0, "clamped bevel still takes material off");
	expect(out.signed_volume() > 10.0, "clamped bevel does not eat the whole box");
}

SLAB_TEST(bevel_rejects_what_it_cannot_seat) {
	const Mesh box = unit_box();
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);
	const EdgeId edge = edge_between(box, corners[0], corners[1]);
	const EdgeId stale{ edge.slot, edge.gen + 7 };

	MeshEdit edit(box);
	expect_eq(int(ops::bevel(edit, { stale }, 0.25f).code), int(MeshError::STALE_HANDLE), "bevel stale edge");
	expect_eq(int(ops::bevel(edit, { EdgeId{ 9999, 1 } }, 0.25f).code), int(MeshError::STALE_HANDLE), "bevel edge past the end");
	expect_eq(int(ops::bevel(edit, {}, 0.25f).code), int(MeshError::DEGENERATE_FACE), "bevel of an empty selection");
	expect_eq(int(ops::bevel(edit, { edge }, 0.0f).code), int(MeshError::DEGENERATE_FACE), "bevel by zero");
	expect_eq(int(ops::bevel(edit, { edge }, -1.0f).code), int(MeshError::DEGENERATE_FACE), "bevel by a negative amount");
	expect_eq(int(ops::bevel(edit, { edge, edge }, 0.25f).code), int(MeshError::ADJACENT_SELECTION), "bevel the same edge twice");
	expect_eq(edit.scratch().face_count(), 6, "rejected bevel leaves the mesh alone");
	expect_eq(edit.scratch().vertex_count(), 8, "rejected bevel adds no vertices");
	expect_eq(euler(edit.scratch()), 2, "rejected bevel keeps euler at 2");
}

SLAB_TEST(bevel_two_opposite_edges_of_the_top_face) {
	const Mesh box = unit_box();
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);
	const EdgeId front = edge_between(box, corners[0], corners[1]);
	const EdgeId back = edge_between(box, corners[2], corners[3]);

	MeshEdit edit(box);
	expect(ops::bevel(edit, { front, back }, 0.25f).ok(), "bevel two edges that share no vertex");
	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "two edge bevel commit");
	expect(!out.alive(front), "first beveled edge is retired");
	expect(!out.alive(back), "second beveled edge is retired");
	expect_eq(out.face_count(), 8, "two edge bevel faces");
	expect_eq(out.vertex_count(), 12, "two edge bevel verts");
	expect_eq(euler(out), 2, "two edge bevel euler");
	expect_near(out.signed_volume(), 11.875, 0.0001, "two edge bevel removes two wedges");
}

SLAB_TEST(bridge_only_joins_edges_that_already_share_a_face) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);
	const EdgeId front = edge_between(box, corners[0], corners[1]);
	const EdgeId back = edge_between(box, corners[2], corners[3]);

	MeshEdit joined(box);
	expect(ops::bridge(joined, front, back).ok(), "bridge two edges of one face");
	Mesh out;
	const MeshFault committed = std::move(joined).commit(out);
	expect(committed.ok(), "bridge commit");
	expect_eq(out.face_count(), 7, "bridge adds the connecting face");
	expect_eq(euler(out), 2, "bridge euler");
	expect_near(out.signed_volume(), 12.0, 0.0001, "bridge moves no volume");

	const FaceId under = face_facing(box, godot::Vector3(0, -1, 0));
	std::vector<EdgeId> bottom_edges;
	box.face_edges(under, bottom_edges);
	EdgeId across;
	for (const EdgeId id : bottom_edges) {
		FaceId lhs;
		FaceId rhs;
		box.edge_faces(id, lhs, rhs);
		FaceId a;
		FaceId b;
		box.edge_faces(front, a, b);
		if (lhs.slot != a.slot && lhs.slot != b.slot && rhs.slot != a.slot && rhs.slot != b.slot) {
			across = id;
		}
	}
	expect(box.alive(across), "the box has a bottom edge sharing no face with the top edge");

	MeshEdit apart(box);
	expect_eq(int(ops::bridge(apart, front, across).code), int(MeshError::NO_INTERSECTION), "bridge across a closed solid would pinch it");
	expect_eq(int(ops::bridge(apart, front, front).code), int(MeshError::NO_INTERSECTION), "bridge an edge to itself");
	const EdgeId stale{ front.slot, front.gen + 7 };
	expect_eq(int(ops::bridge(apart, stale, back).code), int(MeshError::STALE_HANDLE), "bridge stale edge");
	expect_eq(apart.scratch().face_count(), 6, "rejected bridge leaves the mesh alone");
}

SLAB_TEST(insert_loop_rings_the_box_with_four_new_edges) {
	const Mesh box = unit_box();
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);
	const EdgeId edge = edge_between(box, corners[0], corners[1]);
	expect(box.alive(edge), "the top face has an edge between its first two corners");

	MeshEdit edit(box);
	expect(ops::insert_loop(edit, edge, 0.5f).ok(), "insert_loop op");

	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "insert_loop commit");
	expect_eq(out.vertex_count(), 12, "insert_loop verts");
	expect_eq(out.edge_count(), 20, "insert_loop edges, twelve original plus four splits plus the four loop edges");
	expect_eq(out.face_count(), 10, "insert_loop faces, the four ring quads each split in two");
	expect_eq(euler(out), 2, "insert_loop euler");
	expect_near(out.signed_volume(), 12.0, 0.0001, "insert_loop moves no volume");

	std::vector<FaceId> faces;
	out.all_faces(faces);
	for (const FaceId id : faces) {
		std::vector<VertexId> ring;
		out.face_corners(id, ring);
		expect_eq(int(ring.size()), 4, "every face after a loop cut is still a quad");
	}
}

SLAB_TEST(insert_loop_clamps_its_parameter) {
	const Mesh box = unit_box();
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);
	const EdgeId edge = edge_between(box, corners[0], corners[1]);

	MeshEdit high(box);
	expect(ops::insert_loop(high, edge, 5.0f).ok(), "insert_loop past one is clamped");
	Mesh out_high;
	expect(std::move(high).commit(out_high).ok(), "clamped high insert_loop commit");
	expect_eq(out_high.face_count(), 10, "clamped high insert_loop faces");
	expect_near(out_high.signed_volume(), 12.0, 0.0001, "clamped high insert_loop volume");

	MeshEdit low(box);
	expect(ops::insert_loop(low, edge, -3.0f).ok(), "insert_loop below zero is clamped");
	Mesh out_low;
	expect(std::move(low).commit(out_low).ok(), "clamped low insert_loop commit");
	expect_eq(euler(out_low), 2, "clamped low insert_loop euler");
	expect_near(out_low.signed_volume(), 12.0, 0.0001, "clamped low insert_loop volume");
}

SLAB_TEST(insert_loop_rejects_a_stale_edge) {
	const Mesh box = unit_box();
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);
	const EdgeId live = edge_between(box, corners[0], corners[1]);
	const EdgeId stale{ live.slot, live.gen + 7 };

	MeshEdit edit(box);
	expect_eq(int(ops::insert_loop(edit, stale, 0.5f).code), int(MeshError::STALE_HANDLE), "insert_loop stale edge");
	expect_eq(int(ops::insert_loop(edit, EdgeId{ 9999, 1 }, 0.5f).code), int(MeshError::STALE_HANDLE), "insert_loop edge past the end");
	expect_eq(edit.scratch().vertex_count(), 8, "rejected insert_loop adds no vertices");
	expect_eq(euler(edit.scratch()), 2, "rejected insert_loop keeps euler at 2");
}

SLAB_TEST(connect_vertices_cuts_the_top_diagonal) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);

	MeshEdit edit(box);
	expect(ops::connect_vertices(edit, corners[0], corners[2]).ok(), "connect_vertices op");
	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "connect_vertices commit");
	expect_eq(out.face_count(), 7, "connect_vertices faces");
	expect_eq(out.vertex_count(), 8, "connect_vertices verts");
	expect_eq(out.edge_count(), 13, "connect_vertices edges");
	expect_eq(euler(out), 2, "connect_vertices euler");
	expect_near(out.signed_volume(), 12.0, 0.0001, "connect_vertices moves no volume");
	expect(out.alive(top), "connect_vertices keeps the cut face id");
}

SLAB_TEST(connect_vertices_rejects_what_it_cannot_cut) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);
	const VertexId stale{ corners[0].slot, corners[0].gen + 7 };

	MeshEdit edit(box);
	expect_eq(int(ops::connect_vertices(edit, stale, corners[2]).code), int(MeshError::STALE_HANDLE), "connect_vertices stale vertex");
	expect_eq(int(ops::connect_vertices(edit, corners[0], corners[0]).code), int(MeshError::INVALID_SELECTION), "connect_vertices onto itself");
	expect_eq(int(ops::connect_vertices(edit, corners[0], corners[1]).code), int(MeshError::ADJACENT_SELECTION), "connect_vertices along an existing edge");

	const VertexId across = far_corner(box, corners[0]);
	expect(box.alive(across), "the box has a corner diagonally across the solid");
	expect_eq(int(ops::connect_vertices(edit, corners[0], across).code), int(MeshError::INVALID_SELECTION), "connect_vertices with no common face");
	expect_eq(edit.scratch().face_count(), 6, "rejected connect_vertices leaves the mesh alone");
}

SLAB_TEST(connect_edges_cuts_between_the_nearest_cuttable_corners) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);
	const EdgeId front = edge_between(box, corners[0], corners[1]);
	const EdgeId back = edge_between(box, corners[2], corners[3]);
	expect(box.alive(front), "top face front edge");
	expect(box.alive(back), "top face back edge");

	MeshEdit edit(box);
	expect(ops::connect_edges(edit, front, back).ok(), "connect_edges op");
	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "connect_edges commit");
	expect_eq(out.face_count(), 7, "connect_edges faces");
	expect_eq(euler(out), 2, "connect_edges euler");
	expect_near(out.signed_volume(), 12.0, 0.0001, "connect_edges moves no volume");

	MeshEdit same(box);
	expect_eq(int(ops::connect_edges(same, front, front).code), int(MeshError::ADJACENT_SELECTION), "connect_edges an edge to itself");
	const EdgeId stale{ front.slot, front.gen + 7 };
	expect_eq(int(ops::connect_edges(same, stale, back).code), int(MeshError::STALE_HANDLE), "connect_edges stale edge");

	MeshEdit corner(box);
	expect(ops::connect_edges(corner, front, edge_between(box, corners[1], corners[2])).ok(), "connect_edges two edges sharing a corner cuts across their far ends");
	Mesh cut_corner;
	expect(std::move(corner).commit(cut_corner).ok(), "shared corner connect_edges commit");
	expect_eq(cut_corner.face_count(), 7, "shared corner connect_edges faces");
	expect_eq(euler(cut_corner), 2, "shared corner connect_edges euler");
}

SLAB_TEST(weld_merges_two_neighbours_and_leaves_distant_pairs_alone) {
	const Mesh box = unit_box();
	std::vector<VertexId> all;
	box.all_vertices(all);
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);

	MeshEdit apart(box);
	expect(ops::weld(apart, all, 0.5f).ok(), "weld finds no pair inside half a metre");
	Mesh untouched;
	expect(std::move(apart).commit(untouched).ok(), "no op weld commit");
	expect_eq(untouched.vertex_count(), 8, "no op weld verts");
	expect_near(untouched.signed_volume(), 12.0, 0.0001, "no op weld moves no volume");

	MeshEdit joined(box);
	expect(ops::weld(joined, { corners[0], corners[1] }, 2.5f).ok(), "weld two corners two metres apart");
	Mesh out;
	const MeshFault committed = std::move(joined).commit(out);
	expect(committed.ok(), "weld commit");
	expect_eq(out.vertex_count(), 7, "weld retires one of the pair");
	expect_eq(out.face_count(), 6, "weld keeps the face count");
	expect_eq(out.edge_count(), 11, "weld retires one edge");
	expect_eq(euler(out), 2, "weld euler");
	expect(out.signed_volume() > 0.0, "weld keeps the volume positive");
	expect(out.signed_volume() < 12.0, "weld pulls a corner in");
	expect(!out.alive(corners[0]) || !out.alive(corners[1]), "one of the welded pair is dead");
}

SLAB_TEST(weld_refuses_a_pair_that_shares_no_edge) {
	const Mesh box = unit_box();
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);

	MeshEdit edit(box);
	const MeshFault faulted = ops::weld(edit, { corners[0], corners[2] }, 3.0f);
	expect_eq(int(faulted.code), int(MeshError::SNAP_COLLAPSED_TOPOLOGY), "weld across a face diagonal would pinch the surface");
	expect_eq(edit.scratch().vertex_count(), 8, "refused weld removes nothing");
	expect_eq(euler(edit.scratch()), 2, "refused weld keeps euler at 2");
}

SLAB_TEST(collapse_retires_a_corner_along_its_shortest_edge) {
	const Mesh box = unit_box();
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);

	MeshEdit edit(box);
	expect(ops::collapse(edit, { corners[0] }).ok(), "collapse op");
	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "collapse commit");
	expect_eq(out.vertex_count(), 7, "collapse retires one vertex");
	expect_eq(out.face_count(), 6, "collapse keeps the face count");
	expect_eq(out.edge_count(), 11, "collapse retires one edge");
	expect_eq(euler(out), 2, "collapse euler");
	expect(out.signed_volume() > 0.0, "collapse keeps the volume positive");
	expect(out.signed_volume() < 12.0, "collapse pulls the corner onto its neighbour");
}

SLAB_TEST(vertex_ops_reject_stale_and_empty_selections) {
	const Mesh box = unit_box();
	std::vector<VertexId> all;
	box.all_vertices(all);
	const VertexId stale{ all[0].slot, all[0].gen + 7 };

	MeshEdit edit(box);
	expect(ops::weld(edit, {}, 1.0f).ok(), "weld of an empty selection");
	expect(ops::collapse(edit, {}).ok(), "collapse of an empty selection");
	expect_eq(int(ops::weld(edit, { stale }, 0.1f).code), int(MeshError::STALE_HANDLE), "weld stale vertex");
	expect_eq(int(ops::collapse(edit, { stale }).code), int(MeshError::STALE_HANDLE), "collapse stale vertex");
	expect_eq(int(ops::weld(edit, { VertexId{ 9999, 1 } }, 0.1f).code), int(MeshError::STALE_HANDLE), "weld vertex past the end");
	expect_eq(int(ops::weld(edit, all, -1.0f).code), int(MeshError::COORD_OUT_OF_RANGE), "weld with a negative radius");
	expect_eq(edit.scratch().vertex_count(), 8, "refused vertex ops remove nothing");

	Mesh out;
	expect(std::move(edit).commit(out).ok(), "empty vertex op commit");
	expect_eq(out.vertex_count(), 8, "empty vertex op verts");
	expect_near(out.signed_volume(), 12.0, 0.0001, "empty vertex op volume");
}

SLAB_TEST(delete_faces_leaves_a_hole_that_cannot_commit) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);

	MeshEdit edit(box);
	expect(ops::delete_faces(edit, { top }).ok(), "delete_faces op");
	expect(!edit.scratch().alive(top), "deleted face id is dead");
	expect_eq(edit.scratch().face_count(), 5, "delete_faces faces");

	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(!committed.ok(), "an unclosed hole must not commit");
	expect_eq(int(committed.code), int(MeshError::NOT_CLOSED), "delete_faces commit code");
}

SLAB_TEST(delete_faces_of_nothing_is_a_no_op) {
	const Mesh box = unit_box();
	MeshEdit edit(box);
	expect(ops::delete_faces(edit, {}).ok(), "delete_faces of an empty selection");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "empty delete_faces commit");
	expect_eq(out.face_count(), 6, "empty delete_faces faces");
	expect_near(out.signed_volume(), 12.0, 0.0001, "empty delete_faces volume");

	MeshEdit stale(box);
	const FaceId absent{ 9999, 1 };
	expect_eq(int(ops::delete_faces(stale, { absent }).code), int(MeshError::STALE_HANDLE), "delete_faces stale face");
	expect_eq(stale.scratch().face_count(), 6, "rejected delete_faces removes nothing");
}

SLAB_TEST(flip_faces_of_every_face_inverts_the_volume) {
	const Mesh box = unit_box();
	std::vector<FaceId> all;
	box.all_faces(all);

	MeshEdit edit(box);
	expect(ops::flip_faces(edit, all).ok(), "flip_faces op");
	expect(edit.scratch().signed_volume() < 0.0, "flipping every face turns the solid inside out");
	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(!committed.ok(), "an inside out solid must not commit");
	expect_eq(int(committed.code), int(MeshError::INVERTED_VOLUME), "flip_faces commit code");
}

SLAB_TEST(flip_faces_of_one_face_disagrees_with_its_neighbours) {
	const Mesh box = unit_box();
	MeshEdit edit(box);
	expect(ops::flip_faces(edit, { top_face(box) }).ok(), "flip_faces of a subset is legal");
	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(!committed.ok(), "one flipped face must not commit");
	expect_eq(int(committed.code), int(MeshError::INCONSISTENT_ORIENTATION), "one flipped face commit code");

	MeshEdit empty(box);
	expect(ops::flip_faces(empty, {}).ok(), "flip_faces of an empty selection");
	Mesh unchanged;
	expect(std::move(empty).commit(unchanged).ok(), "empty flip_faces commit");
	expect_near(unchanged.signed_volume(), 12.0, 0.0001, "empty flip_faces volume");
}
