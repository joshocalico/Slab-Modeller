#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/ops/uv.hpp"

#include <algorithm>
#include <cmath>
#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;

namespace {

godot::Vector2 uv_at(const Mesh &p_mesh, FaceId p_face, VertexId p_vertex) {
	const FaceAttrs attrs = p_mesh.attrs(p_face);
	const godot::Vector3 p = p_mesh.position(p_vertex);
	return godot::Vector2(p.dot(attrs.uv_u), p.dot(attrs.uv_v)) + attrs.uv_origin;
}

Mesh box() {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(4, 2, 4)).ok(), "make box");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "commit box");
	return mesh;
}

FaceId upward_face(const Mesh &p_mesh) {
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	return *std::max_element(faces.begin(), faces.end(), [&](FaceId a, FaceId b) {
		return p_mesh.face_normal(a).y < p_mesh.face_normal(b).y;
	});
}

std::vector<FaceId> cylinder_sides(const Mesh &p_mesh) {
	std::vector<FaceId> all;
	std::vector<FaceId> sides;
	p_mesh.all_faces(all);
	for (const FaceId face : all) {
		if (std::abs(p_mesh.face_normal(face).y) < 0.2f) sides.push_back(face);
	}
	return sides;
}

bool point_in_loop(const godot::Vector2 &p, const std::vector<godot::Vector2> &p_loop) {
	bool inside = false;
	for (size_t i = 0, j = p_loop.size() - 1; i < p_loop.size(); j = i++) {
		const godot::Vector2 &a = p_loop[j];
		const godot::Vector2 &b = p_loop[i];
		if ((a.y > p.y) != (b.y > p.y) &&
				p.x < a.x + (b.x - a.x) * (p.y - a.y) / (b.y - a.y)) inside = !inside;
	}
	return inside;
}

std::vector<godot::Vector2> uv_loop(const Mesh &p_mesh, FaceId p_face) {
	std::vector<VertexId> corners;
	p_mesh.face_corners(p_face, corners);
	std::vector<godot::Vector2> out;
	for (const VertexId corner : corners) out.push_back(uv_at(p_mesh, p_face, corner));
	return out;
}

} // namespace

SLAB_TEST(uv_unwrap_preserves_planar_patch_continuity_density_and_material) {
	Mesh source = box();
	MeshEdit edit(source);
	const FaceId top = upward_face(source);
	std::vector<VertexId> corners;
	edit.scratch().face_corners(top, corners);
	const EdgeId middle = edit.split_face(top, corners[0], corners[2]);
	FaceId left;
	FaceId right;
	edit.scratch().edge_faces(middle, left, right);
	FaceAttrs painted = edit.scratch().attrs(left);
	painted.material_slot = 19;
	painted.uv_scale = godot::Vector2(7, 3);
	edit.set_attrs(left, painted);

	const ops::UvUnwrapResult result = ops::unwrap_uv(edit, { left, right }, 256.0f, 1024);
	expect(result.ok(), "split planar patch unwraps");
	expect_eq(result.island_count, 1, "non-seam neighbours share an island");
	expect(result.auto_seams.empty(), "consistent planar cycle needs no automatic cut");
	VertexId a;
	VertexId b;
	edit.scratch().edge_vertices(middle, a, b);
	expect(uv_at(edit.scratch(), left, a).distance_to(uv_at(edit.scratch(), right, a)) < 0.00001f,
			"first hinge endpoint is continuous");
	expect(uv_at(edit.scratch(), left, b).distance_to(uv_at(edit.scratch(), right, b)) < 0.00001f,
			"second hinge endpoint is continuous");
	const double world_length = edit.scratch().position(a).distance_to(edit.scratch().position(b));
	const double uv_length = uv_at(edit.scratch(), left, a).distance_to(uv_at(edit.scratch(), left, b));
	expect_near(uv_length, world_length * 0.25, 0.0001, "256 pixels per metre in a 1024 texture");
	expect_eq(edit.scratch().attrs(left).material_slot, 19, "unwrap preserves material");
	expect(edit.scratch().attrs(left).uv_scale.is_equal_approx(godot::Vector2(1, 1)), "density resets repeat scale");
}

SLAB_TEST(uv_unwrap_accepts_a_reflex_planar_ngon) {
	const IVec3 reflex[] = {
		{ -2048, 0, -2048 }, { -2048, 0, 2048 }, { 0, 0, 512 },
		{ 2048, 0, 2048 }, { 2048, 0, -2048 },
	};
	MeshEdit made = MeshEdit::empty();
	expect(ops::prism(made, reflex, 5, 1024).ok(), "make reflex prism");
	Mesh mesh;
	expect(std::move(made).commit(mesh).ok(), "commit reflex prism");
	const FaceId top = upward_face(mesh);
	MeshEdit edit(mesh);
	const ops::UvUnwrapResult result = ops::unwrap_uv(edit, { top }, 128.0f, 512);
	expect(result.ok(), "reflex ngon unwraps without triangulation assumptions");
	expect(edit.scratch().attrs(top).uv_unwrapped, "reflex ngon stores unfolded covectors");
}

SLAB_TEST(uv_unwrap_marked_hinge_splits_two_faces_into_packed_islands) {
	Mesh source = box();
	MeshEdit edit(source);
	const FaceId top = upward_face(source);
	std::vector<VertexId> corners;
	edit.scratch().face_corners(top, corners);
	const EdgeId middle = edit.split_face(top, corners[0], corners[2]);
	FaceId a;
	FaceId b;
	edit.scratch().edge_faces(middle, a, b);
	edit.set_uv_seam(middle, true);
	const ops::UvUnwrapResult result = ops::unwrap_uv(edit, { a, b }, 64.0f, 256);
	expect(result.ok(), "marked-seam patch unwraps");
	expect_eq(result.island_count, 2, "marked shared hinge creates two islands");
	expect(result.auto_seams.empty(), "authored seam is not reported as automatic");
	VertexId va;
	VertexId vb;
	edit.scratch().edge_vertices(middle, va, vb);
	expect(uv_at(edit.scratch(), a, va).distance_to(uv_at(edit.scratch(), b, va)) > 0.0001f,
			"packed seam islands do not silently overlap at the hinge");
}

SLAB_TEST(uv_unwrap_curved_cylinder_explicitly_cuts_inconsistent_cycle) {
	MeshEdit made = MeshEdit::empty();
	expect(ops::cylinder(made, 2.0f, 3.0f, 8).ok(), "make cylinder");
	Mesh cylinder;
	expect(std::move(made).commit(cylinder).ok(), "commit cylinder");
	const std::vector<FaceId> sides = cylinder_sides(cylinder);
	expect_eq(int(sides.size()), 8, "eight hinged side faces");
	MeshEdit edit(cylinder);
	const ops::UvUnwrapResult result = ops::unwrap_uv(edit, sides, 100.0f, 1000);
	expect(result.ok(), "curved side strip unwraps");
	expect(!result.auto_seams.empty(), "closing cycle receives an explicit automatic seam");
	for (const EdgeId seam : result.auto_seams) expect(edit.scratch().edge_uv_seam(seam), "automatic cut is stored on mesh");
	for (const FaceId side : sides) expect(edit.scratch().attrs(side).uv_unwrapped, "each cylinder side receives a mapping");
}

SLAB_TEST(uv_unwrap_refuses_invalid_density_without_changing_attributes) {
	Mesh source = box();
	const FaceId top = upward_face(source);
	const FaceAttrs before = source.attrs(top);
	MeshEdit edit(source);
	expect(!ops::unwrap_uv(edit, { top }, 0.0f, 1024).ok(), "zero density is refused");
	expect(!edit.scratch().attrs(top).uv_unwrapped && edit.scratch().attrs(top).material_slot == before.material_slot,
			"refusal leaves face attributes unchanged");
}

SLAB_TEST(uv_unwrap_branching_box_net_does_not_silently_overlap_faces) {
	Mesh source = box();
	std::vector<FaceId> faces;
	source.all_faces(faces);
	MeshEdit edit(source);
	const ops::UvUnwrapResult result = ops::unwrap_uv(edit, faces, 128.0f, 512);
	expect(result.ok(), "closed branching box surface unwraps");
	expect(!result.auto_seams.empty(), "box cycle or overlapping branches receive explicit cuts");
	for (const EdgeId edge : result.auto_seams) expect(edit.scratch().edge_uv_seam(edge), "each reported box cut is stored");
	for (size_t i = 0; i < faces.size(); i++) {
		const std::vector<godot::Vector2> a = uv_loop(edit.scratch(), faces[i]);
		godot::Vector2 centre;
		for (const godot::Vector2 &point : a) centre += point;
		centre /= float(a.size());
		for (size_t j = 0; j < faces.size(); j++) {
			if (i != j) expect(!point_in_loop(centre, uv_loop(edit.scratch(), faces[j])),
					"a box face centre is not hidden under another island");
		}
	}
}
