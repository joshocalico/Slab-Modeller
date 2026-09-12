#include "harness.hpp"

#include "kernel/emit.hpp"
#include "kernel/mesh_edit.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/serialize.hpp"

#include <cstdint>
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

static Mesh make_box() {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 3, 2)).ok(), "box op");
	Mesh mesh;
	expect(std::move(edit).commit(mesh).ok(), "box commit");
	return mesh;
}

static bool same_edge(EdgeId p_a, EdgeId p_b) {
	return p_a.slot == p_b.slot && p_a.gen == p_b.gen;
}

static bool has_edge(const std::vector<EdgeId> &p_list, EdgeId p_id) {
	for (const EdgeId e : p_list) {
		if (same_edge(e, p_id)) {
			return true;
		}
	}
	return false;
}

SLAB_TEST(box_has_twelve_canonical_edges) {
	const Mesh mesh = make_box();
	std::vector<EdgeId> edges;
	mesh.all_edges(edges);
	expect_eq(int(edges.size()), 12, "all_edges count");
	expect_eq(mesh.edge_count(), 12, "edge_count");
	for (const EdgeId e : edges) {
		expect(mesh.alive(e), "edge alive");
		VertexId a;
		VertexId b;
		mesh.edge_vertices(e, a, b);
		expect(mesh.alive(a) && mesh.alive(b), "edge has two live verts");
		expect(a.slot != b.slot, "edge verts distinct");
		FaceId fa;
		FaceId fb;
		mesh.edge_faces(e, fa, fb);
		expect(mesh.alive(fa) && mesh.alive(fb), "edge has two live faces");
		expect(fa.slot != fb.slot, "edge faces distinct");
	}
	const FaceId top = top_face(mesh);
	expect_near(mesh.face_area(top), 4.0, 0.01, "top area");
	expect_near(double(mesh.face_centroid(top).y), 3.0, 0.01, "top centroid y");
	const godot::AABB aabb = mesh.local_aabb();
	expect_near(double(aabb.size.x), 2.0, 0.01, "aabb x");
	expect_near(double(aabb.size.y), 3.0, 0.01, "aabb y");
	expect_near(double(aabb.size.z), 2.0, 0.01, "aabb z");
}

SLAB_TEST(box_face_edges_cover_each_edge_twice) {
	const Mesh mesh = make_box();
	std::vector<FaceId> faces;
	mesh.all_faces(faces);
	expect_eq(int(faces.size()), 6, "six faces");
	std::vector<EdgeId> edges;
	mesh.all_edges(edges);
	std::vector<int> hits(edges.size(), 0);
	for (const FaceId f : faces) {
		std::vector<EdgeId> fe;
		mesh.face_edges(f, fe);
		expect_eq(int(fe.size()), 4, "quad face_edges");
		for (const EdgeId e : fe) {
			int found = 0;
			for (size_t i = 0; i < edges.size(); i++) {
				if (same_edge(edges[i], e)) {
					hits[i]++;
					found++;
				}
			}
			expect_eq(found, 1, "face edge is in all_edges once");
		}
	}
	for (int h : hits) {
		expect_eq(h, 2, "edge appears in two faces");
	}
}

SLAB_TEST(edge_id_matches_from_either_half_edge) {
	const Mesh mesh = make_box();
	std::vector<FaceId> faces;
	mesh.all_faces(faces);
	for (const FaceId f : faces) {
		std::vector<EdgeId> fe;
		mesh.face_edges(f, fe);
		for (const EdgeId e : fe) {
			FaceId fa;
			FaceId fb;
			mesh.edge_faces(e, fa, fb);
			expect(mesh.alive(fa) && mesh.alive(fb), "both faces live");
			std::vector<EdgeId> a_edges;
			std::vector<EdgeId> b_edges;
			mesh.face_edges(fa, a_edges);
			mesh.face_edges(fb, b_edges);
			expect(has_edge(a_edges, e), "canonical id from first face");
			expect(has_edge(b_edges, e), "canonical id from twin face");
			expect(e.slot < 0xFFFFFFFFu, "edge slot not invalid");
			expect(mesh.alive(e), "canonical edge alive");
			EdgeId flipped;
			flipped.slot = e.slot;
			flipped.gen = e.gen + 1;
			expect(!mesh.alive(flipped), "wrong gen is stale");
		}
	}
}

SLAB_TEST(emit_box_is_twelve_triangles) {
	const Mesh mesh = make_box();
	EmitOut out;
	emit_arrays(mesh, out);
	expect_eq(int(out.provenance.size()), 12, "twelve triangles");
	expect_eq(int(out.indices.size()), 36, "thirty-six indices");
	expect_eq(int(out.verts.size()), 24, "four verts per face");
	expect_eq(int(out.normals.size()), int(out.verts.size()), "normal per vert");
	expect_eq(int(out.uvs.size()), int(out.verts.size()), "uv per vert");
	for (const FaceId id : out.provenance) {
		expect(mesh.alive(id), "provenance face alive");
	}
}

SLAB_TEST(emit_winds_clockwise_against_the_outward_normal) {
	const Mesh mesh = make_box();
	EmitOut out;
	emit_arrays(mesh, out);
	expect(out.indices.size() >= 3, "emitted triangles");
	for (size_t i = 0; i + 2 < out.indices.size(); i += 3) {
		const godot::Vector3 a = out.verts[size_t(out.indices[i])];
		const godot::Vector3 b = out.verts[size_t(out.indices[i + 1])];
		const godot::Vector3 c = out.verts[size_t(out.indices[i + 2])];
		const godot::Vector3 n = out.normals[size_t(out.indices[i])];
		const godot::Vector3 geo = (b - a).cross(c - a);
		expect(geo.dot(n) < 0.0f, "Godot front faces are clockwise when looking along the outward normal");
	}
}

SLAB_TEST(emit_applies_face_uv_scale_and_offset) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 3, 2)).ok(), "box op");
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "box commit");
	const FaceId top = top_face(box);

	EmitOut plain;
	emit_arrays(box, plain);

	FaceAttrs attrs;
	attrs.uv_scale = godot::Vector2(2, 2);
	attrs.uv_offset = godot::Vector2(0.5f, 0.25f);
	MeshEdit painted(box);
	painted.set_attrs(top, attrs);
	Mesh mesh;
	expect(std::move(painted).commit(mesh).ok(), "attrs commit");

	EmitOut out;
	emit_arrays(mesh, out);
	int compared = 0;
	for (size_t i = 0; i < out.provenance.size(); i++) {
		if (out.provenance[i].slot != top.slot || out.provenance[i].gen != top.gen) {
			continue;
		}
		for (int k = 0; k < 3; k++) {
			const int32_t pi = plain.indices[int(i) * 3 + k];
			const int32_t oi = out.indices[int(i) * 3 + k];
			const godot::Vector2 want = godot::Vector2(
					plain.uvs[pi].x * 2.0f + 0.5f,
					plain.uvs[pi].y * 2.0f + 0.25f);
			expect_near(double(out.uvs[oi].x), double(want.x), 0.0001, "uv scale+offset x");
			expect_near(double(out.uvs[oi].y), double(want.y), 0.0001, "uv scale+offset y");
			compared++;
		}
	}
	expect(compared == 6, "top face two triangles");
}

SLAB_TEST(serialize_round_trips_ids_and_attrs) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 3, 2)).ok(), "box op");
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "box commit");
	const FaceId top = top_face(box);
	FaceAttrs attrs;
	attrs.uv_scale = godot::Vector2(2, 3);
	attrs.uv_offset = godot::Vector2(0.5f, 0.25f);
	attrs.uv_rotation = 0.4f;
	attrs.uv_axis = UvAxis::Y;
	attrs.material_slot = 7;
	attrs.smooth = true;
	attrs.uv_unwrapped = true;
	attrs.uv_u = godot::Vector3(0.5f, 0, 0);
	attrs.uv_v = godot::Vector3(0, 0, 0.5f);
	attrs.uv_origin = godot::Vector2(0.125f, 0.25f);
	MeshEdit painted(box);
	painted.set_attrs(top, attrs);
	std::vector<EdgeId> edges;
	box.all_edges(edges);
	painted.set_uv_seam(edges.front(), true);
	Mesh mesh;
	expect(std::move(painted).commit(mesh).ok(), "attrs commit");

	const std::vector<uint8_t> bytes = serialize(mesh);
	Mesh loaded;
	const MeshFault got = deserialize(bytes, loaded);
	expect(got.ok(), "deserialize ok");
	expect_eq(loaded.face_count(), mesh.face_count(), "face_count");
	expect_eq(loaded.edge_count(), mesh.edge_count(), "edge_count");
	expect_eq(loaded.vertex_count(), mesh.vertex_count(), "vertex_count");
	expect_near(loaded.signed_volume(), mesh.signed_volume(), 0.0001, "signed_volume");
	expect(loaded.alive(top), "FaceId alive after reload");
	const FaceAttrs back = loaded.attrs(top);
	expect_near(double(back.uv_scale.x), 2.0, 0.0001, "uv_scale.x");
	expect_near(double(back.uv_scale.y), 3.0, 0.0001, "uv_scale.y");
	expect_near(double(back.uv_offset.x), 0.5, 0.0001, "uv_offset.x");
	expect_near(double(back.uv_offset.y), 0.25, 0.0001, "uv_offset.y");
	expect_near(double(back.uv_rotation), 0.4, 0.0001, "uv_rotation");
	expect_eq(int(back.uv_axis), int(UvAxis::Y), "uv_axis");
	expect_eq(int(back.material_slot), 7, "material_slot");
	expect(back.smooth, "smooth");
	expect(back.uv_unwrapped && back.uv_u == attrs.uv_u && back.uv_v == attrs.uv_v
			&& back.uv_origin == attrs.uv_origin, "unfolded face mapping survives reload");
	expect(loaded.edge_uv_seam(edges.front()), "marked seam survives reload");
	EmitOut before_emit, after_emit;
	emit_arrays(mesh, before_emit);
	emit_arrays(loaded, after_emit);
	expect(before_emit.uvs == after_emit.uvs, "rendered UVs survive serialization exactly");
	std::vector<uint8_t> legacy = bytes;
	legacy[4] = 2;
	legacy.resize(legacy.size() - size_t(mesh.edge_count() * 2) - size_t(mesh.face_count() * 33));
	Mesh legacy_mesh;
	expect(deserialize(legacy, legacy_mesh).ok(), "version two solids still load");
	expect(!legacy_mesh.attrs(top).uv_unwrapped && !legacy_mesh.edge_uv_seam(edges.front()),
			"legacy solids retain automatic projection without marked seams");
}

SLAB_TEST(uv_seam_survives_edge_split_and_reload) {
	Mesh mesh = make_box();
	std::vector<EdgeId> edges;
	mesh.all_edges(edges);
	VertexId a, b;
	mesh.edge_vertices(edges.front(), a, b);
	const IVec3 pa = mesh.position_i(a), pb = mesh.position_i(b);
	MeshEdit edit(mesh);
	edit.set_uv_seam(edges.front(), true);
	const VertexId midpoint = edit.split_edge(edges.front(),
			IVec3{(pa.x + pb.x) / 2, (pa.y + pb.y) / 2, (pa.z + pb.z) / 2});
	expect(midpoint.slot != INVALID_IDX, "split marked edge");
	expect(std::move(edit).commit(mesh).ok(), "marked split commits");
	Mesh loaded;
	expect(deserialize(serialize(mesh), loaded).ok(), "split seam round-trips");
	loaded.all_edges(edges);
	int marked = 0;
	for (const EdgeId edge : edges) if (loaded.edge_uv_seam(edge)) marked++;
	expect_eq(marked, 2, "both child edges retain the seam");
	auto damaged = serialize(mesh);
	damaged.pop_back();
	const auto before = serialize(loaded);
	expect(!deserialize(damaged, loaded).ok(), "truncated UV extension is refused");
	expect(serialize(loaded) == before, "bad UV data leaves target unchanged");
}

SLAB_TEST(serialize_round_trips_a_material_slot_past_255) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 3, 2)).ok(), "box op");
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "box commit");
	const FaceId top = top_face(box);
	FaceAttrs attrs;
	attrs.material_slot = 400;
	MeshEdit painted(box);
	painted.set_attrs(top, attrs);
	Mesh mesh;
	expect(std::move(painted).commit(mesh).ok(), "attrs commit");
	Mesh loaded;
	expect(deserialize(serialize(mesh), loaded).ok(), "deserialize ok");
	expect_eq(int(loaded.attrs(top).material_slot), 400, "slot 400 survives");
}

SLAB_TEST(emit_records_a_material_slot_per_triangle) {
	MeshEdit edit = MeshEdit::empty();
	expect(ops::box(edit, godot::Vector3(2, 3, 2)).ok(), "box op");
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "box commit");
	const FaceId top = top_face(box);
	FaceAttrs attrs;
	attrs.material_slot = 2;
	MeshEdit painted(box);
	painted.set_attrs(top, attrs);
	Mesh mesh;
	expect(std::move(painted).commit(mesh).ok(), "attrs commit");
	EmitOut out;
	emit_arrays(mesh, out);
	expect_eq(int(out.slots.size()), int(out.provenance.size()), "one slot per triangle");
	int painted_tris = 0;
	for (size_t i = 0; i < out.provenance.size(); i++) {
		if (out.provenance[i].slot == top.slot && out.provenance[i].gen == top.gen) {
			expect_eq(int(out.slots[i]), 2, "painted face keeps slot 2");
			painted_tris++;
		} else {
			expect_eq(int(out.slots[i]), 0, "other faces stay on slot 0");
		}
	}
	expect(painted_tris == 2, "top face two triangles");
}

SLAB_TEST(box_vertex_star) {
	const Mesh mesh = make_box();
	std::vector<VertexId> verts;
	mesh.all_vertices(verts);
	expect_eq(int(verts.size()), 8, "eight verts");
	for (const VertexId v : verts) {
		std::vector<EdgeId> ve;
		mesh.vertex_edges(v, ve);
		expect_eq(int(ve.size()), 3, "vertex degree 3");
		std::vector<FaceId> vf;
		mesh.vertex_faces(v, vf);
		expect_eq(int(vf.size()), 3, "vertex faces 3");
		for (const EdgeId e : ve) {
			expect(mesh.alive(e), "star edge alive");
		}
		for (const FaceId f : vf) {
			expect(mesh.alive(f), "star face alive");
		}
	}
}

SLAB_TEST(stale_handles_return_empty) {
	const Mesh mesh = make_box();
	const EdgeId dead_e{};
	const FaceId dead_f{};
	const VertexId dead_v{};
	expect(!mesh.alive(dead_e), "zero edge dead");
	expect(!mesh.alive(dead_f), "zero face dead");
	expect(!mesh.alive(dead_v), "zero vert dead");
	VertexId a;
	VertexId b;
	mesh.edge_vertices(dead_e, a, b);
	expect(!mesh.alive(a) && !mesh.alive(b), "stale edge verts empty");
	FaceId fa;
	FaceId fb;
	mesh.edge_faces(dead_e, fa, fb);
	expect(!mesh.alive(fa) && !mesh.alive(fb), "stale edge faces empty");
	std::vector<EdgeId> edges;
	mesh.face_edges(dead_f, edges);
	expect(edges.empty(), "stale face_edges empty");
	mesh.vertex_edges(dead_v, edges);
	expect(edges.empty(), "stale vertex_edges empty");
	std::vector<FaceId> faces;
	mesh.vertex_faces(dead_v, faces);
	expect(faces.empty(), "stale vertex_faces empty");
	expect(mesh.face_centroid(dead_f) == godot::Vector3(), "stale centroid zero");
	expect_near(mesh.face_area(dead_f), 0.0, 0.0, "stale area zero");
}

SLAB_TEST(deserialize_rejects_bad_magic_and_truncation) {
	const Mesh mesh = make_box();
	const std::vector<uint8_t> bytes = serialize(mesh);

	Mesh target;
	MeshEdit seed = MeshEdit::empty();
	expect(ops::box(seed, godot::Vector3(2, 3, 2)).ok(), "seed box");
	expect(std::move(seed).commit(target).ok(), "seed commit");
	expect_eq(target.face_count(), 6, "seed faces");

	std::vector<uint8_t> bad = bytes;
	bad[0] ^= 0xFF;
	const MeshFault magic_fault = deserialize(bad, target);
	expect(!magic_fault.ok(), "bad magic rejected");
	expect_eq(int(magic_fault.code), int(MeshError::CORRUPT_DATA), "bad magic code");
	expect_eq(target.face_count(), 6, "target untouched after bad magic");

	std::vector<uint8_t> half = bytes;
	half.resize(half.size() / 2);
	const MeshFault trunc_fault = deserialize(half, target);
	expect(!trunc_fault.ok(), "truncated rejected");
	expect_eq(int(trunc_fault.code), int(MeshError::CORRUPT_DATA), "truncated code");
	expect_eq(target.face_count(), 6, "target untouched after truncate");
}
