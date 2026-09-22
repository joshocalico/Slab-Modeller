#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/ops/uv.hpp"
#include "kernel/ops/region.hpp"
#include "kernel/serialize.hpp"

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
	const ops::UvUnwrapResult result = ops::unwrap_uv(edit, { a, b }, 30.0f, 256);
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
	const ops::UvUnwrapResult result = ops::unwrap_uv(edit, sides, 64.0f, 1024);
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
	const ops::UvUnwrapResult result = ops::unwrap_uv(edit, faces, 64.0f, 1024);
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

SLAB_TEST(uv_unwrap_packs_every_corner_inside_the_single_texture) {
	Mesh source = box();
	std::vector<FaceId> faces;
	source.all_faces(faces);
	MeshEdit edit(source);
	const ops::UvUnwrapResult result = ops::unwrap_uv(edit, faces, 64.0f, 1024);
	expect(result.ok(), "low-density box atlas fits");
	for (const FaceId face : faces) {
		std::vector<VertexId> corners;
		edit.scratch().face_corners(face, corners);
		for (const VertexId corner : corners) {
			const godot::Vector2 uv = uv_at(edit.scratch(), face, corner);
			expect(uv.x >= -0.00001f && uv.y >= -0.00001f && uv.x <= 1.00001f && uv.y <= 1.00001f,
					"packed corner remains in the non-wrapping atlas");
		}
	}
}

SLAB_TEST(uv_unwrap_atlas_overflow_is_atomic_and_actionable) {
	Mesh source = box();
	std::vector<FaceId> faces;
	source.all_faces(faces);
	std::vector<EdgeId> source_edges;
	source.all_edges(source_edges);
	MeshEdit marked(source);
	for (const EdgeId edge : source_edges) marked.set_uv_seam(edge, true);
	expect(std::move(marked).commit(source).ok(), "prepare six independent face islands");
	MeshEdit edit(source);
	const ops::UvUnwrapResult result = ops::unwrap_uv(edit, faces, 256.0f, 1024);
	expect(!result.ok() && result.atlas_overflow, "oversized multi-island atlas is explicitly refused");
	expect(result.suggested_texture_resolution > 1024, "overflow suggests a larger texture");
	for (const FaceId face : faces) expect(!edit.scratch().attrs(face).uv_unwrapped, "overflow changes no face mapping");
	std::vector<EdgeId> edges;
	edit.scratch().all_edges(edges);
	for (const EdgeId edge : edges) expect(edit.scratch().edge_uv_seam(edge), "overflow preserves authored seam state");
	MeshEdit retry(source);
	const ops::UvUnwrapResult retried = ops::unwrap_uv(retry, faces, 256.0f, result.suggested_texture_resolution);
	expect(retried.ok(), "retry at the suggested resolution demonstrably fits every island");
}

SLAB_TEST(uv_pack_rearranges_existing_islands_without_reunfolding) {
	Mesh source = box();
	std::vector<FaceId> faces;
	source.all_faces(faces);
	MeshEdit unwrapped(source);
	expect(ops::unwrap_uv(unwrapped, faces, 64.0f, 1024).ok(), "box unwraps for pack");
	expect(std::move(unwrapped).commit(source).ok(), "commit unwrap");
	std::vector<double> lengths;
	for (const FaceId face : faces) {
		std::vector<VertexId> corners;
		source.face_corners(face, corners);
		lengths.push_back(uv_at(source, face, corners[0]).distance_to(uv_at(source, face, corners[1])));
	}
	MeshEdit shifted(source);
	for (const FaceId face : faces) {
		FaceAttrs attrs = shifted.scratch().attrs(face);
		attrs.uv_offset = godot::Vector2(0.35f, 0.35f);
		shifted.set_attrs(face, attrs);
	}
	expect(std::move(shifted).commit(source).ok(), "commit offset placement");
	std::vector<VertexId> first_corners;
	source.face_corners(faces[0], first_corners);
	const godot::Vector2 before_pack = uv_at(source, faces[0], first_corners[0]) + source.attrs(faces[0]).uv_offset;
	MeshEdit packed(source);
	const ops::UvPackResult packed_result = ops::pack_uv(packed, faces, 1024, 1024);
	expect(packed_result.ok(), "offset islands pack at the same atlas");
	expect(packed_result.island_count >= 1, "pack reports islands");
	for (size_t i = 0; i < faces.size(); i++) {
		std::vector<VertexId> corners;
		packed.scratch().face_corners(faces[i], corners);
		expect_near(uv_at(packed.scratch(), faces[i], corners[0]).distance_to(
				uv_at(packed.scratch(), faces[i], corners[1])),
				lengths[i], 0.0001, "pack keeps island edge lengths instead of unfolding again");
		for (const VertexId corner : corners) {
			const godot::Vector2 uv = uv_at(packed.scratch(), faces[i], corner);
			expect(uv.x >= -0.00001f && uv.y >= -0.00001f && uv.x <= 1.00001f && uv.y <= 1.00001f,
					"packed corner returns to the atlas");
		}
	}
	expect(uv_at(packed.scratch(), faces[0], first_corners[0]).distance_to(before_pack) > 0.001f,
			"pack moves offset islands rather than leaving them where placement put them");
	const FaceId top = upward_face(source);
	std::vector<VertexId> top_corners;
	source.face_corners(top, top_corners);
	const double unwrap_len = uv_at(source, top, top_corners[0]).distance_to(uv_at(source, top, top_corners[1]));
	MeshEdit scaled(source);
	FaceAttrs top_attrs = scaled.scratch().attrs(top);
	top_attrs.uv_offset = godot::Vector2();
	top_attrs.uv_scale = godot::Vector2(2, 2);
	scaled.set_attrs(top, top_attrs);
	const ops::UvPackResult scaled_pack = ops::pack_uv(scaled, { top }, 1024, 1024);
	expect(scaled_pack.ok(), "a single 2x island packs");
	expect_near(uv_at(scaled.scratch(), top, top_corners[0]).distance_to(
			uv_at(scaled.scratch(), top, top_corners[1])),
			unwrap_len * 2.0, 0.0001, "pack keeps the 2x placement instead of unfolding at 1x");
	MeshEdit again(source);
	FaceAttrs reset = again.scratch().attrs(top);
	reset.uv_offset = godot::Vector2();
	reset.uv_scale = godot::Vector2(2, 2);
	again.set_attrs(top, reset);
	expect(ops::unwrap_uv(again, { top }, 64.0f, 1024).ok(), "unwrap of the scaled face succeeds");
	expect_near(uv_at(again.scratch(), top, top_corners[0]).distance_to(
			uv_at(again.scratch(), top, top_corners[1])),
			unwrap_len, 0.0001, "unwrap rebuilds island size from 3D and drops placement scale");
	expect(packed.scratch().attrs(faces[0]).uv_scale.is_equal_approx(godot::Vector2(1, 1)),
			"successful pack bakes placement into the mapping");
	expect(packed.scratch().attrs(faces[0]).uv_offset.is_equal_approx(godot::Vector2()),
			"successful pack clears placement offset");
}

SLAB_TEST(uv_pack_overflow_is_atomic_and_actionable) {
	Mesh source = box();
	std::vector<FaceId> faces;
	source.all_faces(faces);
	MeshEdit unwrapped(source);
	expect(ops::unwrap_uv(unwrapped, faces, 64.0f, 1024).ok(), "box unwraps before overflow pack");
	expect(std::move(unwrapped).commit(source).ok(), "commit unwrap");
	MeshEdit scaled(source);
	for (const FaceId face : faces) {
		FaceAttrs attrs = scaled.scratch().attrs(face);
		attrs.uv_scale = godot::Vector2(16, 16);
		scaled.set_attrs(face, attrs);
	}
	expect(std::move(scaled).commit(source).ok(), "commit oversized placement");
	const FaceAttrs before = source.attrs(faces[0]);
	MeshEdit edit(source);
	const ops::UvPackResult result = ops::pack_uv(edit, faces, 1024, 1024);
	expect(!result.ok() && result.atlas_overflow, "oversized packed islands are refused");
	expect(result.suggested_texture_resolution > 1024, "overflow suggests a larger texture");
	expect(edit.scratch().attrs(faces[0]).uv_scale.is_equal_approx(before.uv_scale),
			"overflow leaves placement scale unchanged");
	expect(edit.scratch().attrs(faces[0]).uv_origin.is_equal_approx(before.uv_origin),
			"overflow leaves mapping origin unchanged");
	MeshEdit retry(source);
	const ops::UvPackResult retried = ops::pack_uv(retry, faces, result.suggested_texture_resolution, 1024);
	expect(retried.ok(), "raising Texture px relative to the authored atlas fits the same islands");
}

SLAB_TEST(uv_pack_refuses_planar_faces_without_mutating) {
	Mesh source = box();
	const FaceId top = upward_face(source);
	const FaceAttrs before = source.attrs(top);
	MeshEdit edit(source);
	expect(!ops::pack_uv(edit, { top }, 1024).ok(), "planar faces are not packed");
	expect(!edit.scratch().attrs(top).uv_unwrapped &&
			edit.scratch().attrs(top).uv_scale.is_equal_approx(before.uv_scale),
			"planar pack refusal leaves attributes unchanged");
}

SLAB_TEST(uv_pack_preserves_per_face_atlas_density_after_reload_and_topology) {
	Mesh source = box();
	std::vector<FaceId> faces;
	source.all_faces(faces);
	const FaceId a = faces[0], b = faces[1];
	MeshEdit first(source);
	expect(ops::unwrap_uv(first, {a}, 32.0f, 512).ok(), "first subset unwraps at 512");
	expect(std::move(first).commit(source).ok(), "commit first subset");
	MeshEdit second(source);
	expect(ops::unwrap_uv(second, {b}, 64.0f, 2048).ok(), "second subset unwraps at 2048");
	expect(std::move(second).commit(source).ok(), "commit second subset");
	MeshEdit placed(source);
	FaceAttrs attrs = placed.scratch().attrs(a);
	attrs.uv_scale = godot::Vector2(2, 2);
	attrs.uv_rotation = 0.3f;
	attrs.uv_offset = godot::Vector2(1, -2);
	placed.set_attrs(a, attrs);
	expect(std::move(placed).commit(source).ok(), "commit placement");
	const auto snapshot = serialize(source);
	Mesh reloaded;
	expect(deserialize(snapshot, reloaded).ok(), "reload mixed-resolution mapping");
	std::vector<double> pixel_lengths;
	for (FaceId face : {a, b}) {
		std::vector<VertexId> corners;
		reloaded.face_corners(face, corners);
		const double placement = face.slot == a.slot ? 2.0 : 1.0;
		pixel_lengths.push_back(uv_at(reloaded, face, corners[0]).distance_to(
				uv_at(reloaded, face, corners[1])) * reloaded.attrs(face).uv_texture_resolution * placement);
	}
	MeshEdit packed(reloaded);
	expect(ops::pack_uv(packed, {a, b}, 4096, 8192).ok(), "pack mixed sources ignoring unrelated fallback");
	expect(std::move(packed).commit(reloaded).ok(), "commit packed mapping");
	int i = 0;
	for (FaceId face : {a, b}) {
		std::vector<VertexId> corners;
		reloaded.face_corners(face, corners);
		expect_near(uv_at(reloaded, face, corners[0]).distance_to(uv_at(reloaded, face, corners[1])) * 4096,
				pixel_lengths[i++], 0.001, "per-face pixel density and placement applied exactly once");
		expect_eq(reloaded.attrs(face).uv_texture_resolution, 4096, "pack stores new source atlas");
	}
	expect(deserialize(snapshot, reloaded).ok(), "undo restores complete mapping snapshot");
	expect_eq(reloaded.attrs(a).uv_texture_resolution, 512, "undo restores first source resolution");
	expect_eq(reloaded.attrs(b).uv_texture_resolution, 2048, "undo restores second source resolution");
	MeshEdit topology(reloaded);
	expect(ops::extrude_region(topology, {a}, 0.25f).ok(), "extrude preserves mapping attributes");
	expect(std::move(topology).commit(reloaded).ok(), "commit extruded mapping");
	reloaded.all_faces(faces);
	int copied = 0;
	for (FaceId face : faces) if (reloaded.attrs(face).uv_texture_resolution == 512) copied++;
	expect(copied > 0, "topology copies retain source atlas resolution");
}
