#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/inset.hpp"
#include "kernel/ops/offset_loop.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/ops/region.hpp"
#include "kernel/ops/subdivide.hpp"

#include <algorithm>
#include <cmath>
#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;

namespace {

Mesh box(const godot::Vector3 &p_size) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, p_size).ok(), "box op");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "box commit");
	return out;
}

FaceId upward_face(const Mesh &p_mesh) {
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	return *std::max_element(faces.begin(), faces.end(), [&](FaceId p_a, FaceId p_b) {
		return p_mesh.face_normal(p_a).y < p_mesh.face_normal(p_b).y;
	});
}

std::vector<FaceId> split_cap(MeshEdit &p_edit, FaceId p_face, size_t p_a, size_t p_b) {
	std::vector<VertexId> corners;
	p_edit.scratch().face_corners(p_face, corners);
	const EdgeId seam = p_edit.split_face(p_face, corners[p_a], corners[p_b]);
	expect(p_edit.last_fault().ok(), "split cap");
	FaceId a;
	FaceId b;
	p_edit.scratch().edge_faces(seam, a, b);
	return { a, b };
}

std::vector<FaceId> upward_faces(const Mesh &p_mesh, double p_area_under) {
	std::vector<FaceId> all;
	std::vector<FaceId> out;
	p_mesh.all_faces(all);
	for (const FaceId face : all) {
		if (p_mesh.face_normal(face).y > 0.99f && p_mesh.face_area(face) < p_area_under) {
			out.push_back(face);
		}
	}
	return out;
}

} // namespace

SLAB_TEST(region_extrude_of_a_split_box_cap_builds_boundary_walls_only) {
	Mesh source = box(godot::Vector3(4, 2, 4));
	MeshEdit edit(source);
	const std::vector<FaceId> caps = split_cap(edit, upward_face(source), 0, 2);
	FaceAttrs left = edit.scratch().attrs(caps[0]);
	left.material_slot = 17;
	left.uv_scale = godot::Vector2(2, 3);
	edit.set_attrs(caps[0], left);
	FaceAttrs right = edit.scratch().attrs(caps[1]);
	right.material_slot = 23;
	right.uv_offset = godot::Vector2(0.25f, 0.5f);
	edit.set_attrs(caps[1], right);

	expect(ops::extrude_region(edit, caps, 1.0f).ok(), "connected cap extrudes");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "connected extrusion commits");
	expect(validate(out).ok(), "connected extrusion validates");
	expect_eq(out.face_count(), 11, "four boundary walls and two cap faces");
	expect_near(out.signed_volume(), 48.0, 0.001, "region adds one cap area of volume");
	std::vector<FaceId> top = upward_faces(out, 15.0);
	expect_eq(int(top.size()), 2, "internal cap adjacency is restored");
	std::vector<uint32_t> slots;
	for (const FaceId face : top) {
		slots.push_back(out.attrs(face).material_slot);
	}
	std::sort(slots.begin(), slots.end());
	expect_eq(slots[0], 17, "first cap material survives");
	expect_eq(slots[1], 23, "second cap material survives");
}

SLAB_TEST(region_extrude_keeps_a_nonconvex_connected_boundary) {
	const IVec3 loop[] = {
		{ -2048, 0, 2048 }, { 0, 0, 512 }, { 2048, 0, 2048 },
		{ 2048, 0, -2048 }, { -2048, 0, -2048 },
	};
	MeshEdit made = MeshEdit::empty();
	expect(ops::prism(made, loop, 5, 2048).ok(), "concave prism");
	Mesh prism;
	expect(std::move(made).commit(prism).ok(), "concave prism commits");
	MeshEdit edit(prism);
	const std::vector<FaceId> caps = split_cap(edit, upward_face(prism), 1, 3);
	expect(ops::extrude_region(edit, caps, 0.5f).ok(), "nonconvex region extrudes");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "nonconvex region commits");
	expect(validate(out).ok(), "nonconvex region validates");
	expect(out.signed_volume() > prism.signed_volume(), "positive extrusion adds volume");
}

SLAB_TEST(region_extrude_preserves_a_four_quad_center_junction) {
	Mesh source = box(godot::Vector3(4, 2, 4));
	MeshEdit edit(source);
	const FaceId top = upward_face(source);
	expect(ops::subdivide(edit, { top }).ok(), "subdivide top into four quads");
	std::vector<FaceId> caps = upward_faces(edit.scratch(), 5.0);
	expect_eq(int(caps.size()), 4, "four cap quads meet at the center");
	expect(ops::extrude_region(edit, caps, 1.0f).ok(), "four-quad region extrudes");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "four-quad extrusion commits");
	expect(validate(out).ok(), "four-quad extrusion validates");
	expect_eq(out.face_count(), 17, "four caps and eight segmented boundary walls");
	expect_eq(int(upward_faces(out, 5.0).size()), 4, "center junction remains four caps");
}

SLAB_TEST(region_inset_then_negative_extrude_builds_a_legal_room) {
	Mesh source = box(godot::Vector3(4, 3, 4));
	MeshEdit edit(source);
	const FaceId top = upward_face(source);
	expect(ops::subdivide(edit, { top }).ok(), "subdivide room cap");
	std::vector<FaceId> caps = upward_faces(edit.scratch(), 5.0);
	expect_eq(int(caps.size()), 4, "room starts with four cap quads");
	expect(ops::inset_region(edit, caps, 0.45f).ok(), "connected cap insets as one region");
	caps.clear();
	for (const FaceId face : upward_faces(edit.scratch(), 8.0)) {
		const double area = edit.scratch().face_area(face);
		if (area > 2.0 && area < 3.0) caps.push_back(face);
	}
	expect_eq(int(caps.size()), 4, "inset keeps the four inner caps and center junction");
	expect(ops::extrude_region(edit, caps, -2.4f).ok(), "connected inner caps move down together");
	Mesh room;
	expect(std::move(edit).commit(room).ok(), "region room commits");
	expect(validate(room).ok(), "region room passes the unchanged validity gate");
}

SLAB_TEST(region_extrude_supports_a_patch_with_a_hole) {
	Mesh source = box(godot::Vector3(6, 2, 6));
	MeshEdit prepared(source);
	const FaceId top = upward_face(source);
	expect(ops::inset(prepared, { top }, 1.0f).ok(), "make a cap surrounded by a ring");
	Mesh ring_source;
	expect(std::move(prepared).commit(ring_source).ok(), "ring source commits");
	std::vector<FaceId> ring;
	for (const FaceId face : upward_faces(ring_source, 7.0)) {
		if (ring_source.face_area(face) < 7.0) ring.push_back(face);
	}
	expect_eq(int(ring.size()), 4, "four faces form a patch with an inner boundary");
	MeshEdit edit(ring_source);
	expect(ops::extrude_region(edit, ring, 0.5f).ok(), "region with a hole extrudes");
	Mesh out;
	expect(std::move(edit).commit(out).ok(), "raised ring commits");
	expect(validate(out).ok(), "raised ring validates");
	expect(out.signed_volume() > ring_source.signed_volume(), "raised ring adds volume");
	MeshEdit inset_edit(ring_source);
	expect(ops::inset_region(inset_edit, ring, 0.2f).ok(), "region with a hole insets both boundary loops");
	Mesh inset_ring;
	expect(std::move(inset_edit).commit(inset_ring).ok(), "inset ring commits");
	expect(validate(inset_ring).ok(), "inset ring validates");
}

SLAB_TEST(region_rejects_disconnected_nonplanar_and_whole_mesh_selections) {
	Mesh source = box(godot::Vector3(2, 2, 2));
	std::vector<FaceId> faces;
	source.all_faces(faces);
	MeshEdit whole(source);
	expect_eq(int(ops::extrude_region(whole, faces, 1.0f).code), int(MeshError::INVALID_SELECTION), "whole mesh is not a region cap");

	FaceId top = upward_face(source);
	FaceId bottom;
	FaceId side;
	for (const FaceId face : faces) {
		if (source.face_normal(face).y < -0.99f) {
			bottom = face;
		}
		if (std::abs(source.face_normal(face).x) > 0.99f) {
			side = face;
		}
	}
	MeshEdit disconnected(source);
	expect_eq(int(ops::extrude_region(disconnected, { top, bottom }, 1.0f).code), int(MeshError::INVALID_SELECTION), "disconnected faces are refused");
	MeshEdit folded(source);
	expect_eq(int(ops::inset_region(folded, { top, side }, 0.25f).code), int(MeshError::INVALID_SELECTION), "nonplanar faces are refused");
}
