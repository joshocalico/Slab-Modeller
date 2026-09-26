#include "region.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <set>
#include <unordered_map>
#include <unordered_set>

namespace slab::ops {
namespace {

struct SourceFace { FaceId id; FaceAttrs attrs; std::vector<VertexId> corners; };
struct BoundaryEdge { VertexId a; VertexId b; FaceAttrs attrs; CornerAttrs corner_a; CornerAttrs corner_b; };
struct Region {
	std::vector<SourceFace> faces;
	std::vector<BoundaryEdge> boundary;
	std::unordered_set<uint32_t> selected;
	godot::Vector3 normal;
};

MeshFault bad(MeshError p_code, uint32_t p_slot = INVALID_IDX) {
	MeshFault out; out.code = p_code; out.slot = p_slot; return out;
}

uint64_t pair_key(uint32_t p_a, uint32_t p_b) {
	if (p_a > p_b) std::swap(p_a, p_b);
	return (uint64_t(p_a) << 32) | p_b;
}

MeshFault inspect(const Mesh &p_mesh, const std::vector<FaceId> &p_faces, Region &r_region) {
	if (p_faces.empty() || p_faces.size() >= size_t(p_mesh.face_count())) return bad(MeshError::INVALID_SELECTION);
	for (const FaceId id : p_faces) {
		if (!p_mesh.alive(id)) return bad(MeshError::STALE_HANDLE, id.slot);
		if (!r_region.selected.insert(id.slot).second) return bad(MeshError::INVALID_SELECTION, id.slot);
		SourceFace face{ id, p_mesh.attrs(id), {} };
		p_mesh.face_corners(id, face.corners);
		if (face.corners.size() < 3) return bad(MeshError::DEGENERATE_FACE, id.slot);
		r_region.faces.push_back(face);
		r_region.normal += p_mesh.face_normal(id) * float(p_mesh.face_area(id));
	}
	std::unordered_map<uint32_t, std::vector<uint32_t>> graph;
	std::vector<EdgeId> edges; p_mesh.all_edges(edges);
	for (const EdgeId edge : edges) {
		FaceId fa, fb; p_mesh.edge_faces(edge, fa, fb);
		const bool sa = r_region.selected.count(fa.slot), sb = r_region.selected.count(fb.slot);
		if (sa && sb) { graph[fa.slot].push_back(fb.slot); graph[fb.slot].push_back(fa.slot); continue; }
		if (!sa && !sb) continue;
		const FaceId owner = sa ? fa : fb;
		const SourceFace *source = nullptr;
		for (const SourceFace &candidate : r_region.faces) if (candidate.id.slot == owner.slot) source = &candidate;
		VertexId ea, eb; p_mesh.edge_vertices(edge, ea, eb);
		for (size_t i = 0; source && i < source->corners.size(); i++) {
			const VertexId a = source->corners[i], b = source->corners[(i + 1) % source->corners.size()];
			if (pair_key(a.slot, b.slot) == pair_key(ea.slot, eb.slot)) {
				std::vector<CornerAttrs> corners;
				p_mesh.face_corner_attrs(owner, corners);
				r_region.boundary.push_back({ a, b, source->attrs, corners[i], corners[(i+1)%corners.size()] });
				break;
			}
		}
	}
	std::unordered_set<uint32_t> reached;
	std::vector<uint32_t> stack{ p_faces[0].slot };
	while (!stack.empty()) {
		const uint32_t at = stack.back(); stack.pop_back();
		if (!reached.insert(at).second) continue;
		for (uint32_t next : graph[at]) stack.push_back(next);
	}
	if (reached.size() != r_region.selected.size() || r_region.boundary.empty()) return bad(MeshError::INVALID_SELECTION);
	if (r_region.normal.length_squared() == 0.0f) return bad(MeshError::DEGENERATE_FACE);
	r_region.normal.normalize();
	return {};
}

bool coplanar(const Mesh &p_mesh, const Region &p_region) {
	const SourceFace &first = p_region.faces[0];
	const godot::Vector3 normal = p_mesh.face_normal(first.id);
	const IVec3 a = p_mesh.position_i(first.corners[0]);
	IVec3 b, c;
	bool plane_found = false;
	for (size_t i = 1; i + 1 < first.corners.size() && !plane_found; i++) {
		b = p_mesh.position_i(first.corners[i]);
		c = p_mesh.position_i(first.corners[i + 1]);
		const int64_t ux = int64_t(b.x) - a.x, uy = int64_t(b.y) - a.y, uz = int64_t(b.z) - a.z;
		const int64_t vx = int64_t(c.x) - a.x, vy = int64_t(c.y) - a.y, vz = int64_t(c.z) - a.z;
		plane_found = (__int128)uy * vz - (__int128)uz * vy != 0 ||
				(__int128)uz * vx - (__int128)ux * vz != 0 ||
				(__int128)ux * vy - (__int128)uy * vx != 0;
	}
	if (!plane_found) return false;
	for (const SourceFace &face : p_region.faces) {
		if (normal.dot(p_mesh.face_normal(face.id)) < 0.99999f) return false;
		for (const VertexId vertex : face.corners) if (orient3d(a, b, c, p_mesh.position_i(vertex)) != 0) return false;
	}
	return true;
}

VertexId find_vertex(const Region &p_region, uint32_t p_slot) {
	for (const SourceFace &face : p_region.faces) for (const VertexId vertex : face.corners) if (vertex.slot == p_slot) return vertex;
	return {};
}

bool offset_boundary(const Mesh &p_mesh, const Region &p_region, float p_amount, std::unordered_map<uint32_t, IVec3> &r_moved) {
	std::unordered_map<uint32_t, uint32_t> next, prev;
	for (const BoundaryEdge &edge : p_region.boundary) {
		if ((next.count(edge.a.slot) && next[edge.a.slot] != edge.b.slot) || (prev.count(edge.b.slot) && prev[edge.b.slot] != edge.a.slot)) return false;
		next[edge.a.slot] = edge.b.slot; prev[edge.b.slot] = edge.a.slot;
	}
	if (next.size() != prev.size()) return false;
	for (const auto &entry : next) {
		const uint32_t at = entry.first;
		if (!prev.count(at)) return false;
		const VertexId current = find_vertex(p_region, at), before = find_vertex(p_region, prev[at]), after = find_vertex(p_region, entry.second);
		if (!p_mesh.alive(current) || !p_mesh.alive(before) || !p_mesh.alive(after)) return false;
		const godot::Vector3 p = p_mesh.position(current);
		const godot::Vector3 incoming = (p - p_mesh.position(before)).normalized();
		const godot::Vector3 outgoing = (p_mesh.position(after) - p).normalized();
		const godot::Vector3 ia = p_region.normal.cross(incoming), ib = p_region.normal.cross(outgoing);
		const float span = 1.0f + ia.dot(ib);
		if (span <= 0.000001f || !quantize(p + (ia + ib) * (p_amount / span), r_moved[at])) return false;
	}
	std::set<IVec3> unique;
	for (const auto &entry : r_moved) if (!unique.insert(entry.second).second) return false;
	return true;
}

MeshFault rebuild(MeshEdit &p_edit, const Region &p_region, const std::unordered_map<uint32_t, IVec3> &p_moved) {
	const Mesh &source = p_edit.scratch();
	std::vector<FaceId> all; source.all_faces(all);
	std::vector<std::vector<IVec3>> loops;
	std::vector<FaceAttrs> attrs;
	std::vector<std::vector<CornerAttrs>> corner_attrs;
	for (const FaceId face : all) {
		std::vector<VertexId> corners; source.face_corners(face, corners);
		std::vector<IVec3> loop;
		for (const VertexId vertex : corners) {
			const auto moved = p_moved.find(vertex.slot);
			loop.push_back(p_region.selected.count(face.slot) && moved != p_moved.end() ? moved->second : source.position_i(vertex));
		}
		loops.push_back(loop); attrs.push_back(source.attrs(face));
		corner_attrs.emplace_back();
		source.face_corner_attrs(face, corner_attrs.back());
	}
	for (const BoundaryEdge &edge : p_region.boundary) {
		const auto a = p_moved.find(edge.a.slot), b = p_moved.find(edge.b.slot);
		if (a == p_moved.end() || b == p_moved.end()) return bad(MeshError::INVALID_SELECTION);
		loops.push_back({ a->second, source.position_i(edge.a), source.position_i(edge.b), b->second });
		attrs.push_back(edge.attrs);
		CornerAttrs ca, cb;
		ca.surface = edge.corner_a.surface;
		cb.surface = edge.corner_b.surface;
		ca.surface.flags &= ~(SurfaceAttrs::NORMAL | SurfaceAttrs::TANGENT);
		cb.surface.flags &= ~(SurfaceAttrs::NORMAL | SurfaceAttrs::TANGENT);
		corner_attrs.push_back({ca, ca, cb, cb});
	}
	MeshEdit assembled = MeshEdit::empty();
	const MeshFault made = assembled.assemble(loops);
	if (!made.ok() || assembled.scratch().face_count() != int(loops.size())) return made.ok() ? bad(MeshError::DEGENERATE_FACE) : made;
	std::vector<FaceId> faces; assembled.scratch().all_faces(faces);
	for (size_t i = 0; i < faces.size(); i++) {
		assembled.set_attrs(faces[i], attrs[i]);
		for (uint32_t k = 0; k < corner_attrs[i].size(); ++k)
			assembled.set_corner_attrs(faces[i], k, corner_attrs[i][k]);
	}
	if (!assembled.last_fault().ok()) return assembled.last_fault();
	return p_edit.replace_with(assembled.scratch());
}

} // namespace

MeshFault extrude_region(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, float p_distance) {
	if (!std::isfinite(p_distance) || p_distance == 0.0f) return bad(MeshError::DEGENERATE_FACE);
	Region region; const MeshFault checked = inspect(p_edit.scratch(), p_faces, region);
	if (!checked.ok()) return checked;
	std::unordered_map<uint32_t, IVec3> moved;
	for (const SourceFace &face : region.faces) for (const VertexId vertex : face.corners) {
		IVec3 target;
		if (!quantize(p_edit.scratch().position(vertex) + region.normal * p_distance, target)) return bad(MeshError::COORD_OUT_OF_RANGE, vertex.slot);
		moved[vertex.slot] = target;
	}
	return rebuild(p_edit, region, moved);
}

MeshFault inset_region(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, float p_amount) {
	if (!(p_amount > 0.0f) || !std::isfinite(p_amount)) return bad(MeshError::DEGENERATE_FACE);
	Region region; const MeshFault checked = inspect(p_edit.scratch(), p_faces, region);
	if (!checked.ok()) return checked;
	if (!coplanar(p_edit.scratch(), region)) return bad(MeshError::INVALID_SELECTION);
	float amount = p_amount;
	for (int attempt = 0; attempt < 24; attempt++, amount *= 0.5f) {
		std::unordered_map<uint32_t, IVec3> moved;
		if (!offset_boundary(p_edit.scratch(), region, amount, moved)) continue;
		MeshEdit candidate(p_edit.scratch());
		if (rebuild(candidate, region, moved).ok() && validate(candidate.scratch()).ok()) return p_edit.replace_with(candidate.scratch());
	}
	return bad(MeshError::DEGENERATE_FACE);
}

} // namespace slab::ops
