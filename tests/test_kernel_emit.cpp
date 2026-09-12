#include "harness.hpp"

#include "kernel/emit.hpp"
#include "kernel/mesh_edit.hpp"
#include "kernel/ops/boolean.hpp"
#include "kernel/ops/edit.hpp"
#include "kernel/ops/inset.hpp"
#include "kernel/ops/offset_loop.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/triangulate.hpp"

#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;
using slabtest::expect_near;

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

Mesh shifted(const Mesh &p_src, const godot::Vector3 &p_delta) {
	Mesh mesh = p_src;
	std::vector<VertexId> verts;
	mesh.all_vertices(verts);
	MeshEdit moved(mesh);
	ops::move_vertices(moved, verts, p_delta);
	std::move(moved).commit(mesh);
	return mesh;
}

void fan_loop(int32_t p_corners, std::vector<int32_t> &r_indices) {
	r_indices.clear();
	for (int32_t i = 1; i + 1 < p_corners; i++) {
		r_indices.push_back(0);
		r_indices.push_back(i + 1);
		r_indices.push_back(i);
	}
}

bool point_in_tri(const godot::Vector3 &p_p, const godot::Vector3 &p_a, const godot::Vector3 &p_b, const godot::Vector3 &p_c) {
	const godot::Vector3 u = p_b - p_a;
	const godot::Vector3 v = p_c - p_a;
	const godot::Vector3 n = u.cross(v);
	const float n2 = n.length_squared();
	if (n2 < 1e-16f) {
		return false;
	}
	const float dist = (p_p - p_a).dot(n);
	const float nlen = godot::Math::sqrt(n2);
	if (godot::Math::abs(dist) > 0.02f * nlen) {
		return false;
	}
	const godot::Vector3 w = p_p - p_a;
	const float d00 = u.dot(u);
	const float d01 = u.dot(v);
	const float d11 = v.dot(v);
	const float d20 = w.dot(u);
	const float d21 = w.dot(v);
	const float denom = d00 * d11 - d01 * d01;
	if (godot::Math::abs(denom) < 1e-16f) {
		return false;
	}
	const float tb = (d11 * d20 - d01 * d21) / denom;
	const float tc = (d00 * d21 - d01 * d20) / denom;
	const float ta = 1.0f - tb - tc;
	return ta >= -1e-3f && tb >= -1e-3f && tc >= -1e-3f;
}

bool covers(const std::vector<IVec3> &p_loop, const std::vector<int32_t> &p_indices, const IVec3 &p_p) {
	const godot::Vector3 p = dequantize(p_p);
	for (size_t i = 0; i + 2 < p_indices.size(); i += 3) {
		if (point_in_tri(p, dequantize(p_loop[size_t(p_indices[i])]), dequantize(p_loop[size_t(p_indices[i + 1])]), dequantize(p_loop[size_t(p_indices[i + 2])]))) {
			return true;
		}
	}
	return false;
}

bool covers_pts(const std::vector<godot::Vector3> &p_pts, const std::vector<int32_t> &p_indices, const godot::Vector3 &p_p) {
	for (size_t i = 0; i + 2 < p_indices.size(); i += 3) {
		if (point_in_tri(p_p, p_pts[size_t(p_indices[i])], p_pts[size_t(p_indices[i + 1])], p_pts[size_t(p_indices[i + 2])])) {
			return true;
		}
	}
	return false;
}

bool emit_covers(const EmitOut &p_out, const godot::Vector3 &p_p) {
	for (size_t i = 0; i + 2 < p_out.indices.size(); i += 3) {
		if (point_in_tri(p_p, p_out.verts[size_t(p_out.indices[i])], p_out.verts[size_t(p_out.indices[i + 1])], p_out.verts[size_t(p_out.indices[i + 2])])) {
			return true;
		}
	}
	return false;
}

godot::Vector3 tri_centroid(const godot::Vector3 &p_a, const godot::Vector3 &p_b, const godot::Vector3 &p_c) {
	return (p_a + p_b + p_c) / 3.0f;
}

// U opening +Y: a fan from vertex 0 covers the bay, ear-clip does not.
std::vector<IVec3> concave_u() {
	return {
			IVec3{ 0, 0, 0 },
			IVec3{ 40, 0, 0 },
			IVec3{ 40, 40, 0 },
			IVec3{ 30, 40, 0 },
			IVec3{ 30, 10, 0 },
			IVec3{ 10, 10, 0 },
			IVec3{ 10, 40, 0 },
			IVec3{ 0, 40, 0 },
	};
}

Mesh turbine_hall_with_door() {
	Mesh room = make_box(godot::Vector3(12, 9, 14));
	const FaceId top = top_face(room);
	MeshEdit hollow(room);
	ops::inset(hollow, { top }, 0.45f);
	ops::extrude(hollow, { top }, -8.55f);
	std::move(hollow).commit(room);
	const Mesh cutter = shifted(make_box(godot::Vector3(1.6f, 3, 2)), godot::Vector3(-0.5f, 0.45f, 6));
	MeshEdit cut(room);
	ops::boolean(cut, cutter, 1);
	std::move(cut).commit(room);
	return room;
}

} // namespace

SLAB_TEST(ear_clip_leaves_the_bay_of_a_concave_u_uncovered) {
	const std::vector<IVec3> loop = concave_u();
	const IVec3 bay{ 20, 25, 0 };
	const IVec3 floor{ 20, 5, 0 };
	const IVec3 left_arm{ 5, 20, 0 };

	std::vector<int32_t> fan;
	fan_loop(int32_t(loop.size()), fan);
	expect(covers(loop, fan, bay), "a fan from vertex 0 covers the U bay");
	expect(covers(loop, fan, floor), "a fan still covers the U floor");

	std::vector<int32_t> ears;
	triangulate_loop(loop, ears);
	expect_eq(int(ears.size() / 3), 6, "an octagon becomes six triangles");
	expect(!covers(loop, ears, bay), "ear-clip must not cover the U bay");
	expect(covers(loop, ears, floor), "ear-clip still covers the U floor");
	expect(covers(loop, ears, left_arm), "ear-clip still covers the left arm");
}

SLAB_TEST(emit_of_a_concave_face_keeps_per_corner_attributes) {
	MeshEdit edit = MeshEdit::empty();
	ops::box(edit, godot::Vector3(2, 3, 2));
	Mesh box;
	expect(std::move(edit).commit(box).ok(), "box commit");
	const FaceId top = top_face(box);
	FaceAttrs painted;
	painted.material_slot = 4;
	painted.uv_scale = godot::Vector2(2, 2);
	MeshEdit tagged(box);
	tagged.set_attrs(top, painted);
	expect(std::move(tagged).commit(box).ok(), "attrs commit");

	EmitOut out;
	emit_arrays(box, out);
	expect_eq(int(out.verts.size()), 24, "one emit vert per corner");
	expect_eq(int(out.uvs.size()), int(out.verts.size()), "uv per corner");
	expect_eq(int(out.normals.size()), int(out.verts.size()), "normal per corner");
	int painted_tris = 0;
	for (size_t t = 0; t < out.provenance.size(); t++) {
		if (out.provenance[t].slot != top.slot || out.provenance[t].gen != top.gen) {
			continue;
		}
		expect_eq(int(out.slots[t]), 4, "painted slot rides the triangle");
		for (int k = 0; k < 3; k++) {
			const int32_t vi = out.indices[t * 3 + size_t(k)];
			expect(out.normals[size_t(vi)].y > 0.9f, "top triangle keeps the face normal");
		}
		painted_tris++;
	}
	expect_eq(painted_tris, 2, "convex top stays two triangles");
}

SLAB_TEST(emit_of_the_hall_doorway_does_not_span_the_opening) {
	const Mesh hall = turbine_hall_with_door();
	expect(validate(hall).ok(), "hall doorway stays an embedded solid");
	expect_eq(hall.face_count(), 40, "saved Subtract applied 40 faces");
	expect_near(hall.signed_volume(), 266.15, 0.05, "doorway volume after the 1.6x3x2 cutter");

	int corners = 0;
	int concave = 0;
	std::vector<FaceId> faces;
	hall.all_faces(faces);
	for (const FaceId id : faces) {
		std::vector<VertexId> loop;
		hall.face_corners(id, loop);
		corners += int(loop.size());
		if (loop.size() > 4) {
			concave++;
		}
	}
	expect(concave > 0, "the doorway leaves at least one n-gon");

	EmitOut out;
	emit_arrays(hall, out);
	expect_eq(int(out.verts.size()), corners, "emit keeps one row per corner");
	expect_eq(int(out.uvs.size()), corners, "uv per corner");
	expect_eq(int(out.normals.size()), corners, "normal per corner");
	expect_eq(int(out.slots.size()), int(out.provenance.size()), "material slot per triangle");
	expect_eq(int(out.indices.size()), int(out.provenance.size()) * 3, "collision soup uses the same triples");

	int32_t cursor = 0;
	int exterior_fan_centroids = 0;
	const godot::Vector3 outer_hole(0.0f, 1.95f, 7.0f);
	const godot::Vector3 inner_hole(0.45f, 1.95f, 7.0f);
	const godot::Vector3 throat(0.225f, 1.95f, 7.0f);
	for (const FaceId id : faces) {
		std::vector<VertexId> ids;
		hall.face_corners(id, ids);
		std::vector<IVec3> loop;
		std::vector<godot::Vector3> pts;
		loop.reserve(ids.size());
		pts.reserve(ids.size());
		for (const VertexId v : ids) {
			loop.push_back(hall.position_i(v));
			pts.push_back(hall.position(v));
		}
		std::vector<int32_t> ears;
		triangulate_loop(loop, ears);
		int face_tris = 0;
		for (size_t t = 0; t < out.provenance.size(); t++) {
			if (out.provenance[t].slot != id.slot || out.provenance[t].gen != id.gen) {
				continue;
			}
			face_tris++;
			godot::Vector3 tri_n;
			for (int k = 0; k < 3; k++) {
				const int32_t vi = out.indices[t * 3 + size_t(k)];
				expect(vi >= cursor && vi < cursor + int32_t(ids.size()), "triangle indexes that face's corners");
				expect_eq(int(out.slots[t]), int(hall.attrs(id).material_slot), "material slot stays on the triangle");
				if (k == 0) {
					tri_n = out.normals[size_t(vi)];
				} else {
					expect_near(double(out.normals[size_t(vi)].dot(tri_n)), 1.0, 0.001, "the three corners share one face normal");
				}
			}
		}
		expect_eq(face_tris, int(ears.size() / 3), "emit triangles match ear-clip");
		std::vector<int32_t> fan;
		fan_loop(int32_t(loop.size()), fan);
		for (size_t i = 0; i + 2 < fan.size(); i += 3) {
			const godot::Vector3 c = tri_centroid(pts[size_t(fan[i])], pts[size_t(fan[i + 1])], pts[size_t(fan[i + 2])]);
			if (!covers_pts(pts, fan, c) || covers_pts(pts, ears, c)) {
				continue;
			}
			exterior_fan_centroids++;
			bool this_face_covers = false;
			for (size_t t = 0; t < out.provenance.size(); t++) {
				if (out.provenance[t].slot != id.slot || out.provenance[t].gen != id.gen) {
					continue;
				}
				if (point_in_tri(c, out.verts[size_t(out.indices[t * 3])], out.verts[size_t(out.indices[t * 3 + 1])], out.verts[size_t(out.indices[t * 3 + 2])])) {
					this_face_covers = true;
					break;
				}
			}
			expect(!this_face_covers, "this face's ear-clip must not cover its own exterior");
		}
		cursor += int32_t(ids.size());
	}
	expect(exterior_fan_centroids > 0, "a fan from vertex 0 of this doorway covers exterior");
	expect(!emit_covers(out, outer_hole), "outer door plane is not covered");
	expect(!emit_covers(out, inner_hole), "inner door plane is not covered");
	expect(!emit_covers(out, throat), "the door throat is not covered");
}
