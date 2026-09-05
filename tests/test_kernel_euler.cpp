#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/primitives.hpp"

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

static FaceId top_face(const Mesh &p_mesh) {
	FaceId best;
	float up = -2.0f;
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	for (const FaceId id : faces) {
		const float y = p_mesh.face_normal(id).y;
		if (y > up) {
			up = y;
			best = id;
		}
	}
	return best;
}

static int euler(const Mesh &p_mesh) {
	return p_mesh.vertex_count() - p_mesh.edge_count() + p_mesh.face_count();
}

static IVec3 midpoint(const IVec3 &p_a, const IVec3 &p_b) {
	return IVec3{ (p_a.x + p_b.x) / 2, (p_a.y + p_b.y) / 2, (p_a.z + p_b.z) / 2 };
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

static VertexId split_at_midpoint(MeshEdit &p_edit, VertexId p_a, VertexId p_b) {
	const EdgeId edge = edge_between(p_edit.scratch(), p_a, p_b);
	const IVec3 mid = midpoint(p_edit.scratch().position_i(p_a), p_edit.scratch().position_i(p_b));
	return p_edit.split_edge(edge, mid);
}

SLAB_TEST(split_edge_adds_a_corner_to_both_faces) {
	const Mesh box = unit_box();
	std::vector<FaceId> before;
	box.all_faces(before);

	MeshEdit edit(box);
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);
	expect(box.alive(edge_between(box, corners[0], corners[1])), "top face has an edge between its first two corners");

	const VertexId split = split_at_midpoint(edit, corners[0], corners[1]);
	expect(edit.last_fault().ok(), "split_edge fault");
	expect(edit.scratch().alive(split), "split_edge returns a live vertex");

	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "split_edge commit");
	expect_eq(out.vertex_count(), 9, "split_edge verts");
	expect_eq(out.edge_count(), 13, "split_edge edges");
	expect_eq(out.face_count(), 6, "split_edge faces");
	expect_eq(euler(out), 2, "split_edge euler");
	expect_near(out.signed_volume(), 12.0, 0.0001, "split_edge volume unchanged");
	for (const FaceId id : before) {
		expect(out.alive(id), "split_edge keeps every original face alive");
	}
	std::vector<VertexId> after_corners;
	out.face_corners(top_face(out), after_corners);
	expect_eq(int(after_corners.size()), 5, "split face gains one corner");
}

static FaceId only_new_face(const std::vector<FaceId> &p_before, const Mesh &p_after) {
	std::vector<FaceId> faces;
	p_after.all_faces(faces);
	for (const FaceId id : faces) {
		bool seen = false;
		for (const FaceId old : p_before) {
			if (old.slot == id.slot && old.gen == id.gen) {
				seen = true;
			}
		}
		if (!seen) {
			return id;
		}
	}
	return FaceId{};
}

SLAB_TEST(split_face_cuts_the_top_in_two) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<FaceId> before;
	box.all_faces(before);

	MeshEdit edit(box);
	FaceAttrs attrs;
	attrs.uv_scale = godot::Vector2(2, 4);
	attrs.uv_offset = godot::Vector2(0.25f, 0.5f);
	attrs.material_slot = 3;
	edit.set_attrs(top, attrs);

	std::vector<VertexId> corners;
	box.face_corners(top, corners);
	const EdgeId cut = edit.split_face(top, corners[0], corners[2]);
	expect(edit.last_fault().ok(), "split_face fault");
	expect(edit.scratch().alive(cut), "split_face returns a live edge");

	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "split_face commit");
	expect_eq(out.vertex_count(), 8, "split_face verts");
	expect_eq(out.edge_count(), 13, "split_face edges");
	expect_eq(out.face_count(), 7, "split_face faces");
	expect_eq(euler(out), 2, "split_face euler");
	expect_near(out.signed_volume(), 12.0, 0.0001, "split_face volume unchanged");
	expect(out.alive(top), "split_face keeps the original face id");

	const FaceId made = only_new_face(before, out);
	expect(out.alive(made), "split_face produces one new face");
	expect_near(out.attrs(made).uv_scale.x, 2.0, 0.0001, "new half copies uv scale x");
	expect_near(out.attrs(made).uv_scale.y, 4.0, 0.0001, "new half copies uv scale y");
	expect_near(out.attrs(made).uv_offset.x, 0.25, 0.0001, "new half copies uv offset x");
	expect_eq(out.attrs(made).material_slot, 3, "new half copies material slot");

	std::vector<VertexId> kept_corners;
	out.face_corners(top, kept_corners);
	expect_eq(int(kept_corners.size()), 3, "kept half is a triangle");
	std::vector<VertexId> made_corners;
	out.face_corners(made, made_corners);
	expect_eq(int(made_corners.size()), 3, "new half is a triangle");
}

SLAB_TEST(remove_face_opens_a_hole_that_cannot_commit) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);

	MeshEdit edit(box);
	expect(edit.remove_face(top).ok(), "remove_face fault");
	expect(!edit.scratch().alive(top), "removed face id is dead");
	expect_eq(edit.scratch().face_count(), 5, "remove_face faces");
	expect_eq(edit.scratch().edge_count(), 12, "remove_face keeps the boundary edges");
	expect_eq(edit.scratch().vertex_count(), 8, "remove_face keeps every vertex");
	expect_eq(euler(edit.scratch()), 1, "open box euler drops to 1");

	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(!committed.ok(), "a hole must not commit");
	expect_eq(int(committed.code), int(MeshError::NOT_CLOSED), "remove_face commit code");
}

SLAB_TEST(dissolve_edge_undoes_a_split_face) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);

	MeshEdit edit(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);
	const EdgeId cut = edit.split_face(top, corners[0], corners[2]);
	expect(edit.last_fault().ok(), "split_face before dissolve");
	expect_eq(edit.scratch().face_count(), 7, "split_face faces before dissolve");

	expect(edit.dissolve_edge(cut).ok(), "dissolve_edge fault");
	expect(!edit.scratch().alive(cut), "dissolved edge id is dead");

	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(committed.ok(), "dissolve_edge commit");
	expect_eq(out.vertex_count(), 8, "dissolve_edge verts");
	expect_eq(out.edge_count(), 12, "dissolve_edge edges");
	expect_eq(out.face_count(), 6, "dissolve_edge faces");
	expect_eq(euler(out), 2, "dissolve_edge euler");
	expect_near(out.signed_volume(), 12.0, 0.0001, "dissolve_edge volume unchanged");
	std::vector<VertexId> merged;
	out.face_corners(top_face(out), merged);
	expect_eq(int(merged.size()), 4, "merged face is a quad again");
}

SLAB_TEST(dissolve_edge_rejects_a_folded_merge) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);

	MeshEdit edit(box);
	edit.dissolve_edge(edge_between(box, corners[0], corners[1]));
	expect_eq(int(edit.last_fault().code), int(MeshError::DEGENERATE_FACE), "dissolve across a box corner");
	expect_eq(edit.scratch().face_count(), 6, "rejected dissolve_edge leaves the mesh alone");
}

SLAB_TEST(dissolve_edge_rejects_a_dangling_vertex) {
	const Mesh box = unit_box();
	std::vector<VertexId> corners;
	box.face_corners(top_face(box), corners);

	MeshEdit edit(box);
	const VertexId split = split_at_midpoint(edit, corners[0], corners[1]);
	expect(edit.last_fault().ok(), "split_edge before dissolve");

	const EdgeId half = edge_between(edit.scratch(), corners[0], split);
	expect(edit.scratch().alive(half), "split leaves an edge to the new vertex");
	edit.dissolve_edge(half);
	expect_eq(int(edit.last_fault().code), int(MeshError::NON_MANIFOLD_VERTEX), "dissolve stranding a valence two vertex");
	expect_eq(edit.scratch().vertex_count(), 9, "rejected dissolve_edge keeps the split vertex");
}

SLAB_TEST(two_splits_cut_a_loop_across_the_top) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);

	MeshEdit edit(box);
	const VertexId near_split = split_at_midpoint(edit, corners[0], corners[1]);
	const VertexId far_split = split_at_midpoint(edit, corners[2], corners[3]);
	expect(edit.last_fault().ok(), "loop cut split_edge fault");
	edit.split_face(top, near_split, far_split);
	expect(edit.last_fault().ok(), "loop cut split_face fault");

	Mesh out;
	expect(std::move(edit).commit(out).ok(), "loop cut commit");
	expect_eq(out.vertex_count(), 10, "loop cut verts");
	expect_eq(out.edge_count(), 15, "loop cut edges");
	expect_eq(out.face_count(), 7, "loop cut faces");
	expect_eq(euler(out), 2, "loop cut euler");
	expect_near(out.signed_volume(), 12.0, 0.0001, "loop cut volume unchanged");
	std::vector<VertexId> half;
	out.face_corners(top, half);
	expect_eq(int(half.size()), 4, "loop cut leaves a quad on the kept id");
}

SLAB_TEST(flip_all_turns_the_box_inside_out) {
	const Mesh box = unit_box();

	MeshEdit inside_out(box);
	expect(inside_out.flip_all().ok(), "flip_all fault");
	expect(inside_out.scratch().signed_volume() < 0.0, "flip_all makes signed volume negative");
	expect_eq(euler(inside_out.scratch()), 2, "flip_all euler");
	Mesh rejected;
	const MeshFault committed = std::move(inside_out).commit(rejected);
	expect(!committed.ok(), "an inside out solid must not commit");
	expect_eq(int(committed.code), int(MeshError::INVERTED_VOLUME), "flip_all commit code");

	MeshEdit twice(box);
	expect(twice.flip_all().ok(), "first flip_all fault");
	expect(twice.flip_all().ok(), "second flip_all fault");
	Mesh out;
	expect(std::move(twice).commit(out).ok(), "flipping twice commits again");
	expect_eq(out.face_count(), 6, "flip twice faces");
	expect_eq(out.vertex_count(), 8, "flip twice verts");
	expect_eq(out.edge_count(), 12, "flip twice edges");
	expect_eq(euler(out), 2, "flip twice euler");
	expect_near(out.signed_volume(), 12.0, 0.0001, "flip twice volume");
}

SLAB_TEST(flip_face_alone_disagrees_with_its_neighbours) {
	const Mesh box = unit_box();
	MeshEdit edit(box);
	expect(edit.flip_face(top_face(box)).ok(), "flip_face fault");
	expect_eq(euler(edit.scratch()), 2, "flip_face euler");
	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(!committed.ok(), "one flipped face must not commit");
	expect_eq(int(committed.code), int(MeshError::INCONSISTENT_ORIENTATION), "flip_face commit code");
}

SLAB_TEST(stale_handles_are_rejected_by_every_primitive) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);

	MeshEdit edit(box);
	const EdgeId live_edge = edge_between(box, corners[0], corners[1]);
	const EdgeId stale_edge{ live_edge.slot, live_edge.gen + 7 };
	const FaceId stale_face{ top.slot, top.gen + 7 };
	const VertexId stale_vertex{ corners[0].slot, corners[0].gen + 7 };
	const EdgeId absent_edge{ 9999, 1 };
	const FaceId absent_face{ 9999, 1 };

	edit.split_edge(stale_edge, IVec3{ 1, 1, 1 });
	expect_eq(int(edit.last_fault().code), int(MeshError::STALE_HANDLE), "split_edge stale edge");
	edit.split_edge(absent_edge, IVec3{ 1, 1, 1 });
	expect_eq(int(edit.last_fault().code), int(MeshError::STALE_HANDLE), "split_edge edge past the end");

	edit.split_face(stale_face, corners[0], corners[2]);
	expect_eq(int(edit.last_fault().code), int(MeshError::STALE_HANDLE), "split_face stale face");
	edit.split_face(top, stale_vertex, corners[2]);
	expect_eq(int(edit.last_fault().code), int(MeshError::STALE_HANDLE), "split_face stale vertex");
	edit.split_face(absent_face, corners[0], corners[2]);
	expect_eq(int(edit.last_fault().code), int(MeshError::STALE_HANDLE), "split_face face past the end");

	edit.remove_face(stale_face);
	expect_eq(int(edit.last_fault().code), int(MeshError::STALE_HANDLE), "remove_face stale face");

	edit.dissolve_edge(stale_edge);
	expect_eq(int(edit.last_fault().code), int(MeshError::STALE_HANDLE), "dissolve_edge stale edge");

	edit.flip_face(stale_face);
	expect_eq(int(edit.last_fault().code), int(MeshError::STALE_HANDLE), "flip_face stale face");

	expect_eq(edit.scratch().face_count(), 6, "stale handles change nothing");
	expect_eq(edit.scratch().vertex_count(), 8, "stale handles add no vertices");
	expect_eq(edit.scratch().edge_count(), 12, "stale handles add no edges");
	expect_eq(euler(edit.scratch()), 2, "stale handles keep euler at 2");
}

SLAB_TEST(dead_handles_from_earlier_ops_stay_dead) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);

	MeshEdit edit(box);
	const EdgeId cut = edit.split_face(top, corners[0], corners[2]);
	expect(edit.dissolve_edge(cut).ok(), "dissolve before reuse");

	edit.dissolve_edge(cut);
	expect_eq(int(edit.last_fault().code), int(MeshError::STALE_HANDLE), "dissolving a dead edge twice");
	edit.split_edge(cut, IVec3{ 1, 1, 1 });
	expect_eq(int(edit.last_fault().code), int(MeshError::STALE_HANDLE), "splitting a dead edge");

	expect_eq(edit.scratch().face_count(), 6, "rejected reuse leaves the merge intact");
	expect_eq(euler(edit.scratch()), 2, "rejected reuse euler");
	Mesh out;
	const MeshFault committed = std::move(edit).commit(out);
	expect(!committed.ok(), "a recorded fault blocks commit");
	expect_eq(int(committed.code), int(MeshError::STALE_HANDLE), "commit reports the recorded fault");
}

SLAB_TEST(split_face_rejects_impossible_cuts) {
	const Mesh box = unit_box();
	const FaceId top = top_face(box);
	std::vector<VertexId> corners;
	box.face_corners(top, corners);

	MeshEdit edit(box);
	edit.split_face(top, corners[0], corners[0]);
	expect_eq(int(edit.last_fault().code), int(MeshError::INVALID_SELECTION), "split_face on one vertex twice");

	edit.split_face(top, corners[0], corners[1]);
	expect_eq(int(edit.last_fault().code), int(MeshError::ADJACENT_SELECTION), "split_face along a loop edge");

	edit.split_face(top, corners[3], corners[0]);
	expect_eq(int(edit.last_fault().code), int(MeshError::ADJACENT_SELECTION), "split_face across the loop seam");

	std::vector<VertexId> all;
	box.all_vertices(all);
	VertexId off_face;
	for (const VertexId v : all) {
		bool on_top = false;
		for (const VertexId c : corners) {
			if (c.slot == v.slot) {
				on_top = true;
			}
		}
		if (!on_top) {
			off_face = v;
		}
	}
	edit.split_face(top, corners[0], off_face);
	expect_eq(int(edit.last_fault().code), int(MeshError::INVALID_SELECTION), "split_face to a vertex off the face");
	expect_eq(edit.scratch().face_count(), 6, "rejected split_face leaves the mesh alone");
}
