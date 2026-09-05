#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/offset_loop.hpp"
#include "kernel/ops/primitives.hpp"

#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;

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

SLAB_TEST(box_commits_a_valid_cube) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 3, 2)).ok(), "box op");
	Mesh mesh;
	const MeshFault committed = std::move(edit).commit(mesh);
	expect(committed.ok(), "box commit");
	expect_eq(mesh.face_count(), 6, "box faces");
	expect_eq(mesh.vertex_count(), 8, "box verts");
	expect_eq(mesh.edge_count(), 12, "box edges");
	expect_eq(mesh.vertex_count() - mesh.edge_count() + mesh.face_count(), 2, "box euler");
	expect(validate(mesh).ok(), "box validate");
	expect_near(mesh.signed_volume(), 12.0, 0.01, "box volume");
}

SLAB_TEST(inverted_lift_cannot_commit) {
	MeshEdit edit = MeshEdit::empty();
	const IVec3 loop[4] = {
		IVec3{ 0, 0, 0 },
		IVec3{ 0, 0, 2048 },
		IVec3{ 2048, 0, 2048 },
		IVec3{ 2048, 0, 0 },
	};
	const FaceId top = edit.make_lamina(loop, 4);
	edit.lift_loop(top);
	std::vector<VertexId> corners;
	edit.scratch().face_corners(top, corners);
	for (const VertexId v : corners) {
		IVec3 p = edit.scratch().position_i(v);
		p.y = -3072;
		edit.move_vertex(v, p);
	}
	Mesh mesh;
	const MeshFault committed = std::move(edit).commit(mesh);
	expect(!committed.ok(), "inverted must not commit");
	expect_eq(int(committed.code), int(MeshError::INVERTED_VOLUME), "inverted code");
}

SLAB_TEST(empty_cannot_commit) {
	MeshEdit edit = MeshEdit::empty();
	Mesh mesh;
	const MeshFault committed = std::move(edit).commit(mesh);
	expect(!committed.ok(), "empty must not commit");
	expect_eq(int(committed.code), int(MeshError::RESULT_EMPTY), "empty code");
}

SLAB_TEST(extrude_keeps_cap_id_and_uvs) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 3, 2)).ok(), "box op");
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "box commit");

	const FaceId top = top_face(box);
	FaceAttrs attrs;
	attrs.uv_scale = godot::Vector2(2, 2);
	attrs.uv_offset = godot::Vector2(0.5f, 0);

	MeshEdit pulled(box);
	pulled.set_attrs(top, attrs);
	expect(ops::extrude(pulled, { top }, 1.0f).ok(), "extrude op");
	Mesh out;
	expect(std::move(pulled).commit(out).ok(), "extrude commit");

	expect(out.alive(top), "extrude keeps cap id");
	expect_eq(out.face_count(), 10, "extrude faces");
	expect_eq(out.vertex_count(), 12, "extrude verts");
	expect_eq(out.vertex_count() - out.edge_count() + out.face_count(), 2, "extrude euler");
	expect_near(out.signed_volume(), 16.0, 0.01, "extrude volume");
	expect_near(out.attrs(top).uv_scale.x, 2.0, 0.0001, "uv scale survives extrude");
	expect_near(out.attrs(top).uv_offset.x, 0.5, 0.0001, "uv offset survives extrude");
}
