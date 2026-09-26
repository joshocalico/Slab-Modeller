#include "plane_cut.hpp"

#include "boolean.hpp"
#include "../rebuild_attributes.hpp"

#include <algorithm>
#include <map>
#include <set>
#include <vector>

namespace slab {
namespace ops {
namespace {

struct SourceFace {
	std::vector<IVec3> loop;
	FaceAttrs attrs;
};

MeshFault bad(MeshError p_code) {
	MeshFault result;
	result.code = p_code;
	return result;
}

__int128 side(const IVec3 &p_point, const IVec3 &p_origin, const IVec3 &p_normal) {
	return (__int128(p_point.x) - p_origin.x) * p_normal.x +
			(__int128(p_point.y) - p_origin.y) * p_normal.y +
			(__int128(p_point.z) - p_origin.z) * p_normal.z;
}

IVec3 hit(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_origin, const IVec3 &p_normal) {
	const __int128 sa = side(p_a, p_origin, p_normal);
	const __int128 sb = side(p_b, p_origin, p_normal);
	__int128 den = sb - sa;
	auto lerp = [&](int32_t p_av, int32_t p_bv) -> int32_t {
		__int128 num = __int128(p_av) * den + (__int128(p_bv) - p_av) * -sa;
		__int128 d = den;
		if (d < 0) {
			d = -d;
			num = -num;
		}
		if (num >= 0) {
			return int32_t((num + d / 2) / d);
		}
		return int32_t((num - d / 2) / d);
	};
	return IVec3{ lerp(p_a.x, p_b.x), lerp(p_a.y, p_b.y), lerp(p_a.z, p_b.z) };
}

std::vector<IVec3> clipped(const std::vector<IVec3> &p_loop, const IVec3 &p_origin,
		const IVec3 &p_normal, PlaneSide p_keep) {
	std::vector<IVec3> out;
	for (size_t i = 0; i < p_loop.size(); ++i) {
		const IVec3 &a = p_loop[i];
		const IVec3 &b = p_loop[(i + 1) % p_loop.size()];
		const __int128 sa = side(a, p_origin, p_normal);
		const __int128 sb = side(b, p_origin, p_normal);
		const bool ina = p_keep == PlaneSide::POSITIVE ? sa >= 0 : sa <= 0;
		const bool inb = p_keep == PlaneSide::POSITIVE ? sb >= 0 : sb <= 0;
		if (ina) {
			out.push_back(a);
		}
		if (ina != inb && sa != 0 && sb != 0) {
			out.push_back(hit(a, b, p_origin, p_normal));
		}
	}
	std::vector<IVec3> clean;
	for (const IVec3 &p : out) {
		if (clean.empty() || clean.back() != p) {
			clean.push_back(p);
		}
	}
	if (clean.size() > 1 && clean.front() == clean.back()) {
		clean.pop_back();
	}
	return clean;
}

void box_faces(const IVec3 &p_lo, const IVec3 &p_hi, std::vector<std::vector<IVec3>> &r_faces) {
	const int32_t x0 = p_lo.x, y0 = p_lo.y, z0 = p_lo.z;
	const int32_t x1 = p_hi.x, y1 = p_hi.y, z1 = p_hi.z;
	r_faces = {
		{ { x0, y0, z0 }, { x0, y0, z1 }, { x0, y1, z1 }, { x0, y1, z0 } },
		{ { x1, y0, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, { x1, y0, z1 } },
		{ { x0, y0, z0 }, { x1, y0, z0 }, { x1, y0, z1 }, { x0, y0, z1 } },
		{ { x0, y1, z0 }, { x0, y1, z1 }, { x1, y1, z1 }, { x1, y1, z0 } },
		{ { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, { x1, y0, z0 } },
		{ { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 } },
	};
}

void close_boundary(std::vector<std::vector<IVec3>> &p_faces, const IVec3 &p_origin, const IVec3 &p_normal) {
	using Segment = std::pair<IVec3, IVec3>;
	std::set<Segment> edges;
	for (const auto &face : p_faces) {
		for (size_t i = 0; i < face.size(); ++i) {
			edges.insert({ face[i], face[(i + 1) % face.size()] });
		}
	}
	std::map<IVec3, IVec3> boundary;
	for (const Segment &edge : edges) {
		if (edges.find({ edge.second, edge.first }) == edges.end()) {
			boundary[edge.first] = edge.second;
		}
	}
	if (boundary.size() < 3) return;
	std::vector<IVec3> cycle;
	const IVec3 start = boundary.begin()->first;
	IVec3 current = start;
	do {
		cycle.push_back(current);
		const auto next = boundary.find(current);
		if (next == boundary.end()) return;
		current = next->second;
	} while (current != start && cycle.size() <= boundary.size());
	if (current != start || cycle.size() < 3) return;
	bool exactly_planar = true;
	for (const IVec3 &p : cycle) exactly_planar &= side(p, p_origin, p_normal) == 0;
	if (exactly_planar) {
		std::vector<IVec3> cap;
		cap.push_back(cycle[0]);
		for (size_t i = cycle.size() - 1; i > 0; --i) cap.push_back(cycle[i]);
		p_faces.push_back(std::move(cap));
		return;
	}
	for (size_t i = 1; i + 1 < cycle.size(); ++i) {
		// Boundary edges follow the side faces, so the cap uses their reverse.
		p_faces.push_back({ cycle[0], cycle[i + 1], cycle[i] });
	}
}

bool on_source_plane(const std::vector<IVec3> &p_face, const SourceFace &p_source) {
	if (p_source.loop.size() < 3) {
		return false;
	}
	size_t c = 2;
	while (c < p_source.loop.size()) {
		const IVec3 ab{ p_source.loop[1].x - p_source.loop[0].x, p_source.loop[1].y - p_source.loop[0].y, p_source.loop[1].z - p_source.loop[0].z };
		const IVec3 ac{ p_source.loop[c].x - p_source.loop[0].x, p_source.loop[c].y - p_source.loop[0].y, p_source.loop[c].z - p_source.loop[0].z };
		const __int128 nx = __int128(ab.y) * ac.z - __int128(ab.z) * ac.y;
		const __int128 ny = __int128(ab.z) * ac.x - __int128(ab.x) * ac.z;
		const __int128 nz = __int128(ab.x) * ac.y - __int128(ab.y) * ac.x;
		if (nx != 0 || ny != 0 || nz != 0) break;
		++c;
	}
	if (c == p_source.loop.size()) return false;
	for (const IVec3 &p : p_face) {
		if (orient3d(p_source.loop[0], p_source.loop[1], p_source.loop[c], p) != 0) return false;
	}
	return true;
}

void restore_attributes(MeshEdit &p_edit, const std::vector<SourceFace> &p_sources,
		const FaceAttrs &p_cap_attrs) {
	std::vector<FaceId> out_faces;
	p_edit.scratch().all_faces(out_faces);
	for (const FaceId id : out_faces) {
		std::vector<VertexId> corners;
		p_edit.scratch().face_corners(id, corners);
		std::vector<IVec3> loop;
		for (const VertexId v : corners) loop.push_back(p_edit.scratch().position_i(v));
		bool restored = false;
		for (const SourceFace &src : p_sources) {
			if (on_source_plane(loop, src)) {
				p_edit.set_attrs(id, src.attrs);
				restored = true;
				break;
			}
		}
		if (!restored) p_edit.set_attrs(id, p_cap_attrs);
	}
}

} // namespace

MeshFault plane_cut(MeshEdit &p_edit, const IVec3 &p_origin, const IVec3 &p_normal,
		PlaneSide p_keep, const FaceAttrs &p_cap_attrs) {
	if (p_normal.x == 0 && p_normal.y == 0 && p_normal.z == 0) {
		return bad(MeshError::DEGENERATE_FACE);
	}
	std::vector<VertexId> vertices;
	p_edit.scratch().all_vertices(vertices);
	if (vertices.empty()) return bad(MeshError::RESULT_EMPTY);
	bool any_kept = false, any_strictly_kept = false, any_removed = false;
	IVec3 lo = p_edit.scratch().position_i(vertices[0]);
	IVec3 hi = lo;
	for (const VertexId id : vertices) {
		const IVec3 p = p_edit.scratch().position_i(id);
		lo.x = std::min(lo.x, p.x); lo.y = std::min(lo.y, p.y); lo.z = std::min(lo.z, p.z);
		hi.x = std::max(hi.x, p.x); hi.y = std::max(hi.y, p.y); hi.z = std::max(hi.z, p.z);
		const __int128 s = side(p, p_origin, p_normal);
		const bool kept = p_keep == PlaneSide::POSITIVE ? s >= 0 : s <= 0;
		const bool strictly_kept = p_keep == PlaneSide::POSITIVE ? s > 0 : s < 0;
		any_kept |= kept;
		any_strictly_kept |= strictly_kept;
		any_removed |= !kept;
	}
	if (!any_removed) return p_edit.last_fault();
	if (!any_kept || !any_strictly_kept) return bad(MeshError::RESULT_EMPTY);

	const Mesh original = p_edit.scratch();
	std::vector<SourceFace> sources;
	std::vector<FaceId> source_ids;
	p_edit.scratch().all_faces(source_ids);
	for (const FaceId id : source_ids) {
		std::vector<VertexId> corners;
		p_edit.scratch().face_corners(id, corners);
		SourceFace src;
		for (const VertexId v : corners) src.loop.push_back(p_edit.scratch().position_i(v));
		src.attrs = p_edit.scratch().attrs(id);
		sources.push_back(std::move(src));
	}

	// Direct face clipping gives the cleanest topology for ordinary concave
	// solids and disconnected shells. MeshEdit::assemble closes their section
	// loops. A cavity produces overlapping automatic caps and fails commit, in
	// which case the Boolean path below resolves the nested section loops.
	std::vector<std::vector<IVec3>> direct_faces;
	for (const SourceFace &src : sources) {
		auto part = clipped(src.loop, p_origin, p_normal, p_keep);
		if (part.size() >= 3) direct_faces.push_back(std::move(part));
	}
	MeshEdit direct = MeshEdit::empty();
	if (direct.assemble(direct_faces).ok()) {
		Mesh direct_mesh;
		if (std::move(direct).commit(direct_mesh).ok()) {
			p_edit.replace_with(direct_mesh);
			restore_attributes(p_edit, sources, p_cap_attrs);
			if (has_authored_attributes(original)) transfer_rebuilt_attributes(p_edit, {&original}, false);
			return p_edit.last_fault();
		}
	}

	auto grow_lo = [](int32_t v) { return v > -COORD_LIMIT ? v - 1 : v; };
	auto grow_hi = [](int32_t v) { return v < COORD_LIMIT ? v + 1 : v; };
	// Axis cuts already have a tighter AABB along their cutting axis. Oblique
	// halfspaces can span all six host bounds, so leave one support coincident
	// to avoid Boolean's coarse AABB enclosure shortcut.
	const int nonzero_axes = (p_normal.x != 0) + (p_normal.y != 0) + (p_normal.z != 0);
	lo = { grow_lo(lo.x), grow_lo(lo.y), nonzero_axes == 1 ? grow_lo(lo.z) : lo.z };
	hi = { grow_hi(hi.x), grow_hi(hi.y), grow_hi(hi.z) };
	std::vector<std::vector<IVec3>> faces;
	box_faces(lo, hi, faces);
	std::vector<std::vector<IVec3>> cutter_faces;
	const PlaneSide remove_side = p_keep == PlaneSide::POSITIVE ? PlaneSide::NEGATIVE : PlaneSide::POSITIVE;
	for (const auto &face : faces) {
		auto part = clipped(face, p_origin, p_normal, remove_side);
		if (part.size() >= 3) cutter_faces.push_back(std::move(part));
	}
	close_boundary(cutter_faces, p_origin, p_normal);
	MeshEdit cutter_edit = MeshEdit::empty();
	MeshFault made = cutter_edit.assemble(cutter_faces);
	if (!made.ok()) return made;
	Mesh cutter;
	made = std::move(cutter_edit).commit(cutter);
	if (!made.ok()) return made;
	MeshFault result = boolean(p_edit, cutter, 1);
	if (!result.ok()) return result;

	restore_attributes(p_edit, sources, p_cap_attrs);
	if (has_authored_attributes(original)) transfer_rebuilt_attributes(p_edit, {&original}, false);
	return p_edit.last_fault();
}

} // namespace ops
} // namespace slab
