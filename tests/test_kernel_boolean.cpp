#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/boolean.hpp"
#include "kernel/ops/edit.hpp"
#include "kernel/ops/inset.hpp"
#include "kernel/ops/offset_loop.hpp"
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

static Mesh shifted_arch(float p_span, float p_depth, int p_segments, float p_thickness, double p_arc, const godot::Vector3 &p_delta) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::arch(edit, p_span, p_depth, p_segments, p_thickness, p_arc).ok(), "arch builds");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "arch commit");
	std::vector<VertexId> verts;
	mesh.all_vertices(verts);
	MeshEdit moved(mesh);
	expect(ops::move_vertices(moved, verts, p_delta).ok(), "shift arch");
	expect(std::move(moved).commit(mesh).ok(), "shifted arch commit");
	return mesh;
}

SLAB_TEST(boolean_union_of_overlapping_boxes_is_a_watertight_solid) {
	const Mesh a = unit_box();
	MeshEdit b_edit = MeshEdit::empty();
	expect(ops::box(b_edit, godot::Vector3(2, 3, 2)).ok(), "second box");
	Mesh b;
	expect(std::move(b_edit).commit(b).ok(), "second box commit");
	std::vector<VertexId> verts;
	b.all_vertices(verts);
	MeshEdit shifted(b);
	expect(ops::move_vertices(shifted, verts, godot::Vector3(1, 0, 0)).ok(), "overlap the boxes by 1 m");
	expect(std::move(shifted).commit(b).ok(), "shifted overlap");

	MeshEdit joined(a);
	const MeshFault fault = ops::boolean(joined, b, 0);
	expect_eq(int(fault.code), int(MeshError::OK), "overlapping union op");
	Mesh out;
	expect(std::move(joined).commit(out).ok(), "overlapping union commit");
	expect(validate(out).ok(), "overlapping union is watertight");
	expect(out.signed_volume() > 12.0, "union is larger than one box");
	expect(out.signed_volume() < 24.0, "union is smaller than two boxes");
}

SLAB_TEST(boolean_union_of_an_arch_on_a_box_is_a_watertight_house) {
	MeshEdit body_edit = MeshEdit::empty();
	expect(ops::box(body_edit, godot::Vector3(4, 2.2f, 4)).ok(), "house body");
	Mesh body;
	expect(std::move(body_edit).commit(body).ok(), "house body commit");
	const Mesh roof = shifted_arch(4.0f, 4.0f, 12, 0.4f, Math_PI, godot::Vector3(0, 2.05f, 0));

	MeshEdit joined(body);
	const MeshFault fault = ops::boolean(joined, roof, 0);
	expect_eq(int(fault.code), int(MeshError::OK), "house union op");
	Mesh out;
	const MeshFault committed = std::move(joined).commit(out);
	expect(committed.ok(), "house union commit");
	expect(validate(out).ok(), "house is watertight");
	expect(out.signed_volume() > body.signed_volume(), "the roof adds volume");
	expect(out.face_count() > 6, "the vault adds faces");

	MeshEdit door_edit = MeshEdit::empty();
	expect(ops::box(door_edit, godot::Vector3(0.9f, 1.6f, 1.2f)).ok(), "door cutter");
	Mesh door;
	expect(std::move(door_edit).commit(door).ok(), "door commit");
	std::vector<VertexId> door_verts;
	door.all_vertices(door_verts);
	MeshEdit shifted_door(door);
	expect(ops::move_vertices(shifted_door, door_verts, godot::Vector3(1.55f, 0.0f, -0.2f)).ok(), "shift door through the front wall");
	expect(std::move(shifted_door).commit(door).ok(), "shifted door");
	const double before_door = out.signed_volume();
	MeshEdit cut(out);
	expect(ops::boolean(cut, door, 1).ok(), "house door subtract");
	expect(std::move(cut).commit(out).ok(), "house door commit");
	expect(validate(out).ok(), "house with a door is watertight");
	expect(out.signed_volume() > 0.0, "house with a door still has volume");
	expect(out.signed_volume() < before_door, "the door removes volume");
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

SLAB_TEST(boolean_subtract_of_overlapping_boxes_cuts_a_notch) {
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
	expect(ops::boolean(cut, b, 1).ok(), "overlapping subtract");
	Mesh out;
	expect(std::move(cut).commit(out).ok(), "overlapping subtract commit");
	expect(validate(out).ok(), "notch is watertight");
	expect(out.signed_volume() > 0.0, "notch volume stays positive");
	expect_near(out.signed_volume(), 6.0, 0.05, "half the host remains");
}

SLAB_TEST(boolean_subtract_through_a_box_is_a_door) {
	MeshEdit host_edit = MeshEdit::empty();
	ops::box(host_edit, godot::Vector3(2, 2, 2));
	Mesh host;
	expect(std::move(host_edit).commit(host).ok(), "host box");

	MeshEdit door_edit = MeshEdit::empty();
	ops::box(door_edit, godot::Vector3(0.8f, 1.2f, 2.4f));
	Mesh door;
	expect(std::move(door_edit).commit(door).ok(), "door box");
	std::vector<VertexId> verts;
	door.all_vertices(verts);
	MeshEdit shifted(door);
	expect(ops::move_vertices(shifted, verts, godot::Vector3(0.6f, 0.4f, -0.2f)).ok(), "shift door through Z");
	expect(std::move(shifted).commit(door).ok(), "shifted door");

	MeshEdit cut(host);
	expect(ops::boolean(cut, door, 1).ok(), "through subtract");
	Mesh out;
	expect(std::move(cut).commit(out).ok(), "door commit");
	expect(validate(out).ok(), "door is watertight");
	expect(out.signed_volume() > 0.0, "door volume stays positive");
	expect(out.signed_volume() < host.signed_volume() - 0.5, "door removes volume");
	expect(out.face_count() > 6, "door adds tunnel faces");
}

SLAB_TEST(boolean_subtract_through_a_thin_wall_is_a_doorway) {
	MeshEdit wall_edit = MeshEdit::empty();
	ops::box(wall_edit, godot::Vector3(4, 3, 0.4f));
	Mesh wall;
	expect(std::move(wall_edit).commit(wall).ok(), "wall box");

	MeshEdit door_edit = MeshEdit::empty();
	ops::box(door_edit, godot::Vector3(1.2f, 2.0f, 0.8f));
	Mesh door;
	expect(std::move(door_edit).commit(door).ok(), "door cutter");
	std::vector<VertexId> verts;
	door.all_vertices(verts);
	MeshEdit shifted(door);
	expect(ops::move_vertices(shifted, verts, godot::Vector3(1.4f, 0.2f, -0.2f)).ok(), "shift door through the wall");
	expect(std::move(shifted).commit(door).ok(), "shifted door");

	const double before = wall.signed_volume();
	MeshEdit cut(wall);
	expect(ops::boolean(cut, door, 1).ok(), "wall subtract");
	Mesh out;
	expect(std::move(cut).commit(out).ok(), "wall door commit");
	expect(validate(out).ok(), "doorway is watertight");
	expect(out.signed_volume() > 0.0, "doorway volume stays positive");
	expect(out.signed_volume() < before, "doorway removes wall volume");
	expect(out.face_count() > 6, "doorway adds tunnel faces");
}

SLAB_TEST(boolean_subtract_cuts_a_door_in_a_hollow_room) {
	MeshEdit room_edit = MeshEdit::empty();
	ops::box(room_edit, godot::Vector3(4, 3, 4));
	Mesh room;
	expect(std::move(room_edit).commit(room).ok(), "room box");
	std::vector<FaceId> faces;
	room.all_faces(faces);
	FaceId top;
	float up = -2.0f;
	for (const FaceId id : faces) {
		const float y = room.face_normal(id).y;
		if (y > up) {
			up = y;
			top = id;
		}
	}
	MeshEdit hollow(room);
	expect(ops::inset(hollow, { top }, 0.45f).ok(), "inset top");
	expect(ops::extrude(hollow, { top }, -2.4f).ok(), "pull inner cap down");
	expect(std::move(hollow).commit(room).ok(), "hollow commit");

	MeshEdit door_edit = MeshEdit::empty();
	ops::box(door_edit, godot::Vector3(0.7f, 1.6f, 1.2f));
	Mesh door;
	expect(std::move(door_edit).commit(door).ok(), "door cutter");
	std::vector<VertexId> verts;
	door.all_vertices(verts);
	MeshEdit shifted(door);
	expect(ops::move_vertices(shifted, verts, godot::Vector3(-0.15f, 0.7f, 1.4f)).ok(), "shift door through +X wall");
	expect(std::move(shifted).commit(door).ok(), "shifted door");

	const double before = room.signed_volume();
	MeshEdit cut(room);
	const MeshFault cut_fault = ops::boolean(cut, door, 1);
	expect(cut_fault.ok(), "room door subtract");
	Mesh out;
	expect(std::move(cut).commit(out).ok(), "room door commit");
	expect(validate(out).ok(), "room doorway is watertight");
	expect(out.signed_volume() > 0.0, "room doorway volume stays positive");
	expect(out.signed_volume() < before, "room doorway removes wall volume");
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
