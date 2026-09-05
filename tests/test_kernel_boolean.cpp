#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/boolean.hpp"
#include "kernel/ops/edit.hpp"
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

static int euler(const Mesh &p_mesh) {
	return p_mesh.vertex_count() - p_mesh.edge_count() + p_mesh.face_count();
}

SLAB_TEST(boolean_subtract_of_an_inner_box_is_a_watertight_cavity) {
	const Mesh outer = unit_box();

	MeshEdit inner_edit = MeshEdit::empty();
	expect(ops::box(inner_edit, godot::Vector3(0.4f, 0.4f, 0.4f)).ok(), "inner box op");
	Mesh inner;
	expect(std::move(inner_edit).commit(inner).ok(), "inner box commit");

	std::vector<VertexId> verts;
	inner.all_vertices(verts);
	MeshEdit shifted(inner);
	expect(ops::move_vertices(shifted, verts, godot::Vector3(0.8f, 1.3f, 0.8f)).ok(), "shift inner box inside the outer");
	expect(std::move(shifted).commit(inner).ok(), "shifted inner commit");

	MeshEdit cut(outer);
	expect(ops::boolean(cut, inner, 1).ok(), "subtract op");
	Mesh out;
	const MeshFault committed = std::move(cut).commit(out);
	expect(committed.ok(), "subtract commit");
	expect_eq(out.face_count(), 12, "cavity has two shells of six faces");
	expect_eq(out.vertex_count(), 16, "cavity verts");
	expect(out.signed_volume() > 0.0, "cavity volume stays positive");
	expect_near(out.signed_volume(), 12.0 - 0.064, 0.001, "cavity volume is outer minus inner");
	expect(validate(out).ok(), "cavity is watertight");
}

SLAB_TEST(boolean_union_of_disjoint_boxes_concatenates) {
	const Mesh a = unit_box();
	MeshEdit b_edit = MeshEdit::empty();
	expect(ops::box(b_edit, godot::Vector3(1, 1, 1)).ok(), "second box");
	Mesh b;
	expect(std::move(b_edit).commit(b).ok(), "second box commit");
	std::vector<VertexId> verts;
	b.all_vertices(verts);
	MeshEdit shifted(b);
	expect(ops::move_vertices(shifted, verts, godot::Vector3(4, 0, 0)).ok(), "shift second box away");
	expect(std::move(shifted).commit(b).ok(), "shifted second commit");

	MeshEdit joined(a);
	expect(ops::boolean(joined, b, 0).ok(), "union op");
	Mesh out;
	expect(std::move(joined).commit(out).ok(), "union commit");
	expect_eq(out.face_count(), 12, "disjoint union faces");
	expect_eq(out.vertex_count(), 16, "disjoint union verts");
	expect_near(out.signed_volume(), 13.0, 0.01, "disjoint union volume");
	expect_eq(euler(out), 4, "two shells have euler 4");
}

SLAB_TEST(boolean_overlapping_boxes_are_refused) {
	const Mesh a = unit_box();
	MeshEdit b_edit = MeshEdit::empty();
	ops::box(b_edit, godot::Vector3(2, 3, 2));
	Mesh b;
	std::move(b_edit).commit(b);
	std::vector<VertexId> verts;
	b.all_vertices(verts);
	MeshEdit shifted(b);
	ops::move_vertices(shifted, verts, godot::Vector3(1, 0, 0));
	std::move(shifted).commit(b);

	MeshEdit cut(a);
	expect_eq(int(ops::boolean(cut, b, 1).code), int(MeshError::NO_INTERSECTION), "overlapping subtract is not a cavity");
	expect_eq(cut.scratch().face_count(), 6, "refused boolean leaves A alone");
}

SLAB_TEST(mirror_x_keeps_volume_and_euler) {
	const Mesh box = unit_box();
	MeshEdit edit(box);
	expect(ops::mirror(edit, godot::Vector3(-1, 1, 1)).ok(), "mirror op");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "mirror commit");
	expect_eq(out.face_count(), 6, "mirror faces");
	expect_eq(euler(out), 2, "mirror euler");
	expect_near(out.signed_volume(), 12.0, 0.0001, "mirror volume");
}

SLAB_TEST(center_pivot_puts_the_aabb_on_the_origin) {
	const Mesh box = unit_box();
	MeshEdit edit(box);
	expect(ops::center_pivot(edit).ok(), "center_pivot op");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "center_pivot commit");
	const godot::Vector3 c = out.local_aabb().position + out.local_aabb().size * 0.5f;
	expect_near(c.x, 0.0, 0.001, "centered x");
	expect_near(c.y, 0.0, 0.001, "centered y");
	expect_near(c.z, 0.0, 0.001, "centered z");
	expect_near(out.signed_volume(), 12.0, 0.0001, "center_pivot volume");
}
