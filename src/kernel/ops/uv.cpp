#include "uv.hpp"

#include <algorithm>
#include <cmath>
#include <queue>
#include <unordered_map>
#include <unordered_set>

namespace slab {
namespace ops {
namespace {

struct Mapping {
	godot::Vector3 u;
	godot::Vector3 v;
	godot::Vector2 origin;
	int island = -1;
};

static godot::Vector2 map_point(const Mapping &p_map, const godot::Vector3 &p) {
	return godot::Vector2(p.dot(p_map.u), p.dot(p_map.v)) + p_map.origin;
}

static MeshFault invalid_selection() {
	MeshFault fault;
	fault.code = MeshError::INVALID_SELECTION;
	return fault;
}

static bool make_root_mapping(const Mesh &p_mesh, FaceId p_face, float p_density, Mapping &r_map) {
	std::vector<VertexId> corners;
	p_mesh.face_corners(p_face, corners);
	if (corners.size() < 3) return false;
	const godot::Vector3 a = p_mesh.position(corners[0]);
	godot::Vector3 tangent;
	for (size_t i = 1; i < corners.size(); i++) {
		tangent = p_mesh.position(corners[i]) - a;
		if (tangent.length_squared() > 1e-12f) break;
	}
	const godot::Vector3 normal = p_mesh.face_normal(p_face);
	if (tangent.length_squared() <= 1e-12f || normal.length_squared() <= 1e-12f) return false;
	tangent.normalize();
	const godot::Vector3 across = normal.cross(tangent).normalized();
	r_map.u = tangent * p_density;
	r_map.v = across * p_density;
	r_map.origin = -godot::Vector2(a.dot(r_map.u), a.dot(r_map.v));
	return true;
}

static bool unfold_across(const Mesh &p_mesh, FaceId p_parent, const Mapping &p_map,
		FaceId p_child, EdgeId p_edge, float p_density, Mapping &r_child) {
	VertexId va;
	VertexId vb;
	p_mesh.edge_vertices(p_edge, va, vb);
	if (!p_mesh.alive(va) || !p_mesh.alive(vb)) return false;
	const godot::Vector3 a = p_mesh.position(va);
	const godot::Vector3 b = p_mesh.position(vb);
	const godot::Vector3 edge3 = b - a;
	const float length = edge3.length();
	if (length <= 1e-6f) return false;
	const godot::Vector2 qa = map_point(p_map, a);
	const godot::Vector2 qb = map_point(p_map, b);
	godot::Vector2 edge2 = qb - qa;
	if (edge2.length_squared() <= 1e-12f) return false;
	edge2 = edge2.normalized();
	const godot::Vector2 perp(-edge2.y, edge2.x);
	const float parent_side = perp.dot(map_point(p_map, p_mesh.face_centroid(p_parent)) - qa);
	const godot::Vector3 tangent = edge3 / length;
	const godot::Vector3 normal = p_mesh.face_normal(p_child);
	if (normal.length_squared() <= 1e-12f) return false;
	const godot::Vector3 across = normal.cross(tangent).normalized();
	const float child_side3 = across.dot(p_mesh.face_centroid(p_child) - a);
	if (std::abs(child_side3) <= 1e-7f) return false;
	const godot::Vector2 desired_across = parent_side >= 0.0f ? -perp : perp;
	const godot::Vector2 child_across = child_side3 >= 0.0f ? desired_across : -desired_across;
	r_child.u = (tangent * edge2.x + across * child_across.x) * p_density;
	r_child.v = (tangent * edge2.y + across * child_across.y) * p_density;
	r_child.origin = qa - godot::Vector2(a.dot(r_child.u), a.dot(r_child.v));
	return true;
}

static bool edge_continuous(const Mesh &p_mesh, EdgeId p_edge, const Mapping &p_a,
		const Mapping &p_b, float p_tolerance) {
	VertexId va;
	VertexId vb;
	p_mesh.edge_vertices(p_edge, va, vb);
	return map_point(p_a, p_mesh.position(va)).distance_to(map_point(p_b, p_mesh.position(va))) <= p_tolerance &&
			map_point(p_a, p_mesh.position(vb)).distance_to(map_point(p_b, p_mesh.position(vb))) <= p_tolerance;
}

static float cross2(const godot::Vector2 &p_a, const godot::Vector2 &p_b, const godot::Vector2 &p_c) {
	return (p_b.x - p_a.x) * (p_c.y - p_a.y) - (p_b.y - p_a.y) * (p_c.x - p_a.x);
}

static bool proper_cross(const godot::Vector2 &p_a, const godot::Vector2 &p_b,
		const godot::Vector2 &p_c, const godot::Vector2 &p_d, float p_epsilon) {
	const float ab_c = cross2(p_a, p_b, p_c);
	const float ab_d = cross2(p_a, p_b, p_d);
	const float cd_a = cross2(p_c, p_d, p_a);
	const float cd_b = cross2(p_c, p_d, p_b);
	return ((ab_c > p_epsilon && ab_d < -p_epsilon) || (ab_c < -p_epsilon && ab_d > p_epsilon)) &&
			((cd_a > p_epsilon && cd_b < -p_epsilon) || (cd_a < -p_epsilon && cd_b > p_epsilon));
}

static bool strictly_inside(const godot::Vector2 &p_point, const std::vector<godot::Vector2> &p_loop,
		float p_epsilon) {
	bool inside = false;
	for (size_t i = 0, j = p_loop.size() - 1; i < p_loop.size(); j = i++) {
		const godot::Vector2 &a = p_loop[j];
		const godot::Vector2 &b = p_loop[i];
		const godot::Vector2 ab = b - a;
		const godot::Vector2 ap = p_point - a;
		const float projection = ab.length_squared() > 0.0f ? ap.dot(ab) / ab.length_squared() : 0.0f;
		if (projection >= 0.0f && projection <= 1.0f &&
				(a + ab * projection).distance_to(p_point) <= p_epsilon) return false;
		if ((a.y > p_point.y) != (b.y > p_point.y)) {
			const float x = a.x + (b.x - a.x) * (p_point.y - a.y) / (b.y - a.y);
			if (x > p_point.x) inside = !inside;
		}
	}
	return inside;
}

static std::vector<godot::Vector2> face_loop(const Mesh &p_mesh, FaceId p_face, const Mapping &p_mapping) {
	std::vector<VertexId> corners;
	p_mesh.face_corners(p_face, corners);
	std::vector<godot::Vector2> loop;
	loop.reserve(corners.size());
	for (const VertexId corner : corners) loop.push_back(map_point(p_mapping, p_mesh.position(corner)));
	return loop;
}

static bool loops_overlap(const std::vector<godot::Vector2> &p_a,
		const std::vector<godot::Vector2> &p_b, float p_epsilon) {
	for (size_t i = 0; i < p_a.size(); i++) {
		for (size_t j = 0; j < p_b.size(); j++) {
			if (proper_cross(p_a[i], p_a[(i + 1) % p_a.size()],
					p_b[j], p_b[(j + 1) % p_b.size()], p_epsilon)) return true;
		}
	}
	for (const godot::Vector2 &point : p_a) if (strictly_inside(point, p_b, p_epsilon)) return true;
	for (const godot::Vector2 &point : p_b) if (strictly_inside(point, p_a, p_epsilon)) return true;
	godot::Vector2 centre_a;
	for (const godot::Vector2 &point : p_a) centre_a += point;
	centre_a /= float(p_a.size());
	if (strictly_inside(centre_a, p_b, p_epsilon)) return true;
	godot::Vector2 centre_b;
	for (const godot::Vector2 &point : p_b) centre_b += point;
	centre_b /= float(p_b.size());
	if (strictly_inside(centre_b, p_a, p_epsilon)) return true;
	return false;
}

} // namespace

UvUnwrapResult unwrap_uv(MeshEdit &p_edit, const std::vector<FaceId> &p_faces,
		float p_pixels_per_meter, int p_texture_resolution) {
	UvUnwrapResult result;
	const Mesh &mesh = p_edit.scratch();
	if (p_faces.empty() || !std::isfinite(p_pixels_per_meter) || p_pixels_per_meter <= 0.0f ||
			p_texture_resolution <= 0) {
		result.fault = invalid_selection();
		return result;
	}
	std::unordered_map<uint32_t, FaceId> selected;
	for (const FaceId face : p_faces) {
		if (!mesh.alive(face) || !selected.emplace(face.slot, face).second) {
			result.fault = invalid_selection();
			return result;
		}
	}
	const float density = p_pixels_per_meter / float(p_texture_resolution);
	const float tolerance = std::max(1e-5f, density * 0.002f);
	std::unordered_map<uint32_t, Mapping> maps;
	std::unordered_set<uint32_t> cut_slots;
	int island = 0;

	for (const FaceId root : p_faces) {
		if (maps.count(root.slot)) continue;
		Mapping root_map;
		if (!make_root_mapping(mesh, root, density, root_map)) {
			result.fault = invalid_selection();
			return result;
		}
		root_map.island = island++;
		maps[root.slot] = root_map;
		std::queue<FaceId> pending;
		pending.push(root);
		while (!pending.empty()) {
			const FaceId face = pending.front();
			pending.pop();
			std::vector<EdgeId> edges;
			mesh.face_edges(face, edges);
			for (const EdgeId edge : edges) {
				if (mesh.edge_uv_seam(edge) || cut_slots.count(edge.slot)) continue;
				FaceId a;
				FaceId b;
				mesh.edge_faces(edge, a, b);
				const FaceId other = a.slot == face.slot ? b : a;
				if (!mesh.alive(other) || !selected.count(other.slot)) continue;
				Mapping candidate;
				if (!unfold_across(mesh, face, maps.at(face.slot), other, edge, density, candidate)) {
					result.fault = invalid_selection();
					return result;
				}
				candidate.island = maps.at(face.slot).island;
				auto found = maps.find(other.slot);
				if (found == maps.end()) {
					maps[other.slot] = candidate;
					pending.push(other);
				} else if (found->second.island == candidate.island &&
						!edge_continuous(mesh, edge, found->second, candidate, tolerance)) {
					cut_slots.insert(edge.slot);
					result.auto_seams.push_back(edge);
				}
			}
		}
	}

	// A branching unfold can place two faces over the same texture area even
	// when every hinge is locally continuous. Isolate the later face explicitly;
	// the component pass below then packs every resulting island apart.
	for (size_t i = 0; i < p_faces.size(); i++) {
		for (size_t j = i + 1; j < p_faces.size(); j++) {
			if (maps.at(p_faces[i].slot).island != maps.at(p_faces[j].slot).island) continue;
			if (!loops_overlap(face_loop(mesh, p_faces[i], maps.at(p_faces[i].slot)),
					face_loop(mesh, p_faces[j], maps.at(p_faces[j].slot)), tolerance)) continue;
			std::vector<EdgeId> edges;
			mesh.face_edges(p_faces[j], edges);
			for (const EdgeId edge : edges) {
				FaceId a;
				FaceId b;
				mesh.edge_faces(edge, a, b);
				if (selected.count(a.slot) && selected.count(b.slot) && cut_slots.insert(edge.slot).second) {
					result.auto_seams.push_back(edge);
				}
			}
		}
	}

	// Recompute components after automatic overlap cuts.
	for (auto &entry : maps) entry.second.island = -1;
	island = 0;
	for (const FaceId root : p_faces) {
		if (maps.at(root.slot).island >= 0) continue;
		maps.at(root.slot).island = island++;
		std::queue<FaceId> pending;
		pending.push(root);
		while (!pending.empty()) {
			const FaceId face = pending.front();
			pending.pop();
			std::vector<EdgeId> edges;
			mesh.face_edges(face, edges);
			for (const EdgeId edge : edges) {
				if (mesh.edge_uv_seam(edge) || cut_slots.count(edge.slot)) continue;
				FaceId a;
				FaceId b;
				mesh.edge_faces(edge, a, b);
				const FaceId other = a.slot == face.slot ? b : a;
				if (!selected.count(other.slot) || maps.at(other.slot).island >= 0) continue;
				maps.at(other.slot).island = maps.at(face.slot).island;
				pending.push(other);
			}
		}
	}

	// Pack seam-separated island bounds into one texture without changing scale.
	std::vector<float> min_u(island, 1e30f), max_u(island, -1e30f);
	std::vector<float> min_v(island, 1e30f), max_v(island, -1e30f);
	for (const FaceId face : p_faces) {
		const Mapping &mapping = maps.at(face.slot);
		std::vector<VertexId> corners;
		mesh.face_corners(face, corners);
		for (const VertexId vertex : corners) {
			const float u = map_point(mapping, mesh.position(vertex)).x;
			const float v = map_point(mapping, mesh.position(vertex)).y;
			min_u[mapping.island] = std::min(min_u[mapping.island], u);
			max_u[mapping.island] = std::max(max_u[mapping.island], u);
			min_v[mapping.island] = std::min(min_v[mapping.island], v);
			max_v[mapping.island] = std::max(max_v[mapping.island], v);
		}
	}
	struct Placement { godot::Vector2 offset; bool rotated = false; };
	std::vector<Placement> placements(island);
	std::vector<int> order(island);
	for (int i = 0; i < island; i++) order[i] = i;
	std::sort(order.begin(), order.end(), [&](int a, int b) {
		return std::max(max_u[a] - min_u[a], max_v[a] - min_v[a]) >
				std::max(max_u[b] - min_u[b], max_v[b] - min_v[b]);
	});
	auto pack_at_resolution = [&](int p_resolution, std::vector<Placement> *r_placements) {
		const float coordinate_scale = float(p_texture_resolution) / float(p_resolution);
		const float padding = 1.0f / float(p_resolution);
		float x = 0.0f;
		float y = 0.0f;
		float row_height = 0.0f;
		for (const int index : order) {
			const float source_w = (max_u[index] - min_u[index]) * coordinate_scale;
			const float source_h = (max_v[index] - min_v[index]) * coordinate_scale;
			bool rotated = false;
			float width = source_w;
			float height = source_h;
			if ((width > 1.0f || (x + width > 1.0f && x + source_h <= 1.0f)) && source_h <= 1.0f) {
				rotated = true;
				width = source_h;
				height = source_w;
			}
			if (x > 0.0f && x + width > 1.0f + 1e-6f) {
				x = 0.0f;
				y += row_height + padding;
				row_height = 0.0f;
				rotated = source_w < source_h;
				width = rotated ? source_h : source_w;
				height = rotated ? source_w : source_h;
			}
			if (width > 1.0f + 1e-6f || y + height > 1.0f + 1e-6f) return false;
			if (r_placements != nullptr) {
				(*r_placements)[index].rotated = rotated;
				const godot::Vector2 source_min = rotated ? godot::Vector2(min_v[index], -max_u[index]) :
						godot::Vector2(min_u[index], min_v[index]);
				(*r_placements)[index].offset = godot::Vector2(x, y) - source_min;
			}
			x += width + padding;
			row_height = std::max(row_height, height);
		}
		return true;
	};
	if (!pack_at_resolution(p_texture_resolution, &placements)) {
		result.fault = invalid_selection();
		result.atlas_overflow = true;
		int candidate = p_texture_resolution;
		do {
			if (candidate > 1 << 28) break;
			candidate *= 2;
		} while (!pack_at_resolution(candidate, nullptr));
		result.suggested_texture_resolution = candidate;
		return result;
	}
	for (const EdgeId edge : result.auto_seams) p_edit.set_uv_seam(edge, true);
	for (const FaceId face : p_faces) {
		const Mapping &mapping = maps.at(face.slot);
		const Placement &placement = placements[mapping.island];
		FaceAttrs attrs = mesh.attrs(face);
		attrs.uv_unwrapped = true;
		attrs.uv_u = placement.rotated ? mapping.v : mapping.u;
		attrs.uv_v = placement.rotated ? -mapping.u : mapping.v;
		attrs.uv_origin = (placement.rotated ? godot::Vector2(mapping.origin.y, -mapping.origin.x) : mapping.origin) +
				placement.offset;
		attrs.uv_scale = godot::Vector2(1, 1);
		attrs.uv_offset = godot::Vector2(0, 0);
		attrs.uv_rotation = 0.0f;
		p_edit.set_attrs(face, attrs);
	}
	result.fault = p_edit.last_fault();
	result.island_count = island;
	return result;
}

} // namespace ops
} // namespace slab
