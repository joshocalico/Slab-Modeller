#include "kernel/mesh_edit.hpp"
#include "kernel/ops/primitives.hpp"
#include "harness.hpp"

using namespace slab;
using namespace slabtest;

static Mesh diagnostic_box() {
	MeshEdit edit = MeshEdit::empty();
	ops::box(edit, godot::Vector3(2, 2, 2));
	Mesh out;
	std::move(edit).commit(out);
	return out;
}

SLAB_TEST(diagnostic_extracts_typed_mesh_locations) {
	const Mesh box = diagnostic_box();
	std::vector<std::pair<IVec3, IVec3>> lines;
	std::vector<FaceId> faces;
	std::vector<EdgeId> edges;
	std::vector<VertexId> vertices;
	box.all_faces(faces);
	box.all_edges(edges);
	box.all_vertices(vertices);

	diagnostic_segments(box, { MeshError::DEGENERATE_FACE, faces[0].slot, FaultElement::FACE }, lines);
	expect_eq(int(lines.size()), 4, "quad face fault outlines its boundary");

	diagnostic_segments(box, { MeshError::TWIN_MISMATCH, edges[0].slot, FaultElement::HALF_EDGE }, lines);
	expect_eq(int(lines.size()), 1, "half-edge fault identifies one edge segment");

	diagnostic_segments(box, { MeshError::NON_MANIFOLD_VERTEX, vertices[0].slot, FaultElement::VERTEX }, lines);
	expect_eq(int(lines.size()), 3, "vertex fault identifies its incident edge star");
}

SLAB_TEST(diagnostic_never_guesses_an_untyped_or_stale_location) {
	const Mesh box = diagnostic_box();
	std::vector<std::pair<IVec3, IVec3>> lines;
	diagnostic_segments(box, { MeshError::INVALID_SELECTION, 0, FaultElement::NONE }, lines);
	expect(lines.empty(), "untyped slot is not attributed to an arbitrary element");
	diagnostic_segments(box, { MeshError::INVALID_SELECTION, INVALID_IDX, FaultElement::FACE }, lines);
	expect(lines.empty(), "invalid typed slot has no geometry");
}

SLAB_TEST(diagnostic_includes_related_face) {
	const Mesh box = diagnostic_box();
	std::vector<FaceId> faces;
	box.all_faces(faces);
	std::vector<std::pair<IVec3, IVec3>> lines;
	diagnostic_segments(box,
			{ MeshError::SELF_INTERSECTION, faces[0].slot, FaultElement::FACE, faces[1].slot }, lines);
	expect_eq(int(lines.size()), 8, "primary and related face boundaries are both extracted");
}
