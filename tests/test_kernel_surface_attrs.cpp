#include "harness.hpp"
#include "kernel/surface_attrs_interpolate.hpp"
#include "kernel/mesh_edit.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/ops/offset_loop.hpp"
#include "kernel/ops/region.hpp"
#include "kernel/serialize.hpp"
#include "kernel/emit.hpp"
#include <limits>
using namespace slab;
using slabtest::expect;
using slabtest::expect_near;

SLAB_TEST(surface_attributes_interpolate_without_losing_deformation) {
	SurfaceAttrs a, b;
	a.flags = b.flags = SurfaceAttrs::UV2 | SurfaceAttrs::COLOR | SurfaceAttrs::NORMAL | SurfaceAttrs::SKIN;
	a.uv2 = godot::Vector2(0, 0); b.uv2 = godot::Vector2(1, 1);
	a.color = godot::Color(1, 0, 0); b.color = godot::Color(0, 0, 1);
	a.normal = b.normal = godot::Vector3(0, 1, 0);
	a.bones[0] = 2; a.weights[0] = 1;
	b.bones[0] = 7; b.weights[0] = 1;
	a.morphs.resize(1); b.morphs.resize(1);
	a.morphs[0].position = godot::Vector3(0, 1, 0);
	b.morphs[0].position = godot::Vector3(0, 3, 0);
	const auto result = lerp_surface_attrs(a, b, 0.25);
	expect_near(result.uv2.x, 0.25, 0.00001, "UV2 interpolates");
	expect_near(result.color.r, 0.75, 0.00001, "linear vertex color interpolates");
	expect_near(result.normal.length(), 1, 0.00001, "authored normal remains normalized");
	expect(result.bones[0] == 2 && result.bones[1] == 7, "bone identities merge by influence");
	expect_near(result.weights[0], 0.75, 0.00001, "first skin weight interpolates");
	expect_near(result.weights[1], 0.25, 0.00001, "second skin weight interpolates");
	expect_near(result.morphs[0].position.y, 1.5, 0.00001, "relative morph delta interpolates");
	SurfaceAttrs corners[] = {a, b};
	double invalid[] = {1, -1};
	SurfaceAttrs untouched = a;
	expect(!interpolate_surface_attrs(corners, invalid, 2, untouched), "negative barycentric weights refuse");
	expect(untouched.bones[0] == 2 && untouched.morphs[0].position.y == 1, "failure leaves destination unchanged");
}

SLAB_TEST(surface_skin_interpolation_keeps_strongest_eight_normalized) {
	SurfaceAttrs corners[3];
	for (int i = 0; i < 3; ++i) {
		corners[i].flags = SurfaceAttrs::SKIN;
		for (int k = 0; k < 8; ++k) {
			corners[i].bones[k] = i * 8 + k;
			corners[i].weights[k] = 0.125f;
		}
	}
	const double weights[] = {0.2, 0.3, 0.5};
	SurfaceAttrs output;
	expect(interpolate_surface_attrs(corners, weights, 3, output), "barycentric skin interpolation succeeds");
	float sum = 0;
	for (int i = 0; i < 8; ++i) {
		expect(output.bones[i] == 16 + i, "highest influences retained deterministically");
		sum += output.weights[i];
	}
	expect_near(sum, 1, 0.00001, "retained skin weights renormalize");
}

SLAB_TEST(surface_attributes_survive_mesh_serialization_and_edge_split) {
	MeshEdit create = MeshEdit::empty();
	expect(ops::box(create, godot::Vector3(2, 2, 2)).ok(), "attribute fixture builds");
	Mesh mesh;
	expect(std::move(create).commit(mesh).ok(), "attribute fixture commits");
	std::vector<FaceId> faces;
	mesh.all_faces(faces);
	MeshEdit edit(mesh);
	for (uint32_t i = 0; i < 4; ++i) {
		CornerAttrs a;
		a.surface.flags = 31;
		a.surface.uv2 = godot::Vector2(float(i), float(i*i));
		a.surface.color = godot::Color(.2f * i, .3f, .4f, 1);
		a.surface.normal = mesh.face_normal(faces[0]);
		a.surface.bones[0] = int(i);
		a.surface.weights[0] = 1;
		a.surface.morphs.resize(1);
		a.surface.morphs[0].position = godot::Vector3(0, float(i), 0);
		edit.set_corner_attrs(faces[0], i, a);
	}
	expect(std::move(edit).commit(mesh).ok(), "all surface channels commit");
	EmitOut emitted;
	emit_arrays(mesh, emitted);
	expect(emitted.surface.size() == emitted.verts.size(), "emission retains attributes for each render vertex");
	expect(emitted.surface[0].flags == 31 && emitted.surface[0].morphs.size() == 1, "emission retains skin and morph channels");
	const auto bytes = serialize(mesh);
	expect(bytes[4] == 6, "extended data uses version six");
	Mesh loaded;
	expect(deserialize(bytes, loaded).ok(), "extended mesh loads");
	expect(serialize(loaded) == bytes, "surface channels round trip byte exactly");
	std::vector<EdgeId> edges;
	std::vector<VertexId> vertices;
	loaded.face_edges(faces[0], edges);
	loaded.face_corners(faces[0], vertices);
	const IVec3 a = loaded.position_i(vertices[0]), b = loaded.position_i(vertices[1]);
	MeshEdit split(loaded);
	const VertexId midpoint = split.split_edge(edges[0], {(a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2});
	expect(std::move(split).commit(loaded).ok(), "surface edge split commits");
	loaded.face_corners(faces[0], vertices);
	std::vector<CornerAttrs> corners;
	loaded.face_corner_attrs(faces[0], corners);
	bool found = false;
	for (size_t i = 0; i < vertices.size(); ++i) {
		if (vertices[i].slot != midpoint.slot) continue;
		found = true;
		const SurfaceAttrs &value = corners[i].surface;
		expect_near(value.uv2.x, .5, .00001, "edge split interpolates UV2");
		expect_near(value.weights[0], .5, .00001, "edge split interpolates skin weights");
		expect_near(value.morphs[0].position.y, .5, .00001, "edge split interpolates morph delta");
	}
	expect(found, "split result contains attributed midpoint");
	const auto before = serialize(loaded);
	auto corrupt = bytes;
	corrupt.pop_back();
	expect(deserialize(corrupt, loaded).code == MeshError::CORRUPT_DATA, "truncated extension is refused");
	expect(serialize(loaded) == before, "bad extension leaves live mesh unchanged");
	MeshEdit invalid(loaded);
	CornerAttrs bad;
	bad.surface.flags = SurfaceAttrs::SKIN;
	invalid.set_corner_attrs(faces[0], 0, bad);
	expect(!std::move(invalid).commit(loaded).ok(), "zero total skin weight is refused");
	expect(serialize(loaded) == before, "bad skin weights cannot mutate live data");
}

SLAB_TEST(extrusion_carries_deformation_to_new_wall_vertices) {
	for (const bool region : {false, true}) {
		MeshEdit create = MeshEdit::empty();
		ops::box(create, godot::Vector3(2, 2, 2));
		Mesh mesh;
		expect(std::move(create).commit(mesh).ok(), "extrusion attribute fixture commits");
		std::vector<FaceId> faces;
		mesh.all_faces(faces);
		const FaceId cap = faces[0];
		MeshEdit mark(mesh);
		for (uint32_t i = 0; i < 4; ++i) {
			CornerAttrs corner;
			corner.surface.flags = SurfaceAttrs::SKIN | SurfaceAttrs::COLOR | SurfaceAttrs::UV2;
			corner.surface.bones[0] = 3;
			corner.surface.weights[0] = 1;
			corner.surface.color = godot::Color(.4f, .6f, .8f);
			corner.surface.uv2 = godot::Vector2(float(i), .5f);
			corner.surface.morphs.resize(1);
			corner.surface.morphs[0].position = godot::Vector3(.25f, 0, 0);
			mark.set_corner_attrs(cap, i, corner);
		}
		expect(std::move(mark).commit(mesh).ok(), "source cap attributes commit");
		MeshEdit extrude(mesh);
		const MeshFault operation = region ? ops::extrude_region(extrude, {cap}, .5f) : ops::extrude(extrude, {cap}, .5f);
		expect(operation.ok(), "attributed extrusion succeeds");
		expect(std::move(extrude).commit(mesh).ok(), "attributed extrusion commits");
		mesh.all_faces(faces);
		int influenced = 0;
		for (FaceId face : faces) {
			std::vector<CornerAttrs> corners;
			mesh.face_corner_attrs(face, corners);
			for (const CornerAttrs &corner : corners) {
				if (!(corner.surface.flags & SurfaceAttrs::SKIN)) continue;
				++influenced;
				expect(corner.surface.bones[0] == 3 && corner.surface.weights[0] == 1, "cap and wall retain bone binding");
				expect(corner.surface.morphs.size() == 1 && corner.surface.morphs[0].position.x == .25f, "cap and wall retain morph delta");
			}
		}
		expect(influenced == 20, "four cap and sixteen wall corners carry deformation");
		Mesh reloaded;
		expect(deserialize(serialize(mesh), reloaded).ok(), "extruded attributes survive reload");
	}
}

#include "kernel/ops/bevel.hpp"
#include "kernel/ops/boolean.hpp"
#include "kernel/ops/plane_cut.hpp"

namespace {
Mesh attributed_box() {
	MeshEdit create = MeshEdit::empty();
	expect(ops::box(create, godot::Vector3(2, 2, 2)).ok(), "rebuild fixture box");
	std::vector<FaceId> faces;
	create.scratch().all_faces(faces);
	for (auto f : faces) {
		auto attrs = create.scratch().attrs(f);
		attrs.material_slot = 3;
		create.set_attrs(f, attrs);
		std::vector<VertexId> vertices;
		create.scratch().face_corners(f, vertices);
		for (uint32_t k = 0; k < vertices.size(); ++k) {
			const auto p = dequantize(create.scratch().position_i(vertices[k]));
			CornerAttrs c;
			c.uv_explicit = true;
			c.uv = godot::Vector2(p.x, p.y);
			c.uv_pinned = true;
			c.surface.flags = SurfaceAttrs::UV2 | SurfaceAttrs::COLOR | SurfaceAttrs::SKIN;
			c.surface.uv2 = godot::Vector2(p.x, p.z);
			c.surface.color = godot::Color((p.x + 1) / 2, .4, .7, 1);
			c.surface.bones[0] = 4;
			c.surface.weights[0] = 1;
			c.surface.morphs.resize(1);
			c.surface.morphs[0].position = godot::Vector3(.2, 0, 0);
			create.set_corner_attrs(f, k, c);
		}
	}
	std::vector<EdgeId> edges;
	create.scratch().all_edges(edges);
	for (auto e : edges) {
		create.set_hard_edge(e, true);
		create.set_uv_seam(e, true);
	}
	Mesh out;
	expect(std::move(create).commit(out).ok(), "attributed box commits");
	return out;
}
void check_deformation(const Mesh &mesh) {
	std::vector<FaceId> faces;
	mesh.all_faces(faces);
	for (auto f : faces) {
		std::vector<CornerAttrs> corners;
		mesh.face_corner_attrs(f, corners);
		for (const auto &c : corners) {
			expect(c.surface.flags & SurfaceAttrs::SKIN, "rebuilt corner keeps skin");
			expect(c.surface.bones[0] == 4, "rebuilt corner keeps bone identity");
			expect_near(c.surface.weights[0], 1, .00001, "rebuilt skin normalized");
			expect(c.surface.morphs.size() == 1, "rebuilt corner keeps morph channel");
			if (!c.surface.morphs.empty())
				expect_near(c.surface.morphs[0].position.x, .2, .00001, "rebuilt morph delta preserved");
		}
	}
	Mesh loaded;
	expect(deserialize(serialize(mesh), loaded).ok(), "rebuilt attrs reload");
	expect(serialize(loaded) == serialize(mesh), "rebuilt attributes roundtrip exactly");
}
} // namespace
SLAB_TEST(plane_cut_preserves_interpolated_surface_and_split_hard_edges) {
	const Mesh source = attributed_box();
	MeshEdit cut(source);
	FaceAttrs cap;
	cap.material_slot = 7;
	expect(ops::plane_cut(cut, {LATTICE, 0, 0}, {1, 0, 0}, ops::PlaneSide::POSITIVE, cap).ok(),
		   "attributed plane cut succeeds");
	Mesh result;
	expect(std::move(cut).commit(result).ok(), "attributed plane cut commits");
	check_deformation(result);
	std::vector<FaceId> faces;
	result.all_faces(faces);
	int caps = 0;
	for (auto f : faces) {
		std::vector<VertexId> vertices;
		std::vector<CornerAttrs> attrs;
		result.face_corners(f, vertices);
		result.face_corner_attrs(f, attrs);
		if (result.attrs(f).material_slot == 7) {
			++caps;
			continue;
		}
		expect(result.attrs(f).material_slot == 3, "retained face material preserved");
		for (size_t i = 0; i < vertices.size(); ++i) {
			const auto p = dequantize(result.position_i(vertices[i]));
			expect_near(attrs[i].surface.uv2.x, p.x, .00001, "cut UV2 uses geometric interpolation");
			expect_near(attrs[i].surface.color.r, (p.x + 1) / 2, .00001, "cut colour interpolates");
			expect_near(attrs[i].uv.x, p.x, .00001, "cut UV placement retained");
			expect(attrs[i].uv_pinned == (p.x != 1), "new cut corners do not acquire pins");
		}
	}
	expect(caps == 1, "cut keeps requested cap material");
	std::vector<EdgeId> edges;
	result.all_edges(edges);
	int hard = 0;
	for (auto e : edges)
		if (result.edge_hard(e)) {
			++hard;
			expect(result.edge_uv_seam(e), "split seam retained with hardness");
		}
	expect(hard >= 8, "surviving and shortened hard edges retained");
}
SLAB_TEST(bevel_preserves_surface_channels_on_retained_faces_and_new_bands) {
	const Mesh source = attributed_box();
	std::vector<EdgeId> edges;
	source.all_edges(edges);
	MeshEdit edit(source);
	expect(ops::bevel(edit, {edges[0]}, .2f, 3).ok(), "attributed segmented bevel succeeds");
	Mesh result;
	expect(std::move(edit).commit(result).ok(), "attributed bevel commits");
	check_deformation(result);
	std::vector<FaceId> faces;
	result.all_faces(faces);
	for (auto f : faces)
		expect(result.attrs(f).material_slot == 3, "bevel retains source material");
}
SLAB_TEST(boolean_preserves_host_and_cutter_surface_channels) {
	Mesh host = attributed_box(), other = attributed_box();
	MeshEdit moved(other);
	std::vector<VertexId> vertices;
	other.all_vertices(vertices);
	for (auto v : vertices) {
		auto p = other.position_i(v);
		p.x += LATTICE;
		moved.move_vertex(v, p);
	}
	expect(std::move(moved).commit(other).ok(), "offset attributed Boolean operand");
	MeshEdit edit(host);
	expect(ops::boolean(edit, other, 0).ok(), "attributed Boolean union succeeds");
	Mesh result;
	expect(std::move(edit).commit(result).ok(), "attributed Boolean union commits");
	check_deformation(result);
	std::vector<FaceId> faces;
	result.all_faces(faces);
	for (auto f : faces)
		expect(result.attrs(f).material_slot == 3, "Boolean preserves material assignments");
}

SLAB_TEST(boolean_keeps_coplanar_operand_material_boundaries) {
	Mesh host = attributed_box(), other = attributed_box();
	MeshEdit operand(other);
	std::vector<VertexId> vertices;
	other.all_vertices(vertices);
	for (auto v : vertices) {
		auto p = other.position_i(v); p.x += LATTICE;
		operand.move_vertex(v, p);
	}
	std::vector<FaceId> faces;
	other.all_faces(faces);
	for (auto f : faces) { auto attrs = other.attrs(f); attrs.material_slot = 9; operand.set_attrs(f, attrs); }
	expect(std::move(operand).commit(other).ok(), "distinct material cutter commits");
	MeshEdit edit(host);
	expect(ops::boolean(edit, other, 0).ok(), "distinct material union succeeds");
	Mesh result;
	expect(std::move(edit).commit(result).ok(), "distinct material union commits");
	result.all_faces(faces);
	int host_faces = 0, cutter_faces = 0;
	for (auto f : faces) {
		std::vector<VertexId> corners; result.face_corners(f, corners);
		double x = 0; for (auto v : corners) x += result.position(v).x;
		x /= corners.size();
		if (x > 2.0001) { ++cutter_faces; expect(result.attrs(f).material_slot == 9, "exposed cutter face keeps material"); }
		else { ++host_faces; expect(result.attrs(f).material_slot == 3, "host and coplanar overlap keep host material"); }
	}
	expect(host_faces > 0 && cutter_faces > 0, "both material regions survive");
}

SLAB_TEST(contained_subtract_reverses_authored_shading_and_preserves_deformation) {
	Mesh inner = attributed_box();
	MeshEdit authored(inner);
	std::vector<VertexId> inner_vertices; inner.all_vertices(inner_vertices);
	for (auto vertex : inner_vertices) {
		auto p = inner.position_i(vertex); p.x += LATTICE; p.y += LATTICE; p.z += LATTICE;
		authored.move_vertex(vertex, p);
	}
	std::vector<FaceId> faces; inner.all_faces(faces);
	for (auto f : faces) {
		std::vector<CornerAttrs> corners; inner.face_corner_attrs(f, corners);
		for (uint32_t k=0; k<corners.size(); ++k) {
			auto c = corners[k];
			c.surface.flags |= SurfaceAttrs::NORMAL | SurfaceAttrs::TANGENT;
			c.surface.normal = inner.face_normal(f);
			c.surface.morphs[0].normal = inner.face_normal(f) * .1;
			c.surface.morphs[0].tangent_w = .25;
			authored.set_corner_attrs(f, k, c);
		}
	}
	expect(std::move(authored).commit(inner).ok(), "authored cutter normals commit");
	MeshEdit outer = MeshEdit::empty();
	expect(ops::box(outer, godot::Vector3(4,4,4)).ok(), "outer solid builds");
	expect(ops::boolean(outer, inner, 1).ok(), "contained subtract succeeds");
	Mesh result; expect(std::move(outer).commit(result).ok(), "contained subtract commits");
	result.all_faces(faces); int inside = 0;
	for (auto f : faces) {
		if(result.attrs(f).material_slot != 3) continue;
		++inside;
		std::vector<CornerAttrs> corners; result.face_corner_attrs(f, corners);
		for(const auto &c : corners) {
			expect_near(c.surface.normal.dot(result.face_normal(f)), 1, .00001, "cavity authored normal follows reversed geometry");
			expect_near(c.surface.tangent[3], -1, .00001, "cavity tangent handedness reversed");
			expect_near(c.surface.morphs[0].normal.dot(result.face_normal(f)), .1, .00001, "morph normal delta reversed");
			expect_near(c.surface.morphs[0].tangent_w, -.25, .00001, "morph handedness delta reversed");
			expect_near(c.surface.morphs[0].position.x, .2, .00001, "morph position unchanged");
		}
	}
	expect(inside == 6, "all inner shell faces retained");
}

SLAB_TEST(plane_cut_retains_uv_placement_values_and_texture_position) {
	Mesh source = attributed_box();
	MeshEdit placed(source);
	std::vector<FaceId> old_faces; source.all_faces(old_faces);
	for (auto face : old_faces) {
		auto attrs = source.attrs(face);
		attrs.uv_scale = godot::Vector2(2.5, .75);
		attrs.uv_offset = godot::Vector2(.125, .375);
		attrs.uv_rotation = .5;
		placed.set_attrs(face, attrs);
	}
	expect(std::move(placed).commit(source).ok(), "placed texture fixture commits");
	MeshEdit cut(source); FaceAttrs cap; cap.material_slot = 7;
	expect(ops::plane_cut(cut, {LATTICE,0,0}, {1,0,0}, ops::PlaneSide::POSITIVE, cap).ok(), "placed texture cut succeeds");
	Mesh result; expect(std::move(cut).commit(result).ok(), "placed texture cut commits");
	std::vector<FaceId> faces; result.all_faces(faces);
	for (auto face : faces) {
		if (result.attrs(face).material_slot == 7) continue;
		const auto attrs = result.attrs(face);
		expect_near(attrs.uv_scale.x, 2.5, .00001, "cut keeps placement scale control");
		expect_near(attrs.uv_offset.y, .375, .00001, "cut keeps placement offset control");
		expect_near(attrs.uv_rotation, .5, .00001, "cut keeps rotation control");
		std::vector<VertexId> corners; result.face_corners(face, corners);
		std::vector<godot::Vector2> uvs; face_uv_points(result, face, uvs);
		for(auto old_face : old_faces) {
			if (source.face_normal(old_face).dot(result.face_normal(face)) < .9999) continue;
			for(size_t k=0; k<corners.size(); ++k) {
				godot::Vector2 expected;
				expect(face_uv_at_point(source, old_face, result.position(corners[k]), expected), "cut corner samples original mapping");
				expect_near(uvs[k].x, expected.x, .00001, "cut keeps visual texture U");
				expect_near(uvs[k].y, expected.y, .00001, "cut keeps visual texture V");
			}
		}
	}
}
