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
