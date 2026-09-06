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

static Mesh make_box(const godot::Vector3 &p_size) {
	MeshEdit edit = MeshEdit::empty();
	ops::box(edit, p_size);
	Mesh mesh;
	std::move(edit).commit(mesh);
	return mesh;
}

static Mesh shifted(const Mesh &p_src, const godot::Vector3 &p_delta) {
	Mesh mesh = p_src;
	std::vector<VertexId> verts;
	mesh.all_vertices(verts);
	MeshEdit moved(mesh);
	ops::move_vertices(moved, verts, p_delta);
	std::move(moved).commit(mesh);
	return mesh;
}

SLAB_TEST(extrude_through_the_floor_cannot_commit) {
	Mesh box = make_box(godot::Vector3(2, 3, 2));
	const FaceId top = top_face(box);
	MeshEdit stabbed(box);
	expect(ops::extrude(stabbed, { top }, -4.0f).ok(), "extrude op still runs");
	Mesh out;
	const MeshFault committed = std::move(stabbed).commit(out);
	expect(!committed.ok(), "a cap through the floor is not a solid");
	expect_eq(int(committed.code), int(MeshError::SELF_INTERSECTION), "self intersection code");
}

SLAB_TEST(inward_extrude_without_an_inset_cannot_commit) {
	Mesh box = make_box(godot::Vector3(2, 3, 2));
	const FaceId top = top_face(box);
	MeshEdit pushed(box);
	expect(ops::extrude(pushed, { top }, -1.0f).ok(), "extrude op still runs");
	Mesh out;
	const MeshFault committed = std::move(pushed).commit(out);
	expect(!committed.ok(), "a cap inside the box is not a solid");
	expect_eq(int(committed.code), int(MeshError::SELF_INTERSECTION), "self intersection code");
}

SLAB_TEST(inset_then_extrude_a_room_still_commits) {
	Mesh box = make_box(godot::Vector3(4, 3, 4));
	const FaceId top = top_face(box);
	MeshEdit hollow(box);
	expect(ops::inset(hollow, { top }, 0.45f).ok(), "inset");
	expect(ops::extrude(hollow, { top }, -2.4f).ok(), "pull the inner cap down");
	Mesh room;
	expect(std::move(hollow).commit(room).ok(), "a hollow room is a solid");
	expect(validate(room).ok(), "room validate");
}

SLAB_TEST(house_boolean_still_commits) {
	Mesh body = make_box(godot::Vector3(4, 2.2f, 4));
	MeshEdit roof_edit = MeshEdit::empty();
	ops::arch(roof_edit, 4.0f, 4.0f, 12, 0.4f, Math_PI);
	Mesh roof;
	expect(std::move(roof_edit).commit(roof).ok(), "arch");
	roof = shifted(roof, godot::Vector3(0, 2.05f, 0));
	MeshEdit joined(body);
	expect(ops::boolean(joined, roof, 0).ok(), "house union");
	Mesh house;
	expect(std::move(joined).commit(house).ok(), "house union commit");

	const Mesh door = shifted(make_box(godot::Vector3(0.9f, 1.6f, 1.2f)), godot::Vector3(1.55f, 0.0f, -0.2f));
	MeshEdit cut(house);
	expect(ops::boolean(cut, door, 1).ok(), "house door");
	expect(std::move(cut).commit(house).ok(), "house door commit");
	expect(validate(house).ok(), "house stays an embedded solid");
}
