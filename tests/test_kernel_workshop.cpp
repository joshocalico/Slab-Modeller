#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/boolean.hpp"
#include "kernel/ops/edit.hpp"
#include "kernel/ops/inset.hpp"
#include "kernel/ops/offset_loop.hpp"
#include "kernel/ops/primitives.hpp"

#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;

namespace {

FaceId top_face(const Mesh &p_mesh) {
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

Mesh make_box(const godot::Vector3 &p_size) {
	MeshEdit edit = MeshEdit::empty();
	ops::box(edit, p_size);
	Mesh mesh;
	std::move(edit).commit(mesh);
	return mesh;
}

Mesh xformed(const Mesh &p_src, const godot::Transform3D &p_xf) {
	Mesh mesh = p_src;
	std::vector<VertexId> verts;
	mesh.all_vertices(verts);
	MeshEdit moved(mesh);
	for (const VertexId id : verts) {
		IVec3 q;
		quantize(p_xf.xform(mesh.position(id)), q);
		moved.move_vertex(id, q);
	}
	std::move(moved).commit(mesh);
	return mesh;
}

Mesh shifted(const Mesh &p_src, const godot::Vector3 &p_delta) {
	return xformed(p_src, godot::Transform3D(godot::Basis(), p_delta));
}

Mesh workshop_with_door() {
	Mesh room = make_box(godot::Vector3(7, 3.5f, 7));
	const FaceId top = top_face(room);
	MeshEdit hollow(room);
	ops::inset(hollow, { top }, 0.35f);
	ops::extrude(hollow, { top }, -3.15f);
	std::move(hollow).commit(room);
	const Mesh door = shifted(make_box(godot::Vector3(2, 2.6f, 1.2f)), godot::Vector3(2.5f, 0.3f, 6.1f));
	MeshEdit cut(room);
	ops::boolean(cut, door, 1);
	std::move(cut).commit(room);
	return room;
}

MeshFault subtract(Mesh &p_host, const Mesh &p_cutter) {
	MeshEdit cut(p_host);
	const MeshFault op = ops::boolean(cut, p_cutter, 1);
	if (!op.ok()) {
		return op;
	}
	return std::move(cut).commit(p_host);
}

int euler(const Mesh &p_mesh) {
	return p_mesh.vertex_count() - p_mesh.edge_count() + p_mesh.face_count();
}

} // namespace

SLAB_TEST(workshop_door_then_right_wall_windows) {
	Mesh room = workshop_with_door();
	expect(validate(room).ok(), "workshop with door is a solid");
	expect_eq(euler(room), 0, "a room with one door is genus 1");

	const float zs[] = { 1.2f, 3.2f, 5.2f };
	const char *labels[] = { "window z=4.2", "window z=6.2", "window z=8.2" };
	const double before = room.signed_volume();
	for (int i = 0; i < 3; i++) {
		const Mesh cutter = shifted(make_box(godot::Vector3(1.2f, 0.85f, 1.1f)), godot::Vector3(6.4f, 1.7f, zs[i]));
		expect(subtract(room, cutter).ok(), labels[i]);
		expect(validate(room).ok(), labels[i]);
		expect_eq(euler(room), -2 * (i + 1), labels[i]);
	}
	expect(room.signed_volume() > 0.0, "workshop volume stays positive");
	expect(room.signed_volume() < before, "three windows remove wall volume");
}

SLAB_TEST(workshop_oblique_cutter_that_fully_crosses_the_wall) {
	// Relay Yard's corner-pivoted 1.4 box at the outer west wall only kisses x=0
	// along an edge, which is a T-junction, not a through opening. A cutter that
	// actually exits the skin is the intended angled window.
	Mesh room = workshop_with_door();
	godot::Transform3D xf;
	xf.origin = godot::Vector3(-0.5f, 1.9f, 3);
	xf.basis = godot::Basis(godot::Vector3(0, 1, 0), Math_PI / 4.0);
	const Mesh cutter = xformed(make_box(godot::Vector3(1.4f, 0.8f, 1.4f)), xf);
	const double before = room.signed_volume();
	expect(subtract(room, cutter).ok(), "45 degree cutter that exits the outer wall");
	expect(validate(room).ok(), "oblique opening stays an embedded solid");
	expect_eq(euler(room), -2, "door plus one oblique window is genus 2");
	expect(room.signed_volume() > 0.0, "through oblique volume stays positive");
	expect(room.signed_volume() < before, "oblique opening removes wall volume");
}

SLAB_TEST(workshop_oblique_cutter_at_relay_yard_shifted_origin) {
	// Codex will move the demo cutter to world x=1.6 (local -0.4 with the
	// workshop at x=2) so the rotated box actually leaves the outer skin.
	Mesh room = workshop_with_door();
	godot::Transform3D xf;
	xf.origin = godot::Vector3(-0.4f, 1.9f, 3);
	xf.basis = godot::Basis(godot::Vector3(0, 1, 0), Math_PI / 4.0);
	const Mesh cutter = xformed(make_box(godot::Vector3(1.4f, 0.8f, 1.4f)), xf);
	expect(subtract(room, cutter).ok(), "Relay Yard's shifted 45 degree cutter");
	expect(validate(room).ok(), "shifted oblique opening stays embedded");
	expect_eq(euler(room), -2, "door plus the shifted oblique window is genus 2");
}
