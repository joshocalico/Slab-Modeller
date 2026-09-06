#include "harness.hpp"

#include "kernel/mesh_edit.hpp"
#include "kernel/ops/boolean.hpp"
#include "kernel/ops/edit.hpp"
#include "kernel/ops/primitives.hpp"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <vector>

using namespace slab;
using slabtest::expect;
using slabtest::expect_eq;

static Mesh make_box(const godot::Vector3 &p_size) {
	MeshEdit edit = MeshEdit::empty();
	ops::box(edit, p_size);
	Mesh mesh;
	std::move(edit).commit(mesh);
	return mesh;
}

static Mesh shifted(const Mesh &p_src, const godot::Vector3 &p_delta) {
	Mesh mesh = p_src;
	std::vector<VertexId> verts;
	mesh.all_vertices(verts);
	MeshEdit moved(mesh);
	ops::move_vertices(moved, verts, p_delta);
	std::move(moved).commit(mesh);
	return mesh;
}

static Mesh make_arch(float p_span, float p_depth, int p_segments, float p_thickness, double p_arc) {
	MeshEdit edit = MeshEdit::empty();
	ops::arch(edit, p_span, p_depth, p_segments, p_thickness, p_arc);
	Mesh mesh;
	std::move(edit).commit(mesh);
	return mesh;
}

static IVec3 sub3(const IVec3 &p_a, const IVec3 &p_b) {
	return IVec3{ p_a.x - p_b.x, p_a.y - p_b.y, p_a.z - p_b.z };
}

static bool collinear_between(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c) {
	const IVec3 ab = sub3(p_b, p_a);
	const IVec3 bc = sub3(p_c, p_b);
	const int64_t cx = int64_t(ab.y) * bc.z - int64_t(ab.z) * bc.y;
	const int64_t cy = int64_t(ab.z) * bc.x - int64_t(ab.x) * bc.z;
	const int64_t cz = int64_t(ab.x) * bc.y - int64_t(ab.y) * bc.x;
	if (cx != 0 || cy != 0 || cz != 0) {
		return false;
	}
	const int64_t d = int64_t(ab.x) * bc.x + int64_t(ab.y) * bc.y + int64_t(ab.z) * bc.z;
	return d > 0;
}

struct Topo {
	int euler = 0;
	int slivers = 0;
	int t_juncs = 0;
	int coplanar = 0;
	int ngons = 0;
	int faces = 0;
	bool watertight = false;
};

static Topo measure(const Mesh &p_mesh) {
	Topo t;
	t.faces = p_mesh.face_count();
	t.euler = p_mesh.vertex_count() - p_mesh.edge_count() + p_mesh.face_count();
	t.watertight = validate(p_mesh).ok();

	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	std::vector<VertexId> corners;
	for (const FaceId id : faces) {
		p_mesh.face_corners(id, corners);
		const int n = int(corners.size());
		if (n > 4) {
			t.ngons++;
		}
		for (int i = 0; i < n; i++) {
			if (collinear_between(p_mesh.position_i(corners[(i + n - 1) % n]), p_mesh.position_i(corners[i]),
						p_mesh.position_i(corners[(i + 1) % n]))) {
				t.t_juncs++;
			}
		}
		const double a = p_mesh.face_area(id);
		double longest = 0;
		for (int i = 0; i < n; i++) {
			const double len = double((p_mesh.position(corners[i]) - p_mesh.position(corners[(i + 1) % n])).length());
			longest = std::max(longest, len);
		}
		const double height = longest > 0 ? (2.0 * a / longest) : 0;
		if (a > 0 && (height < 0.02 || (longest > 0 && height / longest < 0.03))) {
			t.slivers++;
		}
	}

	std::vector<EdgeId> edges;
	p_mesh.all_edges(edges);
	FaceId fa;
	FaceId fb;
	for (const EdgeId id : edges) {
		p_mesh.edge_faces(id, fa, fb);
		if (!p_mesh.alive(fa) || !p_mesh.alive(fb)) {
			continue;
		}
		if (p_mesh.face_normal(fa).dot(p_mesh.face_normal(fb)) > 0.999f) {
			t.coplanar++;
		}
	}
	return t;
}

static int cost(const Topo &p_u, const Topo &p_d) {
	int n = 0;
	if (p_u.euler != 2) {
		n += 10000;
	}
	if (p_d.euler != 2) {
		n += 10000;
	}
	n += 50 * p_d.slivers;
	n += 10 * p_d.t_juncs;
	n += p_d.coplanar;
	return n;
}

static void print_case(const char *p_name, const Topo &p_t) {
	if (std::getenv("SLAB_TOPO") == nullptr) {
		return;
	}
	std::printf("CASE %s euler=%d slivers=%d t_juncs=%d coplanar=%d ngons=%d faces=%d watertight=%d\n", p_name, p_t.euler,
			p_t.slivers, p_t.t_juncs, p_t.coplanar, p_t.ngons, p_t.faces, p_t.watertight ? 1 : 0);
}

SLAB_TEST(topo_measure) {
	const Mesh box = make_box(godot::Vector3(4, 2.2f, 4));
	expect(validate(box).ok(), "box watertight");
	print_case("box", measure(box));

	const Mesh arch = make_arch(4.0f, 4.0f, 12, 0.4f, Math_PI);
	expect(validate(arch).ok(), "arch watertight");
	print_case("arch", measure(arch));

	MeshEdit overlap_join(make_box(godot::Vector3(2, 3, 2)));
	expect(ops::boolean(overlap_join, shifted(make_box(godot::Vector3(2, 3, 2)), godot::Vector3(1, 0, 0)), 0).ok(),
			"overlap union");
	Mesh overlap;
	expect(std::move(overlap_join).commit(overlap).ok(), "overlap commit");
	expect(validate(overlap).ok(), "overlap watertight");
	print_case("boxes_overlap", measure(overlap));

	const Mesh roof = shifted(arch, godot::Vector3(0, 2.05f, 0));
	MeshEdit joined(box);
	expect(ops::boolean(joined, roof, 0).ok(), "house union");
	Mesh house;
	expect(std::move(joined).commit(house).ok(), "house union commit");
	expect(validate(house).ok(), "house union watertight");
	const Topo union_topo = measure(house);
	print_case("house_union", union_topo);

	const Mesh door = shifted(make_box(godot::Vector3(0.9f, 1.6f, 1.2f)), godot::Vector3(1.55f, 0.0f, -0.2f));
	MeshEdit cut(house);
	expect(ops::boolean(cut, door, 1).ok(), "house door");
	expect(std::move(cut).commit(house).ok(), "house door commit");
	expect(validate(house).ok(), "house door watertight");
	const Topo door_topo = measure(house);
	print_case("house_door", door_topo);

	const int topo_cost = cost(union_topo, door_topo);
	if (std::getenv("SLAB_TOPO") != nullptr) {
		std::printf("topo_cost=%d\n", topo_cost);
	}
	expect(topo_cost >= 0, "cost is defined");
}
