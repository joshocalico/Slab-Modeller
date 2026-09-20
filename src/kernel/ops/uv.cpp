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

struct IslandBox {
	float min_u = 1e30f;
	float max_u = -1e30f;
	float min_v = 1e30f;
	float max_v = -1e30f;
};

struct IslandPlacement {
	godot::Vector2 offset;
	bool rotated = false;
};

static void expand_box(IslandBox &r_box, const godot::Vector2 &p_uv) {
	r_box.min_u = std::min(r_box.min_u, p_uv.x);
	r_box.max_u = std::max(r_box.max_u, p_uv.x);
	r_box.min_v = std::min(r_box.min_v, p_uv.y);
	r_box.max_v = std::max(r_box.max_v, p_uv.y);
}

static std::vector<int> island_order(const std::vector<IslandBox> &p_boxes) {
	std::vector<int> order(p_boxes.size());
	for (int i = 0; i < int(p_boxes.size()); i++) order[i] = i;
	std::sort(order.begin(), order.end(), [&](int a, int b) {
		return std::max(p_boxes[a].max_u - p_boxes[a].min_u, p_boxes[a].max_v - p_boxes[a].min_v) >
				std::max(p_boxes[b].max_u - p_boxes[b].min_u, p_boxes[b].max_v - p_boxes[b].min_v);
	});
	return order;
}

// Pack island AABBs into the unit tile. `p_source_resolution` is the atlas the
// boxes were authored for; `p_target_resolution` is the atlas being packed into.
// Success at source==target leaves island scale unchanged (rearrange only).
static bool pack_island_boxes(const std::vector<IslandBox> &p_boxes, const std::vector<int> &p_order,
		int p_source_resolution, int p_target_resolution, std::vector<IslandPlacement> *r_placements) {
	if (p_source_resolution <= 0 || p_target_resolution <= 0) return false;
	const float coordinate_scale = float(p_source_resolution) / float(p_target_resolution);
	const float padding = 1.0f / float(p_target_resolution);
	float x = 0.0f;
	float y = 0.0f;
	float row_height = 0.0f;
	for (const int index : p_order) {
		const IslandBox &box = p_boxes[index];
		const float source_w = (box.max_u - box.min_u) * coordinate_scale;
		const float source_h = (box.max_v - box.min_v) * coordinate_scale;
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
			const godot::Vector2 source_min = rotated ? godot::Vector2(box.min_v, -box.max_u) :
					godot::Vector2(box.min_u, box.min_v);
			(*r_placements)[index].offset = godot::Vector2(x, y) - source_min * coordinate_scale;
		}
		x += width + padding;
		row_height = std::max(row_height, height);
	}
	return true;
}

static int suggest_fitting_resolution(const std::vector<IslandBox> &p_boxes, const std::vector<int> &p_order,
		int p_source_resolution, int p_start_resolution) {
	int candidate = p_start_resolution;
	do {
		if (candidate > 1 << 28) break;
		candidate *= 2;
	} while (!pack_island_boxes(p_boxes, p_order, p_source_resolution, candidate, nullptr));
	return candidate;
}

static void write_packed_mapping(MeshEdit &p_edit, FaceId p_face, const godot::Vector3 &p_u,
		const godot::Vector3 &p_v, const godot::Vector2 &p_origin, const IslandPlacement &p_placement,
		float p_scale) {
	FaceAttrs attrs = p_edit.scratch().attrs(p_face);
	const godot::Vector3 u = p_placement.rotated ? p_v : p_u;
	const godot::Vector3 v = p_placement.rotated ? -p_u : p_v;
	const godot::Vector2 origin = p_placement.rotated ? godot::Vector2(p_origin.y, -p_origin.x) : p_origin;
	attrs.uv_unwrapped = true;
	attrs.uv_u = u * p_scale;
	attrs.uv_v = v * p_scale;
	attrs.uv_origin = origin * p_scale + p_placement.offset;
	attrs.uv_scale = godot::Vector2(1, 1);
	attrs.uv_offset = godot::Vector2(0, 0);
	attrs.uv_rotation = 0.0f;
	p_edit.set_attrs(p_face, attrs);
}

static UvAxis resolved_axis(const Mesh &p_mesh, FaceId p_face) {
	const FaceAttrs attrs = p_mesh.attrs(p_face);
	if (attrs.uv_axis != UvAxis::AUTO) return attrs.uv_axis;
	const godot::Vector3 n = p_mesh.face_normal(p_face);
	const float ax = std::abs(n.x);
	const float ay = std::abs(n.y);
	const float az = std::abs(n.z);
	if (az >= ax && az >= ay) return UvAxis::Z;
	if (ay >= ax) return UvAxis::Y;
	return UvAxis::X;
}

static godot::Vector2 project_axis(const godot::Vector3 &p, UvAxis p_axis) {
	switch (p_axis) {
		case UvAxis::X:
			return godot::Vector2(p.y, p.z);
		case UvAxis::Y:
			return godot::Vector2(p.x, p.z);
		case UvAxis::Z:
		case UvAxis::AUTO:
			return godot::Vector2(p.x, p.y);
	}
	return godot::Vector2(p.x, p.y);
}

static godot::Vector2 raw_projection(const Mesh &p_mesh, FaceId p_face, const godot::Vector3 &p) {
	const FaceAttrs attrs = p_mesh.attrs(p_face);
	if (attrs.uv_unwrapped) {
		return godot::Vector2(p.dot(attrs.uv_u), p.dot(attrs.uv_v)) + attrs.uv_origin;
	}
	return project_axis(p, resolved_axis(p_mesh, p_face));
}

static godot::Vector2 rotate2(const godot::Vector2 &p, float p_cos, float p_sin) {
	return godot::Vector2(p.x * p_cos - p.y * p_sin, p.x * p_sin + p.y * p_cos);
}

static godot::Vector2 current_uv(const Mesh &p_mesh, FaceId p_face, const godot::Vector3 &p) {
	const FaceAttrs attrs = p_mesh.attrs(p_face);
	godot::Vector2 uv = raw_projection(p_mesh, p_face, p);
	uv.x *= attrs.uv_scale.x;
	uv.y *= attrs.uv_scale.y;
	godot::Vector2 centroid = raw_projection(p_mesh, p_face, p_mesh.face_centroid(p_face));
	centroid.x *= attrs.uv_scale.x;
	centroid.y *= attrs.uv_scale.y;
	const float s = std::sin(attrs.uv_rotation);
	const float c = std::cos(attrs.uv_rotation);
	const godot::Vector2 d = uv - centroid;
	return rotate2(d, c, s) + centroid + attrs.uv_offset;
}

static void baked_current_mapping(const Mesh &p_mesh, FaceId p_face, godot::Vector3 &r_u,
		godot::Vector3 &r_v, godot::Vector2 &r_origin) {
	const FaceAttrs attrs = p_mesh.attrs(p_face);
	godot::Vector3 u = godot::Vector3(1, 0, 0);
	godot::Vector3 v = godot::Vector3(0, 1, 0);
	godot::Vector2 origin;
	if (attrs.uv_unwrapped) {
		u = attrs.uv_u;
		v = attrs.uv_v;
		origin = attrs.uv_origin;
	} else {
		switch (resolved_axis(p_mesh, p_face)) {
			case UvAxis::X:
				u = godot::Vector3(0, 1, 0);
				v = godot::Vector3(0, 0, 1);
				break;
			case UvAxis::Y:
				u = godot::Vector3(1, 0, 0);
				v = godot::Vector3(0, 0, 1);
				break;
			case UvAxis::Z:
			case UvAxis::AUTO:
				u = godot::Vector3(1, 0, 0);
				v = godot::Vector3(0, 1, 0);
				break;
		}
		origin = godot::Vector2();
	}
	const float sx = attrs.uv_scale.x;
	const float sy = attrs.uv_scale.y;
	const godot::Vector3 u_s = u * sx;
	const godot::Vector3 v_s = v * sy;
	const godot::Vector2 o_s(origin.x * sx, origin.y * sy);
	godot::Vector2 centroid = raw_projection(p_mesh, p_face, p_mesh.face_centroid(p_face));
	centroid.x *= sx;
	centroid.y *= sy;
	const float s = std::sin(attrs.uv_rotation);
	const float c = std::cos(attrs.uv_rotation);
	r_u = u_s * c - v_s * s;
	r_v = u_s * s + v_s * c;
	r_origin = rotate2(o_s, c, s) + centroid - rotate2(centroid, c, s) + attrs.uv_offset;
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
	std::vector<IslandBox> boxes(island);
	for (const FaceId face : p_faces) {
		const Mapping &mapping = maps.at(face.slot);
		std::vector<VertexId> corners;
		mesh.face_corners(face, corners);
		for (const VertexId vertex : corners) {
			expand_box(boxes[mapping.island], map_point(mapping, mesh.position(vertex)));
		}
	}
	const std::vector<int> order = island_order(boxes);
	std::vector<IslandPlacement> placements(island);
	if (!pack_island_boxes(boxes, order, p_texture_resolution, p_texture_resolution, &placements)) {
		result.fault = invalid_selection();
		result.atlas_overflow = true;
		result.suggested_texture_resolution = suggest_fitting_resolution(boxes, order,
				p_texture_resolution, p_texture_resolution);
		return result;
	}
	for (const EdgeId edge : result.auto_seams) p_edit.set_uv_seam(edge, true);
	for (const FaceId face : p_faces) {
		const Mapping &mapping = maps.at(face.slot);
		write_packed_mapping(p_edit, face, mapping.u, mapping.v, mapping.origin,
				placements[mapping.island], 1.0f);
	}
	result.fault = p_edit.last_fault();
	result.island_count = island;
	return result;
}

UvPackResult pack_uv(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, int p_texture_resolution,
		int p_source_texture_resolution) {
	UvPackResult result;
	const Mesh &mesh = p_edit.scratch();
	if (p_faces.empty() || p_texture_resolution <= 0) {
		result.fault = invalid_selection();
		return result;
	}
	if (p_source_texture_resolution <= 0) p_source_texture_resolution = p_texture_resolution;
	std::unordered_map<uint32_t, FaceId> selected;
	for (const FaceId face : p_faces) {
		if (!mesh.alive(face) || !mesh.attrs(face).uv_unwrapped || !selected.emplace(face.slot, face).second) {
			result.fault = invalid_selection();
			return result;
		}
	}

	const float tolerance = 1e-4f;
	std::unordered_map<uint32_t, int> island_of;
	int island = 0;
	for (const FaceId root : p_faces) {
		if (island_of.count(root.slot)) continue;
		island_of[root.slot] = island++;
		std::queue<FaceId> pending;
		pending.push(root);
		while (!pending.empty()) {
			const FaceId face = pending.front();
			pending.pop();
			std::vector<EdgeId> edges;
			mesh.face_edges(face, edges);
			for (const EdgeId edge : edges) {
				if (mesh.edge_uv_seam(edge)) continue;
				FaceId a;
				FaceId b;
				mesh.edge_faces(edge, a, b);
				const FaceId other = a.slot == face.slot ? b : a;
				if (!selected.count(other.slot) || island_of.count(other.slot)) continue;
				VertexId va;
				VertexId vb;
				mesh.edge_vertices(edge, va, vb);
				if (current_uv(mesh, face, mesh.position(va)).distance_to(current_uv(mesh, other, mesh.position(va))) >
								tolerance ||
						current_uv(mesh, face, mesh.position(vb)).distance_to(current_uv(mesh, other, mesh.position(vb))) >
								tolerance) {
					continue;
				}
				island_of[other.slot] = island_of[face.slot];
				pending.push(other);
			}
		}
	}

	std::vector<IslandBox> boxes(island);
	for (const FaceId face : p_faces) {
		std::vector<VertexId> corners;
		mesh.face_corners(face, corners);
		for (const VertexId vertex : corners) {
			expand_box(boxes[island_of.at(face.slot)], current_uv(mesh, face, mesh.position(vertex)));
		}
	}
	const std::vector<int> order = island_order(boxes);
	std::vector<IslandPlacement> placements(island);
	if (!pack_island_boxes(boxes, order, p_source_texture_resolution, p_texture_resolution, &placements)) {
		result.fault = invalid_selection();
		result.atlas_overflow = true;
		result.suggested_texture_resolution = suggest_fitting_resolution(boxes, order,
				p_source_texture_resolution, p_texture_resolution);
		return result;
	}
	const float scale = float(p_source_texture_resolution) / float(p_texture_resolution);
	for (const FaceId face : p_faces) {
		godot::Vector3 u;
		godot::Vector3 v;
		godot::Vector2 origin;
		baked_current_mapping(mesh, face, u, v, origin);
		write_packed_mapping(p_edit, face, u, v, origin, placements[island_of.at(face.slot)], scale);
	}
	result.fault = p_edit.last_fault();
	result.island_count = island;
	return result;
}

} // namespace ops
} // namespace slab
