#include "harness.hpp"
#include "kernel/emit.hpp"
#include "kernel/mesh_edit.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/ops/uv.hpp"
#include "kernel/serialize.hpp"
#include <algorithm>
#include <cmath>
#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;

namespace {
Mesh cube() {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(1, 1, 1)).ok(), "corner UV fixture box");
	Mesh result;
	expect(std::move(edit).commit(result).ok(), "corner UV fixture commits");
	return result;
}
FaceId top(const Mesh &mesh) {
	std::vector<FaceId> faces;
	mesh.all_faces(faces);
	return *std::max_element(faces.begin(), faces.end(), [&](FaceId a, FaceId b) { return mesh.face_normal(a).y < mesh.face_normal(b).y; });
}
std::vector<godot::Vector2> uvs(const Mesh &mesh, FaceId face) {
	std::vector<godot::Vector2> result;
	face_uv_points(mesh, face, result);
	return result;
}
void explicit_uvs(MeshEdit &edit, FaceId face, const std::vector<godot::Vector2> &uv, const std::vector<int> &pins = {}) {
	FaceAttrs attrs = edit.scratch().attrs(face);
	attrs.uv_texture_resolution = 512;
	attrs.uv_scale = godot::Vector2(1, 1);
	attrs.uv_offset = godot::Vector2();
	attrs.uv_rotation = 0;
	edit.set_attrs(face, attrs);
	for (size_t i = 0; i < uv.size(); ++i) {
		CornerAttrs c;
		c.uv_explicit = true;
		c.uv = uv[i];
		c.uv_pinned = std::find(pins.begin(), pins.end(), int(i)) != pins.end();
		edit.set_corner_attrs(face, uint32_t(i), c);
	}
}
std::vector<godot::Vector2> rectangle(float x, float y, float w, float h) {
	return {{x,y},{x+w,y},{x+w,y+h},{x,y+h}};
}
bool disjoint(const std::vector<godot::Vector2> &a, const std::vector<godot::Vector2> &b) {
	float ax=1e9f, ay=1e9f, az=-1e9f, aw=-1e9f, bx=1e9f, by=1e9f, bz=-1e9f, bw=-1e9f;
	for (auto p:a) { ax=std::min(ax,p.x); ay=std::min(ay,p.y); az=std::max(az,p.x); aw=std::max(aw,p.y); }
	for (auto p:b) { bx=std::min(bx,p.x); by=std::min(by,p.y); bz=std::max(bz,p.x); bw=std::max(bw,p.y); }
	return az <= bx || bz <= ax || aw <= by || bw <= ay;
}
}

SLAB_TEST(uv_pack_preserves_non_affine_effective_corners_and_density) {
	Mesh mesh = cube();
	FaceId face = top(mesh);
	MeshEdit authored(mesh);
	explicit_uvs(authored, face, {{0,0},{.3f,.02f},{.25f,.2f},{.04f,.25f}});
	FaceAttrs attrs = authored.scratch().attrs(face);
	attrs.material_slot = 9;
	attrs.uv_scale = godot::Vector2(1.5f, .75f);
	attrs.uv_rotation = .37f;
	attrs.uv_offset = godot::Vector2(1.2f, -.7f);
	authored.set_attrs(face, attrs);
	expect(std::move(authored).commit(mesh).ok(), "non-affine projected face authored");
	const auto before = uvs(mesh, face);
	MeshEdit packed(mesh);
	const auto result = ops::pack_uv(packed, {face}, 1024);
	expect(result.ok(), "Pack accepts explicit UVs without affine unwrap flag");
	expect(std::move(packed).commit(mesh).ok(), "non-affine Pack commits");
	const auto after = uvs(mesh, face);
	for (size_t i = 0; i < before.size(); ++i) {
		for (size_t j = i + 1; j < before.size(); ++j) {
			expect_near(after[i].distance_to(after[j]) * 1024, before[i].distance_to(before[j]) * 512, .001, "Pack preserves every pairwise pixel distance");
		}
		expect(after[i].x >= -1e-6 && after[i].y >= -1e-6 && after[i].x <= 1.000001 && after[i].y <= 1.000001, "explicit corner lies in packed tile");
	}
	expect((after[0] + after[2] - after[1] - after[3]).length() > .01f, "non-affine quad is not replaced by a parallelogram");
	expect_eq(mesh.attrs(face).material_slot, 9, "Pack preserves material");
	expect_eq(mesh.attrs(face).uv_texture_resolution, 1024, "Pack records new atlas density basis");
}

SLAB_TEST(uv_pack_freezes_pinned_island_and_avoids_its_bounds) {
	Mesh mesh = cube();
	std::vector<FaceId> faces;
	mesh.all_faces(faces);
	MeshEdit authored(mesh);
	explicit_uvs(authored, faces[0], rectangle(.375f,.375f,.25f,.25f), {0});
	explicit_uvs(authored, faces[1], rectangle(.4f,.4f,.3f,.2f));
	expect(std::move(authored).commit(mesh).ok(), "pinned and moving islands authored");
	const auto pinned = uvs(mesh, faces[0]);
	const auto moving = uvs(mesh, faces[1]);
	MeshEdit packed(mesh);
	expect(ops::pack_uv(packed, {faces[0],faces[1]}, 512).ok(), "unpinned island fits around fixed island");
	expect(std::move(packed).commit(mesh).ok(), "fixed-obstacle Pack commits");
	expect(uvs(mesh, faces[0]) == pinned, "entire pinned island stays exactly fixed");
	expect(uvs(mesh, faces[1]) != moving, "overlapping unpinned island moves");
	expect(disjoint(uvs(mesh, faces[0]), uvs(mesh, faces[1])), "packed bounds avoid pinned bounds");
	std::vector<CornerAttrs> corners;
	mesh.face_corner_attrs(faces[0], corners);
	expect(corners[0].uv_pinned, "Pack preserves pin flag");
	const auto bytes = serialize(mesh);
	MeshEdit resized(mesh);
	const auto refusal = ops::pack_uv(resized, {faces[0],faces[1]}, 1024);
	expect(!refusal.ok() && refusal.pinned_conflict && !refusal.refuse_reason.empty(), "pinned density resize explains conflict");
	expect(serialize(resized.scratch()) == bytes, "pinned resize refusal is atomic");
}

SLAB_TEST(uv_pack_pin_blocked_atlas_is_atomic) {
	Mesh mesh = cube();
	std::vector<FaceId> faces;
	mesh.all_faces(faces);
	MeshEdit edit(mesh);
	explicit_uvs(edit, faces[0], rectangle(.4f,.4f,.2f,.2f), {0});
	explicit_uvs(edit, faces[1], rectangle(0,0,.8f,.8f));
	const auto before = serialize(edit.scratch());
	const auto result = ops::pack_uv(edit, {faces[0],faces[1]}, 512);
	expect(!result.ok() && result.pinned_conflict && result.atlas_overflow, "fixed obstacle can prevent packing despite free total area");
	expect(!result.refuse_reason.empty(), "blocked packing explains how to recover");
	expect(serialize(edit.scratch()) == before, "blocked packing changes neither face");
}

SLAB_TEST(uv_pack_uses_explicit_shared_edge_continuity) {
	Mesh mesh = cube();
	FaceId face = top(mesh);
	MeshEdit edit(mesh);
	std::vector<VertexId> corners;
	mesh.face_corners(face, corners);
	const EdgeId diagonal = edit.split_face(face, corners[0], corners[2]);
	FaceId a,b;
	edit.scratch().edge_faces(diagonal,a,b);
	for (const FaceId f : {a,b}) {
		edit.scratch().face_corners(f, corners);
		std::vector<godot::Vector2> coords;
		for (const VertexId v : corners) {
			const auto p = edit.scratch().position(v);
			coords.push_back(godot::Vector2(.25f + p.x*.125f + p.x*p.z*.0625f, .25f + p.z*.125f));
		}
		explicit_uvs(edit, f, coords, f.slot == a.slot ? std::vector<int>{0} : std::vector<int>{});
	}
	const auto before = serialize(edit.scratch());
	const auto result = ops::pack_uv(edit, {a,b}, 512);
	expect(result.ok(), "explicit neighbouring triangles pack");
	expect_eq(result.island_count, 1, "shared effective UVs join one island");
	expect(serialize(edit.scratch()) == before, "one pin freezes both connected faces exactly");
}

SLAB_TEST(uv_unwrap_clears_stale_explicit_corners) {
	Mesh mesh = cube();
	const FaceId face = top(mesh);
	MeshEdit edit(mesh);
	explicit_uvs(edit, face, rectangle(2,3,.6f,.8f));
	const auto result = ops::unwrap_uv(edit, {face}, 64, 512);
	expect(result.ok(), "explicit face unwraps from geometry");
	std::vector<CornerAttrs> corners;
	edit.scratch().face_corner_attrs(face, corners);
	for (const auto &c : corners) expect(!c.uv_explicit, "old explicit override is cleared");
	const auto uv = uvs(edit.scratch(), face);
	expect_near(uv[0].distance_to(uv[1]), .125, .00001, "effective UVs use new density, not stale corners");
}

SLAB_TEST(uv_unwrap_solves_rotated_pins_and_preserves_exact_coordinates) {
	Mesh mesh = cube();
	const FaceId face = top(mesh);
	MeshEdit base(mesh);
	expect(ops::unwrap_uv(base, {face}, 64, 512).ok(), "make reference unfolding");
	const auto reference = uvs(base.scratch(), face);
	std::vector<godot::Vector2> target;
	for (const auto &uv : reference) target.push_back(godot::Vector2(-uv.y+.5f, uv.x+.375f));
	explicit_uvs(base, face, target, {0,1});
	const auto result = ops::unwrap_uv(base, {face}, 64, 512);
	expect(result.ok(), "two compatible pins rotate and anchor unfolding");
	const auto actual = uvs(base.scratch(), face);
	expect(actual[0] == target[0] && actual[1] == target[1], "pinned effective coordinates remain exact");
	for (size_t i=0;i<actual.size();++i) expect_near(actual[i].distance_to(target[i]), 0, .00001, "rigid pin solution places unpinned corners consistently");
	std::vector<CornerAttrs> corners;
	base.scratch().face_corner_attrs(face,corners);
	expect(corners[0].uv_pinned && corners[0].uv_explicit, "pin remains explicit and pinned");
	expect(!corners[2].uv_explicit, "unpinned explicit coordinate is replaced by unfold");
}

SLAB_TEST(uv_unwrap_incompatible_pins_refuses_without_changes) {
	Mesh mesh = cube();
	const FaceId face = top(mesh);
	MeshEdit edit(mesh);
	explicit_uvs(edit,face,rectangle(.25f,.25f,.5f,.5f),{0,1});
	const auto before=serialize(edit.scratch());
	const auto result=ops::unwrap_uv(edit,{face},64,512);
	expect(!result.ok() && result.pinned_conflict && !result.refuse_reason.empty(), "pin distance incompatible with density is explained");
	expect(serialize(edit.scratch())==before,"incompatible pins preserve all attributes and seams");
}

SLAB_TEST(uv_projection_reset_refuses_pins_then_clears_all_overrides) {
	Mesh mesh=cube();
	const FaceId face=top(mesh);
	MeshEdit edit(mesh);
	explicit_uvs(edit,face,rectangle(.25f,.25f,.125f,.125f),{0});
	FaceAttrs attrs=edit.scratch().attrs(face);
	attrs.material_slot=17;
	attrs.uv_unwrapped=true;
	attrs.uv_offset=godot::Vector2(.2f,.1f);
	edit.set_attrs(face,attrs);
	std::vector<EdgeId> edges;
	edit.scratch().face_edges(face,edges);
	edit.set_uv_seam(edges[0],true);
	const auto before=serialize(edit.scratch());
	const auto refused=ops::reset_uv_projection(edit,{face},UvAxis::Y);
	expect(!refused.ok() && refused.pinned_conflict && !refused.refuse_reason.empty(),"projection reset explains pinned conflict");
	expect(serialize(edit.scratch())==before,"pinned reset is atomic");
	std::vector<CornerAttrs> corners;
	edit.scratch().face_corner_attrs(face,corners);
	corners[0].uv_pinned=false;
	corners[0].surface.flags = SurfaceAttrs::COLOR | SurfaceAttrs::UV2;
	corners[0].surface.color = godot::Color(.2f,.3f,.4f,1);
	corners[0].surface.uv2 = godot::Vector2(.7f,.8f);
	edit.set_corner_attrs(face,0,corners[0]);
	expect(ops::reset_uv_projection(edit,{face},UvAxis::Y).ok(),"unpinned projection resets");
	attrs=edit.scratch().attrs(face);
	expect(!attrs.uv_unwrapped && attrs.uv_texture_resolution==0,"reset removes atlas mapping and density metadata");
	expect(attrs.uv_scale==godot::Vector2(1,1) && attrs.uv_offset==godot::Vector2() && attrs.uv_rotation==0,"reset removes placement transforms");
	edit.scratch().face_corner_attrs(face,corners);
	for (auto c:corners) expect(!c.uv_explicit && !c.uv_pinned,"reset clears explicit coordinates without leaving pins");
	expect(corners[0].surface.flags == (SurfaceAttrs::COLOR | SurfaceAttrs::UV2) && corners[0].surface.color == godot::Color(.2f,.3f,.4f,1) && corners[0].surface.uv2 == godot::Vector2(.7f,.8f), "UV reset preserves imported surface attributes");
	std::vector<VertexId> vertices;
	edit.scratch().face_corners(face,vertices);
	const auto projected=uvs(edit.scratch(),face);
	for (size_t i=0;i<vertices.size();++i) { auto p=edit.scratch().position(vertices[i]); expect(projected[i]==godot::Vector2(p.x,p.z),"effective UV uses requested projection axis"); }
	expect_eq(attrs.material_slot,17,"projection reset preserves material");
	expect(edit.scratch().edge_uv_seam(edges[0]),"projection reset preserves seam annotations");
}
