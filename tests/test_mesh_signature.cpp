#include "harness.hpp"
#include "mesh_signature.hpp"
#include "kernel/mesh_edit.hpp"
#include "kernel/ops/primitives.hpp"

using namespace slab;

SLAB_TEST(mesh_signature_tracks_faces_and_attributes_without_handle_order) {
	MeshEdit initial = MeshEdit::empty();
	slabtest::expect(ops::box(initial, godot::Vector3(2, 3, 4)).ok(), "make signature fixture");
	Mesh source;
	slabtest::expect(std::move(initial).commit(source).ok(), "commit signature fixture");
	const auto baseline = slabtest::mesh_signature(source);
	std::vector<FaceId> faces;
	source.all_faces(faces);
	std::vector<std::vector<IVec3>> loops;
	for (const FaceId face : faces) {
		std::vector<VertexId> corners;
		source.face_corners(face, corners);
		std::vector<IVec3> loop;
		for (const VertexId vertex : corners) loop.push_back(source.position_i(vertex));
		std::rotate(loop.begin(), loop.begin() + 1, loop.end());
		loops.push_back(loop);
	}
	std::reverse(loops.begin(), loops.end());
	MeshEdit reordered = MeshEdit::empty();
	slabtest::expect(reordered.assemble(loops).ok(), "reassemble reordered source loops");
	Mesh equivalent;
	slabtest::expect(std::move(reordered).commit(equivalent).ok(), "commit reordered fixture");
	slabtest::expect(baseline == slabtest::mesh_signature(equivalent), "face order and cyclic loop starts do not change signature");

	MeshEdit divided(source);
	std::vector<VertexId> corners;
	source.face_corners(faces.front(), corners);
	divided.split_face(faces.front(), corners[0], corners[2]);
	Mesh triangulated;
	slabtest::expect(std::move(divided).commit(triangulated).ok(), "commit changed face connectivity");
	slabtest::expect(source.vertex_count() == triangulated.vertex_count(), "connectivity fixture retains the original vertex set");
	slabtest::expect(baseline != slabtest::mesh_signature(triangulated), "signature catches changed face connectivity despite equal vertices");

	MeshEdit painted(source);
	FaceAttrs attrs = source.attrs(faces.front());
	attrs.uv_unwrapped = true;
	attrs.uv_u = godot::Vector3(0.5f, 0.25f, 0.125f);
	attrs.uv_v = godot::Vector3(0.0f, 0.75f, 0.5f);
	attrs.uv_origin = godot::Vector2(0.125f, 0.25f);
	painted.set_attrs(faces.front(), attrs);
	Mesh changed_uv;
	slabtest::expect(std::move(painted).commit(changed_uv).ok(), "commit changed unfolded mapping");
	slabtest::expect(baseline != slabtest::mesh_signature(changed_uv), "signature includes unfolded UV covectors and origin");
}
