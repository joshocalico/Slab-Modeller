#include "uv.hpp"
#include "../emit.hpp"

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

static bool boxes_intersect(const IslandBox &a, const IslandBox &b, float padding = 0.0f) {
	return a.max_u + padding > b.min_u + 1e-6f && b.max_u + padding > a.min_u + 1e-6f &&
			a.max_v + padding > b.min_v + 1e-6f && b.max_v + padding > a.min_v + 1e-6f;
}

static bool pack_around_fixed(const std::vector<IslandBox> &boxes, const std::vector<int> &order,
		float scale, float padding, const std::vector<bool> &fixed,
		std::vector<IslandPlacement> *placements) {
	std::vector<IslandBox> occupied;
	for (size_t i = 0; i < boxes.size(); ++i) {
		if (!fixed[i]) continue;
		const IslandBox b{ boxes[i].min_u * scale, boxes[i].max_u * scale,
				boxes[i].min_v * scale, boxes[i].max_v * scale };
		if (b.min_u < -1e-6f || b.min_v < -1e-6f || b.max_u > 1.0f + 1e-6f || b.max_v > 1.0f + 1e-6f) return false;
		for (const IslandBox &other : occupied) if (boxes_intersect(b, other)) return false;
		occupied.push_back(b);
		if (placements) (*placements)[i] = IslandPlacement{};
	}
	for (const int i : order) {
		if (fixed[i]) continue;
		const IslandBox &b = boxes[i];
		const float w = (b.max_u - b.min_u) * scale, h = (b.max_v - b.min_v) * scale;
		std::vector<float> xs{0.0f}, ys{0.0f};
		for (const IslandBox &other : occupied) {
			xs.push_back(other.max_u + padding);
			ys.push_back(other.max_v + padding);
		}
		std::sort(xs.begin(), xs.end());
		std::sort(ys.begin(), ys.end());
		bool found = false;
		for (const float y : ys) {
			for (const float x : xs) {
				for (int rotation = 0; rotation < 2; ++rotation) {
					const float width = rotation ? h : w, height = rotation ? w : h;
					if (x + width > 1.0f + 1e-6f || y + height > 1.0f + 1e-6f) continue;
					const IslandBox candidate{x, x + width, y, y + height};
					bool blocked = false;
					for (const IslandBox &other : occupied) {
						if (boxes_intersect(candidate, other, padding)) { blocked = true; break; }
					}
					if (blocked) continue;
					if (placements) {
						(*placements)[i].rotated = rotation != 0;
						const godot::Vector2 minimum = rotation ? godot::Vector2(b.min_v, -b.max_u) : godot::Vector2(b.min_u, b.min_v);
						(*placements)[i].offset = godot::Vector2(x, y) - minimum * scale;
					}
					occupied.push_back(candidate);
					found = true;
					break;
				}
				if (found) break;
			}
			if (found) break;
		}
		if (!found) return false;
	}
	return true;
}

// Pack island AABBs into the unit tile. `p_source_resolution` is the atlas the
// boxes were authored for; `p_target_resolution` is the atlas being packed into.
// Success at source==target leaves island scale unchanged (rearrange only).
static bool pack_island_boxes(const std::vector<IslandBox> &p_boxes, const std::vector<int> &p_order,
		int p_source_resolution, int p_target_resolution, std::vector<IslandPlacement> *r_placements,
		const std::vector<bool> *p_fixed = nullptr) {
	if (p_source_resolution <= 0 || p_target_resolution <= 0) return false;
	const float coordinate_scale = float(p_source_resolution) / float(p_target_resolution);
	const float padding = 1.0f / float(p_target_resolution);
	if (p_fixed && std::find(p_fixed->begin(), p_fixed->end(), true) != p_fixed->end()) {
		return pack_around_fixed(p_boxes, p_order, coordinate_scale, padding, *p_fixed, r_placements);
	}
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
		float p_scale, int p_texture_resolution) {
	FaceAttrs attrs = p_edit.scratch().attrs(p_face);
	const godot::Vector3 u = p_placement.rotated ? p_v : p_u;
	const godot::Vector3 v = p_placement.rotated ? -p_u : p_v;
	const godot::Vector2 origin = p_placement.rotated ? godot::Vector2(p_origin.y, -p_origin.x) : p_origin;
	attrs.uv_unwrapped = true;
	attrs.uv_texture_resolution = uint32_t(p_texture_resolution);
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

	// Solve rigid pin constraints at the requested density before changing data.
	// Pins constrain whole unfolded islands, including faces without pins.
	struct Pin { godot::Vector2 source; godot::Vector2 target; };
	std::vector<std::vector<Pin>> pins(island);
	std::vector<bool> fixed(island, false);
	std::unordered_map<uint32_t, std::vector<CornerAttrs>> old_corners;
	std::unordered_map<uint32_t, std::vector<godot::Vector2>> old_uvs;
	for (const FaceId face : p_faces) {
		mesh.face_corner_attrs(face, old_corners[face.slot]);
		face_uv_points(mesh, face, old_uvs[face.slot]);
		std::vector<VertexId> corners;
		mesh.face_corners(face, corners);
		for (size_t i = 0; i < corners.size(); ++i) {
			if (!old_corners.at(face.slot)[i].uv_pinned) continue;
			const Mapping &mapping = maps.at(face.slot);
			pins[mapping.island].push_back({map_point(mapping, mesh.position(corners[i])), old_uvs.at(face.slot)[i]});
		}
	}
	for (int index = 0; index < island; ++index) {
		if (pins[index].empty()) continue;
		fixed[index] = true;
		const Pin &anchor = pins[index][0];
		float c = 1.0f, s = 0.0f;
		for (size_t i = 1; i < pins[index].size(); ++i) {
			const godot::Vector2 from = pins[index][i].source - anchor.source;
			if (from.length() <= tolerance) continue;
			const godot::Vector2 to = pins[index][i].target - anchor.target;
			const float angle = std::atan2(from.x * to.y - from.y * to.x, from.dot(to));
			c = std::cos(angle);
			s = std::sin(angle);
			break;
		}
		const godot::Vector2 offset = anchor.target - rotate2(anchor.source, c, s);
		for (const Pin &pin : pins[index]) {
			const godot::Vector2 fitted = rotate2(pin.source, c, s) + offset;
			if (!std::isfinite(pin.target.x) || !std::isfinite(pin.target.y) || fitted.distance_to(pin.target) > tolerance) {
				result.fault = invalid_selection();
				result.pinned_conflict = true;
				result.refuse_reason = "Pinned UVs are incompatible with this unfold or texel density. Unpin conflicting corners, change density, or add seams.";
				return result;
			}
		}
		for (const FaceId face : p_faces) {
			Mapping &mapping = maps.at(face.slot);
			if (mapping.island != index) continue;
			const godot::Vector3 u = mapping.u, v = mapping.v;
			mapping.u = u * c - v * s;
			mapping.v = u * s + v * c;
			mapping.origin = rotate2(mapping.origin, c, s) + offset;
		}
	}

	// Pack seam-separated island bounds into one texture without changing scale.
	std::vector<IslandBox> boxes(island);
	for (const FaceId face : p_faces) {
		const Mapping &mapping = maps.at(face.slot);
		std::vector<VertexId> corners;
		mesh.face_corners(face, corners);
		for (const VertexId vertex : corners) {
			const godot::Vector2 uv = map_point(mapping, mesh.position(vertex));
			if (!std::isfinite(uv.x) || !std::isfinite(uv.y)) {
				result.fault = invalid_selection();
				result.refuse_reason = "The requested unwrap density exceeds the finite UV range.";
				return result;
			}
			expand_box(boxes[mapping.island], uv);
		}
	}
	const std::vector<int> order = island_order(boxes);
	std::vector<IslandPlacement> placements(island);
	if (!pack_island_boxes(boxes, order, p_texture_resolution, p_texture_resolution, &placements, &fixed)) {
		result.fault = invalid_selection();
		result.atlas_overflow = true;
		result.pinned_conflict = std::find(fixed.begin(), fixed.end(), true) != fixed.end();
		if (result.pinned_conflict) {
			result.refuse_reason = "Pinned island bounds overlap, leave the tile, or block packing. Move or unpin them, or reduce the unfold density.";
		} else {
			result.suggested_texture_resolution = suggest_fitting_resolution(boxes, order,
					p_texture_resolution, p_texture_resolution);
			result.refuse_reason = "The unfolded islands do not fit at this density. Use the suggested larger atlas.";
		}
		return result;
	}
	for (const EdgeId edge : result.auto_seams) p_edit.set_uv_seam(edge, true);
	for (const FaceId face : p_faces) {
		const Mapping &mapping = maps.at(face.slot);
		write_packed_mapping(p_edit, face, mapping.u, mapping.v, mapping.origin,
				placements[mapping.island], 1.0f, p_texture_resolution);
		for (size_t i = 0; i < old_corners.at(face.slot).size(); ++i) {
			CornerAttrs corner = old_corners.at(face.slot)[i];
			// Clear superseded explicit coordinates; only pins retain exact values.
			corner.uv_explicit = corner.uv_pinned;
			corner.uv = corner.uv_pinned ? old_uvs.at(face.slot)[i] : godot::Vector2();
			p_edit.set_corner_attrs(face, uint32_t(i), corner);
		}
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
	std::unordered_map<uint32_t, std::vector<godot::Vector2>> coordinates;
	std::unordered_map<uint32_t, std::vector<VertexId>> vertices;
	std::unordered_map<uint32_t, std::vector<CornerAttrs>> attributes;
	std::unordered_map<uint32_t, bool> explicit_faces;
	for (const FaceId face : p_faces) {
		if (!mesh.alive(face) || !selected.emplace(face.slot, face).second) {
			result.fault = invalid_selection();
			return result;
		}
		mesh.face_corner_attrs(face, attributes[face.slot]);
		bool any_explicit = false;
		for (const CornerAttrs &corner : attributes.at(face.slot)) any_explicit |= corner.uv_explicit;
		if (!mesh.attrs(face).uv_unwrapped && !any_explicit) {
			result.fault = invalid_selection();
			result.refuse_reason = "Unwrap projected faces before packing, or author explicit corner UVs.";
			return result;
		}
		explicit_faces[face.slot] = any_explicit;
		mesh.face_corners(face, vertices[face.slot]);
		face_uv_points(mesh, face, coordinates[face.slot]);
		for (const godot::Vector2 &uv : coordinates.at(face.slot)) {
			if (!std::isfinite(uv.x) || !std::isfinite(uv.y)) { result.fault = invalid_selection(); return result; }
		}
	}
	const auto source_resolution = [&](FaceId face) {
		const uint32_t stored = mesh.attrs(face).uv_texture_resolution;
		return stored > 0 ? float(stored) : float(p_source_texture_resolution);
	};
	const auto uv_at_vertex = [&](FaceId face, VertexId vertex) {
		const auto &corners = vertices.at(face.slot);
		for (size_t i = 0; i < corners.size(); ++i) if (corners[i].slot == vertex.slot) return coordinates.at(face.slot)[i];
		return godot::Vector2();
	};
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
				FaceId a, b;
				mesh.edge_faces(edge, a, b);
				const FaceId other = a.slot == face.slot ? b : a;
				if (!selected.count(other.slot) || island_of.count(other.slot)) continue;
				if (source_resolution(face) != source_resolution(other)) continue;
				VertexId va, vb;
				mesh.edge_vertices(edge, va, vb);
				if (uv_at_vertex(face, va).distance_to(uv_at_vertex(other, va)) > tolerance ||
						uv_at_vertex(face, vb).distance_to(uv_at_vertex(other, vb)) > tolerance) continue;
				island_of[other.slot] = island_of[face.slot];
				pending.push(other);
			}
		}
	}
	std::vector<IslandBox> boxes(island);
	std::vector<bool> fixed(island, false);
	for (const FaceId face : p_faces) {
		for (const godot::Vector2 &uv : coordinates.at(face.slot)) {
			const godot::Vector2 pixels = uv * source_resolution(face);
			if (!std::isfinite(pixels.x) || !std::isfinite(pixels.y)) {
				result.fault = invalid_selection();
				result.refuse_reason = "The current UV coordinates exceed the finite packing range.";
				return result;
			}
			expand_box(boxes[island_of.at(face.slot)], pixels);
		}
		for (const CornerAttrs &corner : attributes.at(face.slot)) if (corner.uv_pinned) fixed[island_of.at(face.slot)] = true;
	}
	for (const FaceId face : p_faces) {
		if (fixed[island_of.at(face.slot)] && source_resolution(face) != float(p_texture_resolution)) {
			result.fault = invalid_selection();
			result.pinned_conflict = true;
			result.refuse_reason = "Pinned islands must keep their atlas resolution. Use the current resolution or unpin them before resizing.";
			return result;
		}
	}
	const std::vector<int> order = island_order(boxes);
	std::vector<IslandPlacement> placements(island);
	if (!pack_island_boxes(boxes, order, 1, p_texture_resolution, &placements, &fixed)) {
		result.fault = invalid_selection();
		result.atlas_overflow = true;
		result.pinned_conflict = std::find(fixed.begin(), fixed.end(), true) != fixed.end();
		if (result.pinned_conflict) {
			result.refuse_reason = "Pinned island bounds overlap, leave the tile, or block packing. Move or unpin them before packing.";
		} else {
			result.suggested_texture_resolution = suggest_fitting_resolution(boxes, order, 1, p_texture_resolution);
			result.refuse_reason = "The islands do not fit at this density. Use the suggested larger atlas.";
		}
		return result;
	}
	for (const FaceId face : p_faces) {
		const int index = island_of.at(face.slot);
		if (fixed[index]) continue; // Keep pinned islands byte-for-byte unchanged.
		const float scale = source_resolution(face) / float(p_texture_resolution);
		const IslandPlacement &placement = placements[index];
		if (explicit_faces.at(face.slot)) {
			FaceAttrs attrs = mesh.attrs(face);
			attrs.uv_unwrapped = true;
			attrs.uv_texture_resolution = uint32_t(p_texture_resolution);
			attrs.uv_scale = godot::Vector2(1, 1);
			attrs.uv_offset = godot::Vector2();
			attrs.uv_rotation = 0;
			p_edit.set_attrs(face, attrs);
			for (size_t i = 0; i < coordinates.at(face.slot).size(); ++i) {
				const godot::Vector2 uv = coordinates.at(face.slot)[i];
				CornerAttrs corner = attributes.at(face.slot)[i];
				corner.uv_explicit = true;
				corner.uv = (placement.rotated ? godot::Vector2(uv.y, -uv.x) : uv) * scale + placement.offset;
				p_edit.set_corner_attrs(face, uint32_t(i), corner);
			}
		} else {
			godot::Vector3 u, v;
			godot::Vector2 origin;
			baked_current_mapping(mesh, face, u, v, origin);
			write_packed_mapping(p_edit, face, u, v, origin, placement, scale, p_texture_resolution);
		}
	}
	result.fault = p_edit.last_fault();
	result.island_count = island;
	return result;
}

UvProjectionResult reset_uv_projection(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, UvAxis p_axis) {
	UvProjectionResult result;
	const Mesh &mesh = p_edit.scratch();
	std::unordered_set<uint32_t> selected;
	if (p_faces.empty() || int(p_axis) < int(UvAxis::AUTO) || int(p_axis) > int(UvAxis::Z)) {
		result.fault = invalid_selection();
		return result;
	}
	for (const FaceId face : p_faces) {
		if (!mesh.alive(face) || !selected.insert(face.slot).second) { result.fault = invalid_selection(); return result; }
		std::vector<CornerAttrs> corners;
		mesh.face_corner_attrs(face, corners);
		for (const CornerAttrs &corner : corners) {
			if (!corner.uv_pinned) continue;
			result.fault = invalid_selection();
			result.pinned_conflict = true;
			result.refuse_reason = "Projection reset would replace pinned UVs. Unpin the selected corners first.";
			return result;
		}
	}
	for (const FaceId face : p_faces) {
		FaceAttrs attrs = mesh.attrs(face);
		attrs.uv_unwrapped = false;
		attrs.uv_texture_resolution = 0;
		attrs.uv_axis = p_axis;
		attrs.uv_scale = godot::Vector2(1, 1);
		attrs.uv_offset = godot::Vector2();
		attrs.uv_rotation = 0;
		attrs.uv_u = godot::Vector3();
		attrs.uv_v = godot::Vector3();
		attrs.uv_origin = godot::Vector2();
		p_edit.set_attrs(face, attrs);
		std::vector<CornerAttrs> corners;
		mesh.face_corner_attrs(face, corners);
		for (size_t i = 0; i < corners.size(); ++i) {
			corners[i].uv_explicit = false;
			corners[i].uv_pinned = false;
			corners[i].uv = godot::Vector2();
			p_edit.set_corner_attrs(face, uint32_t(i), corners[i]);
		}
	}
	result.fault = p_edit.last_fault();
	return result;
}

} // namespace ops
} // namespace slab
