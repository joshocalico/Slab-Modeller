#include "../rebuild_attributes.hpp"
#include "bevel.hpp"

#include "weld.hpp"

#include <algorithm>
#include <cmath>
#include <vector>

namespace slab {
namespace ops {

namespace {

MeshFault _bad(MeshError p_code, uint32_t p_slot = INVALID_IDX) {
	MeshFault f;
	f.code = p_code;
	f.slot = p_slot;
	return f;
}

void _poison(MeshEdit &p_edit) {
	p_edit.move_vertex(VertexId{}, IVec3{});
}

bool _collinear(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c) {
	const int64_t bx = int64_t(p_b.x) - p_a.x;
	const int64_t by = int64_t(p_b.y) - p_a.y;
	const int64_t bz = int64_t(p_b.z) - p_a.z;
	const int64_t cx = int64_t(p_c.x) - p_a.x;
	const int64_t cy = int64_t(p_c.y) - p_a.y;
	const int64_t cz = int64_t(p_c.z) - p_a.z;
	return by * cz - bz * cy == 0 && bz * cx - bx * cz == 0 && bx * cy - by * cx == 0;
}

__int128 _dist2(const IVec3 &p_a, const IVec3 &p_b) {
	const int64_t dx = int64_t(p_a.x) - p_b.x;
	const int64_t dy = int64_t(p_a.y) - p_b.y;
	const int64_t dz = int64_t(p_a.z) - p_b.z;
	return __int128(dx) * dx + __int128(dy) * dy + __int128(dz) * dz;
}

int64_t _gcd(int64_t p_a, int64_t p_b) {
	while (p_b != 0) {
		const int64_t rest = p_a % p_b;
		p_a = p_b;
		p_b = rest;
	}
	return p_a;
}

bool _offset_along(const IVec3 &p_from, const IVec3 &p_to, int32_t p_dist, IVec3 &r_out) {
	const godot::Vector3 from = dequantize(p_from);
	const godot::Vector3 to = dequantize(p_to);
	const float span = (to - from).length();
	if (span == 0.0f) {
		return false;
	}
	float reach = float(p_dist) / float(LATTICE);
	if (reach > span * 0.45f) {
		reach = span * 0.45f;
	}
	if (!quantize(from + (to - from) * (reach / span), r_out)) {
		return false;
	}
	return !(r_out == p_from) && !(r_out == p_to);
}

int32_t _span_cap(const IVec3 &p_from, const IVec3 &p_to) {
	const float span = (dequantize(p_to) - dequantize(p_from)).length();
	return int32_t(double(span) * 0.45 * double(LATTICE) + 0.5);
}

int32_t _face_rail_cap(const Mesh &p_mesh, EdgeId p_edge, FaceId p_face) {
	std::vector<VertexId> corners;
	std::vector<EdgeId> edges;
	p_mesh.face_corners(p_face, corners);
	p_mesh.face_edges(p_face, edges);
	const int n = int(corners.size());
	if (n < 3 || int(edges.size()) != n) {
		return 0;
	}
	int at = -1;
	for (int k = 0; k < n; k++) {
		if (edges[k].slot == p_edge.slot) {
			at = k;
		}
	}
	if (at < 0) {
		return 0;
	}
	const int32_t head = _span_cap(p_mesh.position_i(corners[at]), p_mesh.position_i(corners[(at + n - 1) % n]));
	const int32_t tail = _span_cap(p_mesh.position_i(corners[(at + 1) % n]), p_mesh.position_i(corners[(at + 2) % n]));
	return head < tail ? head : tail;
}

bool _midway_lattice(const IVec3 &p_a, const IVec3 &p_b, IVec3 &r_out) {
	const int64_t dx = int64_t(p_b.x) - p_a.x;
	const int64_t dy = int64_t(p_b.y) - p_a.y;
	const int64_t dz = int64_t(p_b.z) - p_a.z;
	const int64_t step = _gcd(_gcd(dx < 0 ? -dx : dx, dy < 0 ? -dy : dy), dz < 0 ? -dz : dz);
	if (step < 2) {
		return false;
	}
	const int64_t half = step / 2;
	r_out = IVec3{
		int32_t(int64_t(p_a.x) + half * dx / step),
		int32_t(int64_t(p_a.y) + half * dy / step),
		int32_t(int64_t(p_a.z) + half * dz / step)
	};
	return !(r_out == p_a) && !(r_out == p_b);
}

struct SidePlan {
	FaceId face;
	EdgeId rail_u;
	EdgeId rail_v;
	IVec3 cut_u;
	IVec3 cut_v;
	VertexId made_u;
	VertexId made_v;
};

struct BevelPlan {
	EdgeId edge;
	VertexId u;
	VertexId v;
	IVec3 u_origin;
	IVec3 v_origin;
	IVec3 u_seat;
	IVec3 v_seat;
	SidePlan side[2];
	std::vector<IVec3> profile_u;
	std::vector<IVec3> profile_v;
};

struct EdgeSeed {
	EdgeId edge;
	IVec3 a;
	IVec3 b;
};

struct FaceLoop {
	std::vector<IVec3> points;
	FaceAttrs attrs;
};

struct ConnectedCorner {
	VertexId vertex;
	FaceId shared_face;
	IVec3 inset;
	IVec3 rail;
	std::vector<IVec3> profile;
};

struct ConnectedPlan {
	std::vector<BevelPlan> edges;
	std::vector<ConnectedCorner> corners;
	std::vector<int> corner_u;
	std::vector<int> corner_v;
};

bool _same_points(const std::vector<IVec3> &p_a, const std::vector<IVec3> &p_b);

bool _rounded_point(const IVec3 &p_a, const IVec3 &p_control, const IVec3 &p_b, double p_t, IVec3 &r_out) {
	const godot::Vector3 a = dequantize(p_a);
	const godot::Vector3 control = dequantize(p_control);
	const godot::Vector3 b = dequantize(p_b);
	const godot::Vector3 va = a - control;
	const godot::Vector3 vb = b - control;
	const double la = va.length();
	const double lb = vb.length();
	if (!(la > 0.0) || !(lb > 0.0)) {
		return false;
	}
	double cosine = double(va.dot(vb)) / (la * lb);
	cosine = std::max(-1.0, std::min(1.0, cosine));
	const double weight = std::sqrt(std::max(0.0, (1.0 + cosine) * 0.5));
	if (!(weight > 0.01)) {
		return false;
	}
	const double one = 1.0 - p_t;
	const double denominator = one * one + 2.0 * weight * one * p_t + p_t * p_t;
	const godot::Vector3 point = (a * float(one * one) + control * float(2.0 * weight * one * p_t) + b * float(p_t * p_t)) / float(denominator);
	return quantize(point, r_out) && r_out != p_a && r_out != p_b;
}

bool _plan_profiles(BevelPlan &r_plan, int p_segments) {
	r_plan.profile_u.resize(size_t(p_segments + 1));
	r_plan.profile_v.resize(size_t(p_segments + 1));
	r_plan.profile_u.front() = r_plan.side[0].cut_u;
	r_plan.profile_u.back() = r_plan.side[1].cut_u;
	r_plan.profile_v.front() = r_plan.side[0].cut_v;
	r_plan.profile_v.back() = r_plan.side[1].cut_v;
	for (int i = 1; i < p_segments; i++) {
		const double t = double(i) / double(p_segments);
		if (!_rounded_point(r_plan.profile_u.front(), r_plan.u_origin, r_plan.profile_u.back(), t, r_plan.profile_u[size_t(i)]) ||
				!_rounded_point(r_plan.profile_v.front(), r_plan.v_origin, r_plan.profile_v.back(), t, r_plan.profile_v[size_t(i)])) {
			return false;
		}
		if (r_plan.profile_u[size_t(i)] == r_plan.profile_u[size_t(i - 1)] ||
				r_plan.profile_v[size_t(i)] == r_plan.profile_v[size_t(i - 1)]) {
			return false;
		}
	}
	return true;
}

MeshFault _plan_side(const Mesh &p_mesh, EdgeId p_edge, FaceId p_face, VertexId p_u, int32_t p_dist, SidePlan &r_out) {
	std::vector<VertexId> corners;
	std::vector<EdgeId> edges;
	p_mesh.face_corners(p_face, corners);
	p_mesh.face_edges(p_face, edges);
	const int n = int(corners.size());
	if (n < 3 || int(edges.size()) != n) {
		return _bad(MeshError::LOOP_TOO_SHORT, p_face.slot);
	}
	int at = -1;
	for (int k = 0; k < n; k++) {
		if (edges[k].slot == p_edge.slot) {
			at = k;
		}
	}
	if (at < 0) {
		return _bad(MeshError::INVALID_SELECTION, p_face.slot);
	}
	const VertexId head = corners[at];
	IVec3 seat_head;
	IVec3 seat_tail;
	if (!_offset_along(p_mesh.position_i(head), p_mesh.position_i(corners[(at + n - 1) % n]), p_dist, seat_head)) {
		return _bad(MeshError::DEGENERATE_FACE, p_face.slot);
	}
	if (!_offset_along(p_mesh.position_i(corners[(at + 1) % n]), p_mesh.position_i(corners[(at + 2) % n]), p_dist, seat_tail)) {
		return _bad(MeshError::DEGENERATE_FACE, p_face.slot);
	}
	const EdgeId rail_head = edges[(at + n - 1) % n];
	const EdgeId rail_tail = edges[(at + 1) % n];

	r_out.face = p_face;
	if (head.slot == p_u.slot) {
		r_out.rail_u = rail_head;
		r_out.cut_u = seat_head;
		r_out.rail_v = rail_tail;
		r_out.cut_v = seat_tail;
	} else {
		r_out.rail_u = rail_tail;
		r_out.cut_u = seat_tail;
		r_out.rail_v = rail_head;
		r_out.cut_v = seat_head;
	}
	return MeshFault{};
}

MeshFault _plan_bevel(const Mesh &p_mesh, EdgeId p_edge, int32_t p_dist, BevelPlan &r_plan) {
	if (!p_mesh.alive(p_edge)) {
		return _bad(MeshError::STALE_HANDLE, p_edge.slot);
	}
	FaceId left;
	FaceId right;
	p_mesh.edge_faces(p_edge, left, right);
	if (!p_mesh.alive(left) || !p_mesh.alive(right)) {
		return _bad(MeshError::NOT_CLOSED, p_edge.slot);
	}
	VertexId u;
	VertexId v;
	p_mesh.edge_vertices(p_edge, u, v);
	if (!p_mesh.alive(u) || !p_mesh.alive(v)) {
		return _bad(MeshError::STALE_HANDLE, p_edge.slot);
	}
	std::vector<EdgeId> ring;
	p_mesh.vertex_edges(u, ring);
	if (ring.size() != 3) {
		return _bad(MeshError::NON_MANIFOLD_VERTEX, u.slot);
	}
	p_mesh.vertex_edges(v, ring);
	if (ring.size() != 3) {
		return _bad(MeshError::NON_MANIFOLD_VERTEX, v.slot);
	}
	r_plan.edge = p_edge;
	r_plan.u = u;
	r_plan.v = v;
	r_plan.u_origin = p_mesh.position_i(u);
	r_plan.v_origin = p_mesh.position_i(v);
	int32_t dist = p_dist;
	const int32_t left_cap = _face_rail_cap(p_mesh, p_edge, left);
	const int32_t right_cap = _face_rail_cap(p_mesh, p_edge, right);
	if (left_cap < dist) {
		dist = left_cap;
	}
	if (right_cap < dist) {
		dist = right_cap;
	}
	if (dist < 2) {
		return _bad(MeshError::DEGENERATE_FACE, p_edge.slot);
	}
	const FaceId faces[2] = { left, right };
	for (int i = 0; i < 2; i++) {
		const MeshFault planned = _plan_side(p_mesh, p_edge, faces[i], u, dist, r_plan.side[i]);
		if (!planned.ok()) {
			return planned;
		}
	}
	const uint32_t rails[4] = {
		r_plan.side[0].rail_u.slot,
		r_plan.side[0].rail_v.slot,
		r_plan.side[1].rail_u.slot,
		r_plan.side[1].rail_v.slot
	};
	for (int i = 0; i < 4; i++) {
		for (int j = i + 1; j < 4; j++) {
			if (rails[i] == rails[j]) {
				return _bad(MeshError::DEGENERATE_FACE, p_edge.slot);
			}
		}
	}

	const IVec3 au = r_plan.side[0].cut_u;
	const IVec3 av = r_plan.side[0].cut_v;
	const IVec3 bu = r_plan.side[1].cut_u;
	const IVec3 bv = r_plan.side[1].cut_v;
	if (_collinear(au, bu, av) || orient3d(au, bu, av, bv) != 0) {
		return _bad(MeshError::DEGENERATE_FACE, p_edge.slot);
	}
	if (!_midway_lattice(au, bu, r_plan.u_seat) || !_midway_lattice(av, bv, r_plan.v_seat)) {
		return _bad(MeshError::DEGENERATE_FACE, p_edge.slot);
	}
	return MeshFault{};
}

int _selected_plan_at(const ConnectedPlan &p_plan, EdgeId p_edge) {
	for (size_t i = 0; i < p_plan.edges.size(); i++) {
		if (p_plan.edges[i].edge.slot == p_edge.slot) return int(i);
	}
	return -1;
}

bool _line_intersection(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c, const IVec3 &p_d, IVec3 &r_out) {
	const godot::Vector3 a = dequantize(p_a);
	const godot::Vector3 b = dequantize(p_b);
	const godot::Vector3 c = dequantize(p_c);
	const godot::Vector3 d = dequantize(p_d);
	const godot::Vector3 u = b - a;
	const godot::Vector3 v = d - c;
	const godot::Vector3 w = a - c;
	const double uu = u.dot(u);
	const double uv = u.dot(v);
	const double vv = v.dot(v);
	const double uw = u.dot(w);
	const double vw = v.dot(w);
	const double denominator = uu * vv - uv * uv;
	if (std::abs(denominator) < 1e-12) return false;
	const double t = (uv * vw - vv * uw) / denominator;
	const double s = (uu * vw - uv * uw) / denominator;
	const godot::Vector3 on_u = a + u * float(t);
	const godot::Vector3 on_v = c + v * float(s);
	if ((on_u - on_v).length() > 1.5f / float(LATTICE)) return false;
	return quantize((on_u + on_v) * 0.5f, r_out);
}

FaceId _shared_face(const BevelPlan &p_a, const BevelPlan &p_b) {
	for (const SidePlan &a : p_a.side) {
		for (const SidePlan &b : p_b.side) if (a.face.slot == b.face.slot) return a.face;
	}
	return FaceId{};
}

const SidePlan *_side_on(const BevelPlan &p_plan, FaceId p_face) {
	for (const SidePlan &side : p_plan.side) if (side.face.slot == p_face.slot) return &side;
	return nullptr;
}

IVec3 _endpoint_cut(const BevelPlan &p_plan, const SidePlan &p_side, VertexId p_vertex) {
	return p_vertex.slot == p_plan.u.slot ? p_side.cut_u : p_side.cut_v;
}

MeshFault _plan_connected(const Mesh &p_mesh, const std::vector<EdgeId> &p_edges, int32_t p_dist,
		int p_segments, ConnectedPlan &r_plan) {
	r_plan.edges.resize(p_edges.size());
	r_plan.corner_u.assign(p_edges.size(), -1);
	r_plan.corner_v.assign(p_edges.size(), -1);
	for (size_t i = 0; i < p_edges.size(); i++) {
		const MeshFault fault = _plan_bevel(p_mesh, p_edges[i], p_dist, r_plan.edges[i]);
		if (!fault.ok()) return fault;
		if (!_plan_profiles(r_plan.edges[i], p_segments)) return _bad(MeshError::SNAP_COLLAPSED_TOPOLOGY, p_edges[i].slot);
	}
	std::vector<VertexId> vertices;
	p_mesh.all_vertices(vertices);
	for (const VertexId vertex : vertices) {
		std::vector<EdgeId> ring;
		p_mesh.vertex_edges(vertex, ring);
		std::vector<int> selected;
		for (const EdgeId edge : ring) {
			const int at = _selected_plan_at(r_plan, edge);
			if (at >= 0) selected.push_back(at);
		}
		if (selected.size() < 2) continue;
		if (selected.size() != 2 || ring.size() != 3) return _bad(MeshError::NON_MANIFOLD_VERTEX, vertex.slot);
		BevelPlan &a = r_plan.edges[size_t(selected[0])];
		BevelPlan &b = r_plan.edges[size_t(selected[1])];
		const FaceId shared = _shared_face(a, b);
		if (!p_mesh.alive(shared)) return _bad(MeshError::INVALID_SELECTION, vertex.slot);
		const SidePlan *side_a = _side_on(a, shared);
		const SidePlan *side_b = _side_on(b, shared);
		if (side_a == nullptr || side_b == nullptr) return _bad(MeshError::INVALID_SELECTION, vertex.slot);
		IVec3 inset;
		if (!_line_intersection(side_a->cut_u, side_a->cut_v, side_b->cut_u, side_b->cut_v, inset)) {
			return _bad(MeshError::DEGENERATE_FACE, vertex.slot);
		}
		const SidePlan *other_a = side_a == &a.side[0] ? &a.side[1] : &a.side[0];
		const SidePlan *other_b = side_b == &b.side[0] ? &b.side[1] : &b.side[0];
		const IVec3 rail_a = _endpoint_cut(a, *other_a, vertex);
		const IVec3 rail_b = _endpoint_cut(b, *other_b, vertex);
		if (rail_a != rail_b) return _bad(MeshError::DEGENERATE_FACE, vertex.slot);
		ConnectedCorner corner;
		corner.vertex = vertex;
		corner.shared_face = shared;
		corner.inset = inset;
		corner.rail = rail_a;
		corner.profile.resize(size_t(p_segments + 1));
		corner.profile.front() = inset;
		corner.profile.back() = rail_a;
		for (int segment = 1; segment < p_segments; segment++) {
			if (!_rounded_point(inset, p_mesh.position_i(vertex), rail_a,
					double(segment) / double(p_segments), corner.profile[size_t(segment)])) {
				return _bad(MeshError::SNAP_COLLAPSED_TOPOLOGY, vertex.slot);
			}
		}
		const int corner_at = int(r_plan.corners.size());
		r_plan.corners.push_back(corner);
		for (const int edge_at : selected) {
			BevelPlan &edge = r_plan.edges[size_t(edge_at)];
			if (edge.u.slot == vertex.slot) r_plan.corner_u[size_t(edge_at)] = corner_at;
			else r_plan.corner_v[size_t(edge_at)] = corner_at;
		}
	}
	return MeshFault{};
}

std::vector<IVec3> _edge_profile(const ConnectedPlan &p_plan, size_t p_edge_at, bool p_u) {
	const int corner_at = p_u ? p_plan.corner_u[p_edge_at] : p_plan.corner_v[p_edge_at];
	const BevelPlan &edge = p_plan.edges[p_edge_at];
	if (corner_at < 0) return p_u ? edge.profile_u : edge.profile_v;
	std::vector<IVec3> profile = p_plan.corners[size_t(corner_at)].profile;
	const FaceId first_face = edge.side[0].face;
	if (first_face.slot != p_plan.corners[size_t(corner_at)].shared_face.slot) std::reverse(profile.begin(), profile.end());
	return profile;
}

const ConnectedCorner *_corner_at(const ConnectedPlan &p_plan, VertexId p_vertex) {
	for (const ConnectedCorner &corner : p_plan.corners) if (corner.vertex.slot == p_vertex.slot) return &corner;
	return nullptr;
}

int _selected_endpoint_at(const ConnectedPlan &p_plan, VertexId p_vertex) {
	for (size_t i = 0; i < p_plan.edges.size(); i++) {
		if (p_plan.edges[i].u.slot == p_vertex.slot || p_plan.edges[i].v.slot == p_vertex.slot) return int(i);
	}
	return -1;
}

MeshFault _assemble_connected(MeshEdit &p_edit, const ConnectedPlan &p_plan, int p_segments) {
	const Mesh &source_mesh = p_edit.scratch();
	std::vector<FaceLoop> emitted;
	std::vector<FaceId> faces;
	source_mesh.all_faces(faces);
	for (const FaceId face : faces) {
		std::vector<VertexId> corners;
		std::vector<EdgeId> edges;
		source_mesh.face_corners(face, corners);
		source_mesh.face_edges(face, edges);
		FaceLoop retained;
		retained.attrs = source_mesh.attrs(face);
		for (size_t i = 0; i < corners.size(); i++) {
			const size_t prev = (i + corners.size() - 1) % corners.size();
			const int incoming = _selected_plan_at(p_plan, edges[prev]);
			const int outgoing = _selected_plan_at(p_plan, edges[i]);
			const ConnectedCorner *joint = _corner_at(p_plan, corners[i]);
			if (incoming >= 0 && outgoing >= 0 && joint != nullptr && joint->shared_face.slot == face.slot) {
				retained.points.push_back(joint->inset);
			} else if (incoming >= 0 || outgoing >= 0) {
				const int edge_at = outgoing >= 0 ? outgoing : incoming;
				const BevelPlan &edge = p_plan.edges[size_t(edge_at)];
				const SidePlan *side = _side_on(edge, face);
				if (side == nullptr) return _bad(MeshError::INVALID_SELECTION, face.slot);
				retained.points.push_back(_endpoint_cut(edge, *side, corners[i]));
			} else {
				const int endpoint = _selected_endpoint_at(p_plan, corners[i]);
				if (endpoint >= 0) {
					const BevelPlan &edge = p_plan.edges[size_t(endpoint)];
					std::vector<IVec3> profile = _edge_profile(p_plan, size_t(endpoint), edge.u.slot == corners[i].slot);
					const IVec3 previous = source_mesh.position_i(corners[prev]);
					const IVec3 origin = source_mesh.position_i(corners[i]);
					if (!_collinear(previous, origin, profile.front())) std::reverse(profile.begin(), profile.end());
					if (!_collinear(previous, origin, profile.front())) return _bad(MeshError::DEGENERATE_FACE, corners[i].slot);
					retained.points.insert(retained.points.end(), profile.begin(), profile.end());
					continue;
				}
				retained.points.push_back(source_mesh.position_i(corners[i]));
			}
		}
		emitted.push_back(retained);
	}
	for (size_t edge_at = 0; edge_at < p_plan.edges.size(); edge_at++) {
		const BevelPlan &edge = p_plan.edges[edge_at];
		const std::vector<IVec3> u = _edge_profile(p_plan, edge_at, true);
		const std::vector<IVec3> v = _edge_profile(p_plan, edge_at, false);
		for (int segment = 0; segment < p_segments; segment++) {
			FaceLoop band;
			band.attrs = source_mesh.attrs(edge.side[0].face);
			band.points = { u[size_t(segment)], u[size_t(segment + 1)], v[size_t(segment + 1)], v[size_t(segment)] };
			emitted.push_back(band);
		}
	}
	std::vector<std::vector<IVec3>> loops;
	for (const FaceLoop &face : emitted) loops.push_back(face.points);
	// assemble() carries seam flags by unchanged geometric edge pairs from its current mesh.
	MeshEdit candidate(source_mesh);
	const MeshFault assembled = candidate.assemble(loops);
	if (!assembled.ok()) return assembled;
	std::vector<FaceId> made_faces;
	candidate.scratch().all_faces(made_faces);
	for (const FaceId face : made_faces) {
		std::vector<VertexId> corners;
		candidate.scratch().face_corners(face, corners);
		std::vector<IVec3> points;
		for (const VertexId corner : corners) points.push_back(candidate.scratch().position_i(corner));
		bool matched = false;
		for (const FaceLoop &item : emitted) {
			if (_same_points(points, item.points)) {
				candidate.set_attrs(face, item.attrs);
				matched = true;
				break;
			}
		}
		if (!matched) return _bad(MeshError::CORRUPT_DATA, face.slot);
	}
	Mesh result;
	const MeshFault committed = std::move(candidate).commit(result);
	if (!committed.ok()) return committed;
	return p_edit.replace_with(result);
}

MeshFault _retire_seat(MeshEdit &p_edit, VertexId p_seat) {
	std::vector<EdgeId> ring;
	p_edit.scratch().vertex_edges(p_seat, ring);
	if (ring.size() != 2) {
		return _bad(MeshError::NON_MANIFOLD_VERTEX, p_seat.slot);
	}
	for (const EdgeId id : ring) {
		VertexId keep;
		VertexId kill;
		p_edit.scratch().edge_vertices(id, keep, kill);
		if (kill.slot == p_seat.slot) {
			return p_edit.collapse_edge(id);
		}
	}
	VertexId keep;
	VertexId kill;
	p_edit.scratch().edge_vertices(ring[0], keep, kill);
	p_edit.move_vertex(keep, p_edit.scratch().position_i(kill));
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	return p_edit.collapse_edge(ring[0]);
}

MeshFault _apply_bevel(MeshEdit &p_edit, BevelPlan &r_plan) {
	for (int i = 0; i < 2; i++) {
		SidePlan &side = r_plan.side[i];
		side.made_u = p_edit.split_edge(side.rail_u, side.cut_u);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
		side.made_v = p_edit.split_edge(side.rail_v, side.cut_v);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	for (int i = 0; i < 2; i++) {
		p_edit.split_face(r_plan.side[i].face, r_plan.side[i].made_u, r_plan.side[i].made_v);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	p_edit.move_vertex(r_plan.u, r_plan.u_seat);
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	p_edit.move_vertex(r_plan.v, r_plan.v_seat);
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	const MeshFault dissolved = p_edit.dissolve_edge(r_plan.edge);
	if (!dissolved.ok()) {
		return dissolved;
	}
	// The dissolve leaves the two seats as collinear midpoints of the chamfer's long sides, which
	// makes face_normal read zero off its first three corners. Retire them to land a clean quad.
	const MeshFault first = _retire_seat(p_edit, r_plan.u);
	if (!first.ok()) {
		return first;
	}
	return _retire_seat(p_edit, r_plan.v);
}

EdgeId _edge_between(const Mesh &p_mesh, VertexId p_a, VertexId p_b) {
	std::vector<EdgeId> edges;
	p_mesh.vertex_edges(p_a, edges);
	for (const EdgeId edge : edges) {
		VertexId a;
		VertexId b;
		p_mesh.edge_vertices(edge, a, b);
		if (a.slot == p_b.slot || b.slot == p_b.slot) {
			return edge;
		}
	}
	return EdgeId{};
}

VertexId _vertex_at(const Mesh &p_mesh, const IVec3 &p_position) {
	std::vector<VertexId> vertices;
	p_mesh.all_vertices(vertices);
	for (const VertexId vertex : vertices) {
		if (p_mesh.position_i(vertex) == p_position) {
			return vertex;
		}
	}
	return VertexId{};
}

EdgeId _remaining_collinear_edge(const Mesh &p_mesh, const IVec3 &p_a, const IVec3 &p_b) {
	std::vector<EdgeId> edges;
	p_mesh.all_edges(edges);
	EdgeId best;
	__int128 best_span = 0;
	const __int128 original_span = _dist2(p_a, p_b);
	for (const EdgeId edge : edges) {
		VertexId va;
		VertexId vb;
		p_mesh.edge_vertices(edge, va, vb);
		const IVec3 a = p_mesh.position_i(va);
		const IVec3 b = p_mesh.position_i(vb);
		if (!_collinear(p_a, p_b, a) || !_collinear(p_a, p_b, b) ||
				_dist2(p_a, a) > original_span || _dist2(p_a, b) > original_span ||
				_dist2(p_b, a) > original_span || _dist2(p_b, b) > original_span) {
			continue;
		}
		const __int128 span = _dist2(a, b);
		if (span > best_span) {
			best_span = span;
			best = edge;
		}
	}
	return best;
}

bool _same_points(const std::vector<IVec3> &p_a, const std::vector<IVec3> &p_b) {
	if (p_a.size() != p_b.size()) {
		return false;
	}
	for (const IVec3 &point : p_a) {
		if (std::find(p_b.begin(), p_b.end(), point) == p_b.end()) {
			return false;
		}
	}
	return true;
}

bool _joint_corner(const std::vector<EdgeSeed> &p_seeds) {
	if (p_seeds.size() != 3) return false;
	const IVec3 candidates[2] = { p_seeds[0].a, p_seeds[0].b };
	for (const IVec3 &candidate : candidates) {
		if ((p_seeds[1].a == candidate || p_seeds[1].b == candidate) &&
				(p_seeds[2].a == candidate || p_seeds[2].b == candidate)) return true;
	}
	return false;
}

MeshFault _truncate_joint_corner(MeshEdit &p_edit, const std::vector<EdgeSeed> &p_seeds, int32_t p_dist) {
	if (!_joint_corner(p_seeds)) {
		return MeshFault{};
	}
	IVec3 joint;
	bool found = false;
	const IVec3 candidates[2] = { p_seeds[0].a, p_seeds[0].b };
	for (const IVec3 &candidate : candidates) {
		bool common = true;
		for (size_t i = 1; i < p_seeds.size(); i++) {
			common = common && (p_seeds[i].a == candidate || p_seeds[i].b == candidate);
		}
		if (common) {
			joint = candidate;
			found = true;
			break;
		}
	}
	if (!found) {
		return MeshFault{};
	}

	std::vector<IVec3> neighbours;
	std::vector<IVec3> cuts;
	for (const EdgeSeed &seed : p_seeds) {
		const IVec3 neighbour = seed.a == joint ? seed.b : seed.a;
		IVec3 cut;
		if (!_offset_along(joint, neighbour, p_dist, cut)) {
			return _bad(MeshError::DEGENERATE_FACE, seed.edge.slot);
		}
		neighbours.push_back(neighbour);
		cuts.push_back(cut);
	}

	const Mesh &mesh = p_edit.scratch();
	std::vector<FaceId> faces;
	mesh.all_faces(faces);
	std::vector<FaceLoop> source;
	std::vector<std::vector<IVec3>> loops;
	FaceAttrs cap_attrs;
	bool cap_attrs_set = false;
	for (const FaceId face : faces) {
		std::vector<VertexId> corners;
		mesh.face_corners(face, corners);
		FaceLoop item;
		item.attrs = mesh.attrs(face);
		for (size_t corner_index = 0; corner_index < corners.size(); corner_index++) {
			const VertexId corner = corners[corner_index];
			const IVec3 point = mesh.position_i(corner);
			if (point != joint) {
				item.points.push_back(point);
				continue;
			}
			if (!cap_attrs_set) {
				cap_attrs = item.attrs;
				cap_attrs_set = true;
			}
			const IVec3 prev = mesh.position_i(corners[(corner_index + corners.size() - 1) % corners.size()]);
			const IVec3 next = mesh.position_i(corners[(corner_index + 1) % corners.size()]);
			for (size_t i = 0; i < neighbours.size(); i++) {
				if (neighbours[i] == prev) item.points.push_back(cuts[i]);
			}
			for (size_t i = 0; i < neighbours.size(); i++) {
				if (neighbours[i] == next) item.points.push_back(cuts[i]);
			}
		}
		loops.push_back(item.points);
		source.push_back(item);
	}

	MeshEdit rebuilt = MeshEdit::empty();
	const MeshFault assembled = rebuilt.assemble(loops);
	if (!assembled.ok()) {
		return assembled;
	}
	std::vector<FaceId> rebuilt_faces;
	rebuilt.scratch().all_faces(rebuilt_faces);
	for (const FaceId face : rebuilt_faces) {
		std::vector<VertexId> corners;
		rebuilt.scratch().face_corners(face, corners);
		std::vector<IVec3> points;
		for (const VertexId corner : corners) points.push_back(rebuilt.scratch().position_i(corner));
		bool matched = false;
		for (const FaceLoop &item : source) {
			if (_same_points(points, item.points)) {
				rebuilt.set_attrs(face, item.attrs);
				matched = true;
				break;
			}
		}
		if (!matched && cap_attrs_set) {
			rebuilt.set_attrs(face, cap_attrs);
		}
	}
	return p_edit.replace_with(rebuilt.scratch());
}

MeshFault _apply_segments(MeshEdit &p_edit, BevelPlan &r_plan, int p_segments) {
	std::vector<VertexId> made_u(size_t(p_segments + 1));
	std::vector<VertexId> made_v(size_t(p_segments + 1));
	made_u.front() = _vertex_at(p_edit.scratch(), r_plan.profile_u.front());
	made_u.back() = _vertex_at(p_edit.scratch(), r_plan.profile_u.back());
	made_v.front() = _vertex_at(p_edit.scratch(), r_plan.profile_v.front());
	made_v.back() = _vertex_at(p_edit.scratch(), r_plan.profile_v.back());
	if (!p_edit.scratch().alive(made_u.front()) || !p_edit.scratch().alive(made_u.back()) ||
			!p_edit.scratch().alive(made_v.front()) || !p_edit.scratch().alive(made_v.back())) {
		_poison(p_edit);
		return p_edit.last_fault();
	}
	VertexId upper_u = made_u.back();
	VertexId upper_v = made_v.back();
	for (int i = p_segments - 1; i > 0; i--) {
		const EdgeId edge_u = _edge_between(p_edit.scratch(), made_u.front(), upper_u);
		const EdgeId edge_v = _edge_between(p_edit.scratch(), made_v.front(), upper_v);
		if (!p_edit.scratch().alive(edge_u) || !p_edit.scratch().alive(edge_v)) {
			_poison(p_edit);
			return p_edit.last_fault();
		}
		made_u[size_t(i)] = p_edit.split_edge(edge_u, r_plan.profile_u[size_t(i)]);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
		made_v[size_t(i)] = p_edit.split_edge(edge_v, r_plan.profile_v[size_t(i)]);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
		upper_u = made_u[size_t(i)];
		upper_v = made_v[size_t(i)];
	}
	for (int i = 1; i < p_segments; i++) {
		const FaceId face = shared_cut_face(p_edit.scratch(), made_u[size_t(i)], made_v[size_t(i)]);
		if (!p_edit.scratch().alive(face)) {
			_poison(p_edit);
			return p_edit.last_fault();
		}
		p_edit.split_face(face, made_u[size_t(i)], made_v[size_t(i)]);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	return p_edit.last_fault();
}

} // namespace

MeshFault bevel(MeshEdit &p_edit, const std::vector<EdgeId> &p_edges, float p_amount) {
	return bevel(p_edit, p_edges, p_amount, 1);
}

static MeshFault bevel_geometry(MeshEdit &p_edit, const std::vector<EdgeId> &p_edges, float p_amount, int p_segments) {
	if (p_edges.empty() || !(p_amount > 0.0f)) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const int32_t dist = int32_t(double(p_amount) * double(LATTICE) + 0.5);
	if (dist < 2) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	for (const EdgeId id : p_edges) {
		if (!p_edit.scratch().alive(id)) {
			return _bad(MeshError::STALE_HANDLE, id.slot);
		}
	}
	for (size_t i = 0; i < p_edges.size(); i++) {
		for (size_t j = i + 1; j < p_edges.size(); j++) {
			if (p_edges[i].slot == p_edges[j].slot) {
				return _bad(MeshError::ADJACENT_SELECTION, p_edges[i].slot);
			}
		}
	}
	std::vector<EdgeSeed> seeds;
	seeds.reserve(p_edges.size());
	for (const EdgeId edge : p_edges) {
		VertexId a;
		VertexId b;
		p_edit.scratch().edge_vertices(edge, a, b);
		seeds.push_back({ edge, p_edit.scratch().position_i(a), p_edit.scratch().position_i(b) });
	}
	const int segments = std::max(BEVEL_SEGMENTS_MIN, std::min(BEVEL_SEGMENTS_MAX, p_segments));
	bool connected = false;
	for (size_t i = 0; i < seeds.size(); i++) {
		for (size_t j = i + 1; j < seeds.size(); j++) {
			connected = connected || seeds[i].a == seeds[j].a || seeds[i].a == seeds[j].b ||
					seeds[i].b == seeds[j].a || seeds[i].b == seeds[j].b;
		}
	}
	if (connected && !_joint_corner(seeds)) {
		ConnectedPlan plan;
		const MeshFault planned = _plan_connected(p_edit.scratch(), p_edges, dist, segments, plan);
		if (!planned.ok()) return planned;
		return _assemble_connected(p_edit, plan, segments);
	}
	const MeshFault joint = _truncate_joint_corner(p_edit, seeds, dist);
	if (!joint.ok()) {
		return joint;
	}
	const bool rebuilt_joint = _joint_corner(seeds);
	for (size_t i = 0; i < p_edges.size(); i++) {
		EdgeId edge = seeds[i].edge;
		if (rebuilt_joint || !p_edit.scratch().alive(edge)) {
			edge = _remaining_collinear_edge(p_edit.scratch(), seeds[i].a, seeds[i].b);
		}
		if (!p_edit.scratch().alive(edge)) {
			if (i > 0) {
				_poison(p_edit);
			}
			return _bad(MeshError::STALE_HANDLE, seeds[i].edge.slot);
		}
		BevelPlan plan;
		const MeshFault planned = _plan_bevel(p_edit.scratch(), edge, dist, plan);
		if (!planned.ok()) {
			if (i > 0) {
				_poison(p_edit);
			}
			return planned;
		}
		if (segments > 1 && !_plan_profiles(plan, segments)) {
			if (i > 0) {
				_poison(p_edit);
			}
			return _bad(MeshError::SNAP_COLLAPSED_TOPOLOGY, edge.slot);
		}
		const MeshFault applied = _apply_bevel(p_edit, plan);
		if (!applied.ok()) {
			return applied;
		}
		if (segments > 1) {
			const MeshFault segmented = _apply_segments(p_edit, plan, segments);
			if (!segmented.ok()) {
				return segmented;
			}
		}
	}
	return p_edit.last_fault();
}

MeshFault bevel(MeshEdit &p_edit, const std::vector<EdgeId> &p_edges, float p_amount, int p_segments) {
	const Mesh source = p_edit.scratch();
	const auto result = bevel_geometry(p_edit, p_edges, p_amount, p_segments);
	if (result.ok() && has_authored_attributes(source)) transfer_rebuilt_attributes(p_edit, {&source}, false);
	return result.ok() ? p_edit.last_fault() : result;
}

} // namespace ops
} // namespace slab
