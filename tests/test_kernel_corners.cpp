#include "harness.hpp"
#include "kernel/emit.hpp"
#include "kernel/mesh_edit.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/serialize.hpp"
#include <cmath>
#include <limits>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;

namespace {
Mesh corner_box() {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 2, 2)).ok(), "box builds");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "box commits");
	return mesh;
}
std::vector<FaceId> faces_of(const Mesh &mesh) {
	std::vector<FaceId> faces;
	mesh.all_faces(faces);
	return faces;
}
}

SLAB_TEST(corner_uvs_are_independent_persistent_and_emit_exactly) {
	Mesh mesh = corner_box();
	const FaceId face = faces_of(mesh)[0];
	MeshEdit edit(mesh);
	for (uint32_t i = 0; i < 4; ++i) {
		CornerAttrs attrs;
		attrs.uv_explicit = true;
		attrs.uv_pinned = i == 2;
		attrs.uv = godot::Vector2(float(i) * .17f, float(i * i) * .11f);
		edit.set_corner_attrs(face, i, attrs);
	}
	std::vector<EdgeId> edges;
	mesh.all_edges(edges);
	edit.set_hard_edge(edges[0], true);
	expect(std::move(edit).commit(mesh).ok(), "nonaffine UVs do not alter solid validity");
	Mesh reloaded;
	expect(deserialize(serialize(mesh), reloaded).ok(), "corner data reloads");
	expect(serialize(reloaded) == serialize(mesh), "corner bytes round trip exactly");
	std::vector<CornerAttrs> corners;
	reloaded.face_corner_attrs(face, corners);
	expect(corners[2].uv_pinned && !corners[1].uv_pinned, "pin stays on its own corner");
	expect(reloaded.edge_hard(edges[0]), "hard edge survives reload");
	std::vector<godot::Vector2> uvs;
	face_uv_points(reloaded, face, uvs);
	for (size_t i = 0; i < corners.size(); ++i)
		expect(uvs[i].distance_to(corners[i].uv) < 1e-6f, "explicit UV emits unchanged");
	expect_near(reloaded.signed_volume(), 8.0, 1e-6, "surface edit leaves volume unchanged");
	const auto before = serialize(mesh);
	MeshEdit invalid(mesh);
	CornerAttrs nan;
	nan.uv.x = std::numeric_limits<float>::quiet_NaN();
	invalid.set_corner_attrs(face, 0, nan);
	expect(!std::move(invalid).commit(mesh).ok(), "nonfinite UV refused at mutation boundary");
	expect(serialize(mesh) == before, "invalid UV never publishes");
}

SLAB_TEST(corner_attributes_survive_edge_and_face_splits) {
	Mesh mesh = corner_box();
	const FaceId face = faces_of(mesh)[0];
	MeshEdit edit(mesh);
	std::vector<VertexId> old_vertices;
	mesh.face_corners(face, old_vertices);
	for (uint32_t i = 0; i < 4; ++i) {
		CornerAttrs attrs;
		attrs.uv_explicit = true;
		attrs.uv = godot::Vector2(float(i), float(i * i));
		edit.set_corner_attrs(face, i, attrs);
	}
	std::vector<EdgeId> edges;
	mesh.face_edges(face, edges);
	edit.set_hard_edge(edges[0], true);
	const IVec3 a = mesh.position_i(old_vertices[0]), b = mesh.position_i(old_vertices[1]);
	const VertexId middle = edit.split_edge(edges[0], IVec3{(a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2});
	expect(edit.scratch().alive(middle), "edge split creates midpoint");
	std::vector<VertexId> vertices;
	std::vector<CornerAttrs> attrs;
	edit.scratch().face_corners(face, vertices);
	edit.scratch().face_corner_attrs(face, attrs);
	for (size_t i = 0; i < vertices.size(); ++i) if (vertices[i].slot == middle.slot)
		expect(attrs[i].uv_explicit && attrs[i].uv.distance_to(godot::Vector2(.5f,.5f)) < 1e-6f,
			"new corner interpolates its own face side");
	const EdgeId cut = edit.split_face(face, old_vertices[0], old_vertices[2]);
	expect(edit.scratch().alive(cut), "split face after UV edit");
	expect(std::move(edit).commit(mesh).ok(), "topology split remains valid");
	Mesh reloaded;
	expect(deserialize(serialize(mesh), reloaded).ok(), "split attrs reload");
	FaceId left, right;
	reloaded.edge_faces(cut, left, right);
	for (FaceId f : {left, right}) {
		reloaded.face_corner_attrs(f, attrs);
		for (const CornerAttrs &attr : attrs) expect(attr.uv_explicit, "new boundary retains explicit mapping");
	}
}

SLAB_TEST(smoothing_respects_hard_edges_and_emits_normal_map_tangents) {
	Mesh mesh = corner_box();
	MeshEdit smooth(mesh);
	for (FaceId face : faces_of(mesh)) {
		FaceAttrs attrs = mesh.attrs(face);
		attrs.smooth = true;
		smooth.set_attrs(face, attrs);
	}
	expect(std::move(smooth).commit(mesh).ok(), "smooth faces commit");
	EmitOut out;
	emit_arrays(mesh, out);
	expect_eq(int(out.tangents.size()), int(out.verts.size()*4), "every vertex has a tangent frame");
	for (size_t i = 0; i < out.verts.size(); ++i) {
		const godot::Vector3 n = out.normals[i];
		expect_near(std::abs(n.x), 1.0/std::sqrt(3.0), 1e-5, "cube smooth normal joins three faces");
		godot::Vector3 t(out.tangents[i*4], out.tangents[i*4+1], out.tangents[i*4+2]);
		expect_near(n.dot(t), 0, 1e-5, "tangent orthogonal to smoothed normal");
		expect_near(t.length(), 1, 1e-5, "tangent normalized");
	}
	MeshEdit hard(mesh);
	std::vector<EdgeId> edges;
	mesh.all_edges(edges);
	for (EdgeId edge : edges) hard.set_hard_edge(edge, true);
	expect(std::move(hard).commit(mesh).ok(), "hard boundaries commit");
	emit_arrays(mesh, out);
	for (size_t t = 0; t < out.provenance.size(); ++t) {
		const godot::Vector3 flat = mesh.face_normal(out.provenance[t]);
		for (int k = 0; k < 3; ++k)
			expect(out.normals[out.indices[t*3+k]].distance_to(flat) < 1e-6, "hard edges stop smoothing fan");
	}
}

SLAB_TEST(version_four_defaults_corner_attributes_and_rejects_corrupt_five) {
	Mesh mesh = corner_box();
	auto bytes = serialize(mesh);
	const uint32_t halves = uint32_t(bytes[12]) | uint32_t(bytes[13])<<8 | uint32_t(bytes[14])<<16 | uint32_t(bytes[15])<<24;
	bytes.resize(bytes.size() - halves*9);
	bytes[4] = 4;
	Mesh legacy;
	expect(deserialize(bytes, legacy).ok(), "real v4 layout remains readable");
	for (FaceId face : faces_of(legacy)) {
		std::vector<CornerAttrs> corners;
		legacy.face_corner_attrs(face, corners);
		for (const auto &corner : corners) expect(!corner.uv_explicit && !corner.uv_pinned, "v4 keeps projection defaults");
	}
	const auto before = serialize(legacy);
	bytes = serialize(mesh);
	bytes[bytes.size()-9] = 128;
	expect(deserialize(bytes, legacy).code == MeshError::CORRUPT_DATA, "unknown corner flags refused");
	expect(serialize(legacy) == before, "failed decode leaves destination intact");
}

SLAB_TEST(reversing_winding_keeps_corner_uvs_on_their_vertices) {
	Mesh mesh = corner_box();
	const FaceId face = faces_of(mesh)[0];
	MeshEdit edit(mesh);
	std::vector<VertexId> vertices;
	mesh.face_corners(face, vertices);
	for (uint32_t i = 0; i < vertices.size(); ++i) {
		CornerAttrs corner;
		corner.uv_explicit = true;
		corner.uv_pinned = i == 1;
		corner.uv = godot::Vector2(float(i), float(i*i));
		edit.set_corner_attrs(face, i, corner);
	}
	expect(edit.flip_all().ok(), "temporary winding reversal succeeds");
	std::vector<VertexId> reversed;
	std::vector<CornerAttrs> corners;
	edit.scratch().face_corners(face, reversed);
	edit.scratch().face_corner_attrs(face, corners);
	for (size_t i = 0; i < reversed.size(); ++i) {
		for (size_t j = 0; j < vertices.size(); ++j) {
			if (reversed[i].slot != vertices[j].slot) continue;
			expect(corners[i].uv == godot::Vector2(float(j), float(j*j)), "UV stays at geometric corner during reversal");
			expect(corners[i].uv_pinned == (j == 1), "pin stays at geometric corner during reversal");
		}
	}
	expect(edit.flip_all().ok(), "restore positive winding");
	expect(std::move(edit).commit(mesh).ok(), "restored winding commits with corner data");
}
