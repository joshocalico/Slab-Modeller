#include "harness.hpp"

#include "kernel/emit.hpp"
#include "kernel/mesh_edit.hpp"
#include "kernel/ops/bevel.hpp"
#include "kernel/ops/import.hpp"
#include "kernel/ops/inset.hpp"
#include "kernel/ops/loop.hpp"
#include "kernel/ops/offset_loop.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/quantize.hpp"
#include "kernel/triangulate.hpp"

#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;

static std::vector<IVec3> _quantize_emit(const EmitOut &p_out) {
	std::vector<IVec3> verts;
	verts.reserve(p_out.verts.size());
	for (const godot::Vector3 &p : p_out.verts) {
		IVec3 q;
		expect(quantize(p, q), "emit vertex quantizes");
		verts.push_back(q);
	}
	return verts;
}

SLAB_TEST(import_closed_box_succeeds) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 2, 2)).ok(), "box primitive builds");
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "box commits");

	EmitOut arrays;
	emit_arrays(box, arrays);
	const std::vector<IVec3> verts = _quantize_emit(arrays);
	const ops::ImportResult imported = ops::import_from_triangles(verts, arrays.indices);
	expect(imported.fault.ok(), "closed box soup promotes");
	expect(imported.refuse_reason.empty(), "success has no refuse reason");
	expect(imported.mesh.face_count() > 0, "promoted mesh has faces");
	expect(validate(imported.mesh).ok(), "promoted mesh validates");
	expect(imported.mesh.signed_volume() > 0.0, "promoted mesh has positive volume");
}

SLAB_TEST(import_empty_refuses) {
	const ops::ImportResult imported = ops::import_from_triangles({}, {});
	expect(!imported.fault.ok(), "empty soup refuses");
	expect_eq(imported.refuse_reason == "empty" ? 1 : 0, 1, "empty reason");
}

SLAB_TEST(import_open_triangle_refuses) {
	const IVec3 a{ 0, 0, 0 };
	const IVec3 b{ 1024, 0, 0 };
	const IVec3 c{ 0, 1024, 0 };
	const ops::ImportResult imported = ops::import_from_triangles({ a, b, c }, { 0, 1, 2 });
	expect(!imported.fault.ok(), "open triangle refuses");
	expect_eq(imported.refuse_reason == "open" ? 1 : 0, 1, "open reason");
}

SLAB_TEST(import_non_manifold_edge_refuses) {
	const IVec3 a{ 0, 0, 0 };
	const IVec3 b{ 1024, 0, 0 };
	const IVec3 c{ 0, 1024, 0 };
	const IVec3 d{ 0, 0, 1024 };
	const IVec3 e{ 1024, 1024, 0 };
	const ops::ImportResult imported = ops::import_from_triangles(
			{ a, b, c, d, e },
			{ 0, 1, 2, 0, 1, 3, 0, 1, 4 });
	expect(!imported.fault.ok(), "triple edge refuses");
	expect(imported.refuse_reason.find("non-manifold") != std::string::npos, "non-manifold reason");
}

SLAB_TEST(import_does_not_cap_open_quad) {
	const IVec3 a{ 0, 0, 0 };
	const IVec3 b{ 1024, 0, 0 };
	const IVec3 c{ 1024, 1024, 0 };
	const IVec3 d{ 0, 1024, 0 };
	const ops::ImportResult imported = ops::import_from_triangles(
			{ a, b, c, d },
			{ 0, 1, 2, 0, 2, 3 });
	expect(!imported.fault.ok(), "open quad refuses instead of capping");
	expect_eq(imported.refuse_reason == "open" ? 1 : 0, 1, "open quad reason");
}

SLAB_TEST(import_flips_inverted_box) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 2, 2)).ok(), "box primitive builds");
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "box commits");

	EmitOut arrays;
	emit_arrays(box, arrays);
	std::vector<int32_t> reversed = arrays.indices;
	for (size_t i = 0; i + 2 < reversed.size(); i += 3) {
		const int32_t tmp = reversed[i + 1];
		reversed[i + 1] = reversed[i + 2];
		reversed[i + 2] = tmp;
	}
	const std::vector<IVec3> verts = _quantize_emit(arrays);
	const ops::ImportResult imported = ops::import_from_triangles(verts, reversed);
	expect(imported.fault.ok(), "inverted closed box still promotes");
	expect(imported.mesh.signed_volume() > 0.0, "flipped import has positive volume");
}

static FaceId _face_facing(const Mesh &p_mesh, const godot::Vector3 &p_dir) {
	FaceId best;
	float score = -2.0f;
	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	for (const FaceId id : faces) {
		const float d = p_mesh.face_normal(id).dot(p_dir);
		if (d > score) {
			score = d;
			best = id;
		}
	}
	return best;
}

static EdgeId _first_edge(const Mesh &p_mesh) {
	std::vector<EdgeId> edges;
	p_mesh.all_edges(edges);
	return edges.empty() ? EdgeId{} : edges[0];
}

static EdgeId _edge_between(const Mesh &p_mesh, VertexId p_a, VertexId p_b) {
	std::vector<EdgeId> edges;
	p_mesh.all_edges(edges);
	for (const EdgeId id : edges) {
		VertexId a;
		VertexId b;
		p_mesh.edge_vertices(id, a, b);
		if ((a.slot == p_a.slot && b.slot == p_b.slot) || (a.slot == p_b.slot && b.slot == p_a.slot)) {
			return id;
		}
	}
	return {};
}

static void _split_first_edge_with_midpoint(std::vector<IVec3> &r_verts, std::vector<int32_t> &r_indices, bool p_include_sliver) {
	expect(r_indices.size() >= 3, "emit has a triangle to split");
	const int32_t a = r_indices[0];
	const int32_t b = r_indices[1];
	const int32_t c = r_indices[2];
	const IVec3 pa = r_verts[size_t(a)];
	const IVec3 pb = r_verts[size_t(b)];
	const IVec3 mid{
		int32_t((int64_t(pa.x) + pb.x) / 2),
		int32_t((int64_t(pa.y) + pb.y) / 2),
		int32_t((int64_t(pa.z) + pb.z) / 2),
	};
	expect(!(mid == pa) && !(mid == pb), "split midpoint is a distinct lattice point");
	r_verts.push_back(mid);
	const int32_t m = int32_t(r_verts.size() - 1);
	r_indices[0] = a;
	r_indices[1] = m;
	r_indices[2] = c;
	r_indices.insert(r_indices.begin() + 3, m);
	r_indices.insert(r_indices.begin() + 4, b);
	r_indices.insert(r_indices.begin() + 5, c);
	if (p_include_sliver) {
		r_indices.push_back(a);
		r_indices.push_back(b);
		r_indices.push_back(m);
	}
}

SLAB_TEST(import_keeps_a_zero_area_sliver_on_a_closed_box) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 2, 2)).ok(), "box primitive builds");
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "box commits");

	EmitOut arrays;
	emit_arrays(box, arrays);
	std::vector<IVec3> verts = _quantize_emit(arrays);
	std::vector<int32_t> indices = arrays.indices;
	_split_first_edge_with_midpoint(verts, indices, true);

	const ops::ImportResult imported = ops::import_from_triangles(verts, indices);
	expect(imported.fault.ok(), "closed box plus sliver still promotes");
	expect(imported.refuse_reason.empty(), "sliver success has no refuse reason");
	expect(validate(imported.mesh).ok(), "promoted sliver mesh validates");
	expect(imported.mesh.signed_volume() > 0.0, "promoted sliver mesh keeps volume");
}

SLAB_TEST(import_recovers_a_missing_sliver_t_junction) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 2, 2)).ok(), "box primitive builds");
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "box commits");

	EmitOut arrays;
	emit_arrays(box, arrays);
	std::vector<IVec3> verts = _quantize_emit(arrays);
	std::vector<int32_t> indices = arrays.indices;
	_split_first_edge_with_midpoint(verts, indices, false);

	const ops::ImportResult imported = ops::import_from_triangles(verts, indices);
	expect(imported.fault.ok(), "T-junction sliver hole still promotes");
	expect(imported.refuse_reason.empty(), "recovered sliver has no refuse reason");
	expect(validate(imported.mesh).ok(), "recovered mesh validates");
	expect(imported.mesh.signed_volume() > 0.0, "recovered mesh keeps volume");
}

SLAB_TEST(import_annex_rack_obj_soup_promotes) {
	// Unique lattice verts + triangles from the PRS-41 Annex rack OBJ
	// (annex_rack_export.obj). Emit dropped a collinear sliver; the soup is
	// closed once that zero-area hole is paired.
	const IVec3 verts[] = {
			{ 1669, 4106, -1188 },
			{ 2304, 4106, -1665 },
			{ 2304, 4106, -1189 },
			{ 1669, 4106, -1665 },
			{ 1638, 2263, -1189 },
			{ 2304, 2263, -1665 },
			{ 1638, 2263, -1665 },
			{ 2304, 2263, -1189 },
			{ 1638, 4075, -1665 },
			{ 1638, 4075, -1188 },
			{ 1654, 4091, -1665 },
			{ 1654, 4091, -1188 },
			{ 1638, 4075, -1127 },
			{ 1654, 4091, -1127 },
			{ 1638, 2263, -1127 },
			{ 2304, 2263, -1127 },
			{ 2304, 4106, -1127 },
			{ 1669, 4106, -1127 },
			{ 1679, 4058, -1127 },
			{ 1683, 4062, -1127 },
			{ 1679, 2304, -1127 },
			{ 2263, 2304, -1127 },
			{ 2263, 4065, -1127 },
			{ 1686, 4065, -1127 },
	};
	const int32_t faces[] = {
			0, 1, 2, 0, 3, 1, 4, 5, 6, 4, 7, 5, 8, 4, 6, 8, 9, 4, 2, 5, 7, 2, 1, 5,
			1, 6, 5, 1, 8, 6, 1, 10, 8, 1, 3, 10, 10, 9, 8, 10, 11, 9, 11, 12, 9, 11, 13, 12,
			12, 4, 9, 12, 14, 4, 14, 7, 4, 15, 2, 7, 15, 16, 2, 16, 0, 2, 16, 17, 0,
			13, 18, 12, 13, 19, 18, 18, 14, 12, 18, 20, 14, 20, 15, 14, 20, 21, 15,
			21, 16, 15, 21, 22, 16, 22, 17, 16, 22, 23, 17, 13, 0, 17, 13, 11, 0,
			11, 3, 0, 11, 10, 3, 19, 17, 23, 19, 13, 17, 7, 14, 15, 23, 20, 18,
			23, 21, 20, 23, 22, 21,
	};
	const std::vector<IVec3> soup(verts, verts + sizeof(verts) / sizeof(verts[0]));
	const std::vector<int32_t> indices(faces, faces + sizeof(faces) / sizeof(faces[0]));
	const ops::ImportResult imported = ops::import_from_triangles(soup, indices);
	expect(imported.fault.ok(), "Annex rack OBJ soup promotes");
	expect(imported.refuse_reason.empty(), "Annex rack has no refuse reason");
	expect(validate(imported.mesh).ok(), "Annex rack mesh validates");
	expect(imported.mesh.signed_volume() > 0.0, "Annex rack keeps volume");
}

SLAB_TEST(import_how_to_try_it_topo_path_promotes) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(0.65f, 1.8f, 0.45f)).ok(), "how-to-try box builds");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "how-to-try box commits");

	{
		MeshEdit next(mesh);
		expect(ops::bevel(next, { _first_edge(mesh) }, 0.03f).ok(), "bevel one edge");
		expect(std::move(next).commit(mesh).ok(), "bevel commits");
	}
	{
		MeshEdit next(mesh);
		const FaceId front = _face_facing(mesh, godot::Vector3(0, 0, 1));
		expect(ops::extrude(next, { front }, 0.06f).ok(), "extrude front face");
		expect(std::move(next).commit(mesh).ok(), "extrude commits");
	}
	{
		MeshEdit next(mesh);
		const FaceId front = _face_facing(mesh, godot::Vector3(0, 0, 1));
		expect(ops::inset(next, { front }, 0.04f).ok(), "inset front face");
		expect(std::move(next).commit(mesh).ok(), "inset commits");
	}
	{
		MeshEdit next(mesh);
		expect(ops::insert_loop(next, _first_edge(mesh), 0.5f).ok(), "loop cut");
		expect(std::move(next).commit(mesh).ok(), "loop cut commits");
	}
	{
		const FaceId front = _face_facing(mesh, godot::Vector3(0, 0, 1));
		std::vector<VertexId> corners;
		mesh.face_corners(front, corners);
		if (corners.size() >= 4) {
			const EdgeId a = _edge_between(mesh, corners[0], corners[1]);
			const EdgeId b = _edge_between(mesh, corners[2], corners[3]);
			if (mesh.alive(a) && mesh.alive(b)) {
				MeshEdit next(mesh);
				if (ops::connect_edges(next, a, b).ok()) {
					expect(std::move(next).commit(mesh).ok(), "connect commits");
				}
			}
		}
	}

	expect(validate(mesh).ok(), "topo'd how-to-try solid stays closed");
	expect(mesh.signed_volume() > 0.0, "topo'd how-to-try solid has volume");

	EmitOut arrays;
	emit_arrays(mesh, arrays);
	const std::vector<IVec3> verts = _quantize_emit(arrays);
	const ops::ImportResult imported = ops::import_from_triangles(verts, arrays.indices);
	expect(imported.fault.ok(), "topo'd how-to-try emit soup promotes");
	expect(imported.refuse_reason.empty(), "how-to-try promote has no refuse reason");
	expect(validate(imported.mesh).ok(), "promoted how-to-try mesh validates");
	expect(imported.mesh.signed_volume() > 0.0, "promoted how-to-try mesh has volume");
}

SLAB_TEST(triangulate_emits_a_collinear_triangle) {
	const IVec3 a{ 0, 0, 0 };
	const IVec3 b{ 4, 4, 0 };
	const IVec3 c{ 7, 7, 0 };
	std::vector<int32_t> tris;
	triangulate_loop({ a, b, c }, tris);
	expect_eq(int(tris.size()), 3, "collinear face still emits one triangle");
}

SLAB_TEST(import_preserves_triangle_materials_and_uvs) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 3, 4)).ok(), "attribute source box builds");
	Mesh source;
	expect(std::move(edit).commit(source).ok(), "attribute source commits");
	EmitOut emitted;
	emit_arrays(source, emitted);
	std::vector<ops::ImportTriangleAttrs> attrs(emitted.indices.size() / 3);
	for (size_t t = 0; t < attrs.size(); t++) {
		attrs[t].material_slot = uint32_t(t % 3);
		attrs[t].has_uvs = true;
		attrs[t].uvs = {godot::Vector2(0.11f, 0.27f), godot::Vector2(0.83f, 0.19f), godot::Vector2(0.42f, 0.91f)};
	}
	const auto vertices = _quantize_emit(emitted);
	const auto imported = ops::import_from_triangles(vertices, emitted.indices, attrs);
	expect(imported.fault.ok(), "UV and material import succeeds");
	std::vector<FaceId> faces;
	imported.mesh.all_faces(faces);
	expect_eq(int(faces.size()), int(attrs.size()), "all source triangles survive");
	for (size_t t = 0; t < faces.size(); t++) {
		const FaceAttrs actual = imported.mesh.attrs(faces[t]);
		expect_eq(int(actual.material_slot), int(attrs[t].material_slot), "triangle retains material slot");
		for (size_t k = 0; k < 3; k++) {
			const auto p = dequantize(vertices[size_t(emitted.indices[t * 3 + k])]);
			const godot::Vector2 uv = godot::Vector2(p.dot(actual.uv_u), p.dot(actual.uv_v)) + actual.uv_origin;
			expect(uv.distance_to(attrs[t].uvs[k]) < 0.0001f, "UV remains attached to original position after winding normalization");
		}
	}
	attrs.pop_back();
	expect(!ops::import_from_triangles(vertices, emitted.indices, attrs).fault.ok(), "incomplete attribute records refuse");
}

SLAB_TEST(import_refuses_malformed_tail_without_partial_success) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 2, 2)).ok(), "malformed source box builds");
	Mesh source;
	expect(std::move(edit).commit(source).ok(), "malformed source commits");
	EmitOut emitted;
	emit_arrays(source, emitted);
	const auto vertices = _quantize_emit(emitted);
	auto indices = emitted.indices;
	indices.push_back(0);
	expect(!ops::import_from_triangles(vertices, indices).fault.ok(), "trailing partial triangle refuses");
	indices.push_back(1);
	indices.push_back(-1);
	expect(!ops::import_from_triangles(vertices, indices).fault.ok(), "invalid triangle after closed mesh refuses");
	indices.back() = 0;
	expect(!ops::import_from_triangles(vertices, indices).fault.ok(), "collapsed triangle after closed mesh refuses");
}

SLAB_TEST(import_preserves_linear_sliver_uvs_and_refuses_inconsistent_uvs) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 2, 2)).ok(), "UV sliver source builds");
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "UV sliver source commits");
	EmitOut emitted;
	emit_arrays(box, emitted);
	auto vertices = _quantize_emit(emitted);
	auto indices = emitted.indices;
	_split_first_edge_with_midpoint(vertices, indices, true);
	std::vector<ops::ImportTriangleAttrs> attrs(indices.size() / 3);
	attrs.back().has_uvs = true;
	attrs.back().material_slot = 7;
	attrs.back().uvs = {godot::Vector2(0, 0), godot::Vector2(1, 1), godot::Vector2(0.5f, 0.5f)};
	const auto imported = ops::import_from_triangles(vertices, indices, attrs);
	expect(imported.fault.ok(), "linear user-authored sliver UVs promote");
	std::vector<FaceId> faces;
	imported.mesh.all_faces(faces);
	expect_eq(int(imported.mesh.attrs(faces.back()).material_slot), 7, "user sliver material preserved");
	attrs.back().uvs[2] = godot::Vector2(0.25f, 0.75f);
	const auto refused = ops::import_from_triangles(vertices, indices, attrs);
	expect(!refused.fault.ok(), "nonlinear sliver UVs refuse without discarding attributes");
	expect(refused.refuse_reason == "unsupported UV mapping", "sliver refusal explains unsupported mapping");
}
