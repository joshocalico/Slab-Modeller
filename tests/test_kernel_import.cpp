#include "harness.hpp"

#include "kernel/emit.hpp"
#include "kernel/mesh_edit.hpp"
#include "kernel/ops/import.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/quantize.hpp"

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
