#include "import.hpp"

#include "../mesh_edit.hpp"

#include <map>
#include <utility>

namespace slab {
namespace ops {

namespace {

const char *REASON_EMPTY = "empty";
const char *REASON_OPEN = "open";
const char *REASON_NON_MANIFOLD = "non-manifold";
const char *REASON_BOTH = "non-manifold / open";

ImportResult _refuse(const char *p_reason, MeshError p_code) {
	ImportResult result;
	result.refuse_reason = p_reason;
	result.fault.code = p_code;
	return result;
}

const char *_reason_from_fault(MeshError p_code) {
	switch (p_code) {
		case MeshError::RESULT_EMPTY:
			return REASON_EMPTY;
		case MeshError::NOT_CLOSED:
		case MeshError::TWIN_MISMATCH:
			return REASON_OPEN;
		default:
			return REASON_NON_MANIFOLD;
	}
}

bool _zero_area(const IVec3 &p_a, const IVec3 &p_b, const IVec3 &p_c) {
	const IVec3 ab{ p_b.x - p_a.x, p_b.y - p_a.y, p_b.z - p_a.z };
	const IVec3 ac{ p_c.x - p_a.x, p_c.y - p_a.y, p_c.z - p_a.z };
	const __int128 nx = (__int128)ab.y * ac.z - (__int128)ab.z * ac.y;
	const __int128 ny = (__int128)ab.z * ac.x - (__int128)ab.x * ac.z;
	const __int128 nz = (__int128)ab.x * ac.y - (__int128)ab.y * ac.x;
	return nx == 0 && ny == 0 && nz == 0;
}

bool _zero_area_loop(const std::vector<IVec3> &p_loop) {
	if (p_loop.size() < 3) {
		return false;
	}
	for (size_t i = 1; i + 1 < p_loop.size(); i++) {
		if (!_zero_area(p_loop[0], p_loop[i], p_loop[i + 1])) {
			return false;
		}
	}
	return true;
}

// Emit can drop a collinear face, leaving a T-junction hole whose boundary is
// a zero-area cycle. Pair those slivers so Promote does not call a closed
// solid open. Cycles with area stay holes.
bool _recover_sliver_holes(std::map<std::pair<IVec3, IVec3>, int> &p_directed, std::vector<std::vector<IVec3>> &r_loops) {
	std::vector<std::pair<IVec3, IVec3>> unmatched;
	std::map<std::pair<IVec3, IVec3>, bool> seen_undirected;
	for (const auto &kv : p_directed) {
		IVec3 a = kv.first.first;
		IVec3 b = kv.first.second;
		if (b < a) {
			const IVec3 tmp = a;
			a = b;
			b = tmp;
		}
		if (!seen_undirected.emplace(std::pair<IVec3, IVec3>{ a, b }, true).second) {
			continue;
		}
		const auto forward = p_directed.find({ a, b });
		const auto back = p_directed.find({ b, a });
		const int n_forward = forward == p_directed.end() ? 0 : forward->second;
		const int n_back = back == p_directed.end() ? 0 : back->second;
		if (n_forward + n_back != 1) {
			continue;
		}
		if (n_forward == 1) {
			unmatched.push_back({ a, b });
		} else {
			unmatched.push_back({ b, a });
		}
	}
	if (unmatched.empty()) {
		return false;
	}

	std::vector<bool> used(unmatched.size(), false);
	auto next_from = [&](const IVec3 &p_from) -> int {
		for (size_t i = 0; i < unmatched.size(); i++) {
			if (!used[i] && unmatched[i].first == p_from) {
				return int(i);
			}
		}
		return -1;
	};

	std::vector<std::vector<IVec3>> slivers;
	size_t consumed = 0;
	while (consumed < unmatched.size()) {
		int start_i = -1;
		for (size_t i = 0; i < unmatched.size(); i++) {
			if (!used[i]) {
				start_i = int(i);
				break;
			}
		}
		if (start_i < 0) {
			break;
		}
		std::vector<IVec3> cycle;
		IVec3 start = unmatched[size_t(start_i)].first;
		IVec3 cur = start;
		bool closed = false;
		for (size_t guard = 0; guard < unmatched.size() + 2; guard++) {
			const int edge_i = next_from(cur);
			if (edge_i < 0) {
				break;
			}
			used[size_t(edge_i)] = true;
			consumed++;
			cycle.push_back(cur);
			cur = unmatched[size_t(edge_i)].second;
			if (cur == start) {
				closed = true;
				break;
			}
		}
		if (!closed || cycle.size() < 3 || !_zero_area_loop(cycle)) {
			return false;
		}
		slivers.push_back(std::move(cycle));
	}
	if (slivers.empty()) {
		return false;
	}
	for (const std::vector<IVec3> &cycle : slivers) {
		for (size_t i = 1; i + 1 < cycle.size(); i++) {
			r_loops.push_back({ cycle[0], cycle[i], cycle[i + 1] });
			p_directed[{ cycle[0], cycle[i] }] += 1;
			p_directed[{ cycle[i], cycle[i + 1] }] += 1;
			p_directed[{ cycle[i + 1], cycle[0] }] += 1;
		}
	}
	return true;
}


bool _triangle_attrs(const std::vector<IVec3> &p_loop, const ImportTriangleAttrs &p_source, FaceAttrs &r_attrs) {
	r_attrs.material_slot = p_source.material_slot;
	if (!p_source.has_uvs) return true;
	for (const godot::Vector2 &uv : p_source.uvs) {
		if (!uv.is_finite()) return false;
	}
	const godot::Vector3 a = dequantize(p_loop[0]);
	const godot::Vector3 ab = dequantize(p_loop[1]) - a;
	const godot::Vector3 ac = dequantize(p_loop[2]) - a;
	const godot::Vector3 normal = ab.cross(ac);
	const godot::Vector2 duv_b = p_source.uvs[1] - p_source.uvs[0];
	const godot::Vector2 duv_c = p_source.uvs[2] - p_source.uvs[0];
	if (normal.length_squared() > 0.0f) {
		const godot::Vector3 b_gradient = ac.cross(normal) / normal.length_squared();
		const godot::Vector3 c_gradient = normal.cross(ab) / normal.length_squared();
		r_attrs.uv_u = b_gradient * duv_b.x + c_gradient * duv_c.x;
		r_attrs.uv_v = b_gradient * duv_b.y + c_gradient * duv_c.y;
	} else {
		// A collinear triangle can carry UVs only if they are linear along its edge.
		const bool use_b = ab.length_squared() >= ac.length_squared();
		const godot::Vector3 edge = use_b ? ab : ac;
		const godot::Vector2 delta = use_b ? duv_b : duv_c;
		if (edge.length_squared() == 0.0f) return false;
		r_attrs.uv_u = edge * (delta.x / edge.length_squared());
		r_attrs.uv_v = edge * (delta.y / edge.length_squared());
	}
	r_attrs.uv_origin = p_source.uvs[0] - godot::Vector2(a.dot(r_attrs.uv_u), a.dot(r_attrs.uv_v));
	r_attrs.uv_unwrapped = true;
	for (size_t i = 0; i < 3; i++) {
		const godot::Vector3 p = dequantize(p_loop[i]);
		const godot::Vector2 reconstructed = godot::Vector2(p.dot(r_attrs.uv_u), p.dot(r_attrs.uv_v)) + r_attrs.uv_origin;
		if (!reconstructed.is_finite() || reconstructed.distance_to(p_source.uvs[i]) > 0.001f) return false;
	}
	return true;
}

} // namespace

ImportResult import_from_triangles(const std::vector<IVec3> &p_verts, const std::vector<int32_t> &p_indices,
		const std::vector<ImportTriangleAttrs> &p_attrs) {
	std::vector<int32_t> indices = p_indices;
	if (indices.empty()) {
		indices.resize(p_verts.size());
		for (size_t i = 0; i < p_verts.size(); i++) {
			indices[i] = int32_t(i);
		}
	}
	if (p_verts.empty() || indices.size() < 3) {
		return _refuse(REASON_EMPTY, MeshError::RESULT_EMPTY);
	}

	if (indices.size() % 3 != 0 || (!p_attrs.empty() && p_attrs.size() != indices.size() / 3)) {
		return _refuse(REASON_NON_MANIFOLD, MeshError::DEGENERATE_FACE);
	}
	std::vector<FaceAttrs> attrs;
	std::vector<std::vector<IVec3>> loops;
	loops.reserve(indices.size() / 3);
	for (size_t i = 0; i + 2 < indices.size(); i += 3) {
		const int32_t i0 = indices[i];
		const int32_t i1 = indices[i + 1];
		const int32_t i2 = indices[i + 2];
		if (i0 < 0 || i1 < 0 || i2 < 0 || size_t(i0) >= p_verts.size() || size_t(i1) >= p_verts.size() ||
				size_t(i2) >= p_verts.size()) {
			return _refuse(REASON_NON_MANIFOLD, MeshError::DEGENERATE_FACE);
		}
		const IVec3 a = p_verts[size_t(i0)];
		const IVec3 b = p_verts[size_t(i1)];
		const IVec3 c = p_verts[size_t(i2)];
		if (a == b || b == c || c == a) {
			return _refuse(REASON_NON_MANIFOLD, MeshError::DEGENERATE_FACE);
		}
		loops.push_back({ a, b, c });
		FaceAttrs face_attrs;
		if (!p_attrs.empty() && !_triangle_attrs(loops.back(), p_attrs[i / 3], face_attrs)) {
			return _refuse("unsupported UV mapping", MeshError::DEGENERATE_FACE);
		}
		attrs.push_back(face_attrs);
	}
	if (loops.empty()) {
		return _refuse(REASON_EMPTY, MeshError::RESULT_EMPTY);
	}

	std::map<std::pair<IVec3, IVec3>, int> directed;
	for (const std::vector<IVec3> &loop : loops) {
		for (size_t i = 0; i < loop.size(); i++) {
			const IVec3 &a = loop[i];
			const IVec3 &b = loop[(i + 1) % loop.size()];
			directed[{ a, b }] += 1;
		}
	}

	bool open = false;
	bool non_manifold = false;
	std::map<std::pair<IVec3, IVec3>, bool> seen_undirected;
	for (const auto &kv : directed) {
		if (kv.second > 1) {
			non_manifold = true;
		}
		IVec3 a = kv.first.first;
		IVec3 b = kv.first.second;
		if (b < a) {
			const IVec3 tmp = a;
			a = b;
			b = tmp;
		}
		if (!seen_undirected.emplace(std::pair<IVec3, IVec3>{ a, b }, true).second) {
			continue;
		}
		const auto forward = directed.find({ a, b });
		const auto back = directed.find({ b, a });
		const int n_forward = forward == directed.end() ? 0 : forward->second;
		const int n_back = back == directed.end() ? 0 : back->second;
		if (n_forward + n_back == 1) {
			open = true;
		} else if (n_forward + n_back != 2) {
			non_manifold = true;
		}
	}

	if (open && !non_manifold && _recover_sliver_holes(directed, loops)) {
		open = false;
	}

	if (open && non_manifold) {
		return _refuse(REASON_BOTH, MeshError::NON_MANIFOLD_VERTEX);
	}
	if (open) {
		return _refuse(REASON_OPEN, MeshError::NOT_CLOSED);
	}
	if (non_manifold) {
		return _refuse(REASON_NON_MANIFOLD, MeshError::NON_MANIFOLD_VERTEX);
	}

	MeshEdit edit = MeshEdit::empty();
	const MeshFault assembled = edit.assemble(loops);
	if (!assembled.ok()) {
		return _refuse(_reason_from_fault(assembled.code), assembled.code);
	}
	// assemble() can cap leftover boundary loops. Promote must never take that path.
	if (edit.scratch().face_count() != int(loops.size())) {
		return _refuse(REASON_OPEN, MeshError::NOT_CLOSED);
	}

	// assemble allocates one face per loop in order; the exact count was checked above.
	std::vector<FaceId> faces;
	edit.scratch().all_faces(faces);
	for (size_t i = 0; i < attrs.size(); i++) edit.set_attrs(faces[i], attrs[i]);

	const MeshFault checked = validate(edit.scratch());
	if (checked.code == MeshError::INVERTED_VOLUME) {
		const MeshFault flipped = edit.flip_all();
		if (!flipped.ok()) {
			return _refuse(REASON_NON_MANIFOLD, flipped.code);
		}
	} else if (!checked.ok()) {
		return _refuse(_reason_from_fault(checked.code), checked.code);
	}

	ImportResult result;
	const MeshFault committed = std::move(edit).commit(result.mesh);
	if (!committed.ok()) {
		return _refuse(_reason_from_fault(committed.code), committed.code);
	}
	result.fault = MeshFault{};
	result.refuse_reason.clear();
	return result;
}

} // namespace ops
} // namespace slab
