#include "inset.hpp"

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

struct Wide {
	__int128 x = 0;
	__int128 y = 0;
	__int128 z = 0;
};

__int128 _dot(const Wide &p_a, const Wide &p_b) {
	return p_a.x * p_b.x + p_a.y * p_b.y + p_a.z * p_b.z;
}

Wide _area_2x(const std::vector<IVec3> &p_pts) {
	Wide a;
	const size_t n = p_pts.size();
	for (size_t i = 0; i < n; i++) {
		const IVec3 &p = p_pts[i];
		const IVec3 &q = p_pts[(i + 1) % n];
		a.x += __int128(p.y) * q.z - __int128(p.z) * q.y;
		a.y += __int128(p.z) * q.x - __int128(p.x) * q.z;
		a.z += __int128(p.x) * q.y - __int128(p.y) * q.x;
	}
	return a;
}

int _turn(const IVec3 &p_prev, const IVec3 &p_cur, const IVec3 &p_next, const Wide &p_ref) {
	const int64_t ax = int64_t(p_cur.x) - p_prev.x;
	const int64_t ay = int64_t(p_cur.y) - p_prev.y;
	const int64_t az = int64_t(p_cur.z) - p_prev.z;
	const int64_t bx = int64_t(p_next.x) - p_cur.x;
	const int64_t by = int64_t(p_next.y) - p_cur.y;
	const int64_t bz = int64_t(p_next.z) - p_cur.z;
	Wide cross;
	cross.x = __int128(ay) * bz - __int128(az) * by;
	cross.y = __int128(az) * bx - __int128(ax) * bz;
	cross.z = __int128(ax) * by - __int128(ay) * bx;
	const __int128 d = _dot(cross, p_ref);
	if (d > 0) {
		return 1;
	}
	if (d < 0) {
		return -1;
	}
	return 0;
}

bool _mitre(const godot::Vector3 &p_normal, const std::vector<IVec3> &p_src, float p_amount, std::vector<IVec3> &r_out) {
	const int n = int(p_src.size());
	std::vector<godot::Vector3> pos(n);
	std::vector<godot::Vector3> inward(n);
	for (int i = 0; i < n; i++) {
		pos[i] = dequantize(p_src[i]);
	}
	for (int i = 0; i < n; i++) {
		const godot::Vector3 edge = pos[(i + 1) % n] - pos[i];
		if (edge.length_squared() == 0.0f) {
			return false;
		}
		inward[i] = p_normal.cross(edge.normalized());
	}
	r_out.resize(n);
	for (int i = 0; i < n; i++) {
		const godot::Vector3 a = inward[(i + n - 1) % n];
		const godot::Vector3 b = inward[i];
		const float span = 1.0f + a.dot(b);
		if (span <= 0.0f) {
			return false;
		}
		if (!quantize(pos[i] + (a + b) * (p_amount / span), r_out[i])) {
			return false;
		}
	}
	return true;
}

bool _shrinks_without_inverting(const std::vector<IVec3> &p_src, const std::vector<IVec3> &p_dst) {
	const int n = int(p_src.size());
	for (int i = 0; i < n; i++) {
		for (int j = i + 1; j < n; j++) {
			if (p_dst[i] == p_dst[j]) {
				return false;
			}
		}
	}
	const Wide src = _area_2x(p_src);
	const Wide dst = _area_2x(p_dst);
	if (_dot(dst, src) <= 0) {
		return false;
	}
	if (_dot(dst, dst) >= _dot(src, src)) {
		return false;
	}
	for (int i = 0; i < n; i++) {
		const int prev = (i + n - 1) % n;
		const int next = (i + 1) % n;
		if (_turn(p_src[prev], p_src[i], p_src[next], src) != _turn(p_dst[prev], p_dst[i], p_dst[next], src)) {
			return false;
		}
	}
	return true;
}

bool _plan_inset(const Mesh &p_mesh, FaceId p_face, float p_amount, std::vector<IVec3> &r_out) {
	std::vector<VertexId> corners;
	p_mesh.face_corners(p_face, corners);
	if (corners.size() < 3) {
		return false;
	}
	const godot::Vector3 normal = p_mesh.face_normal(p_face);
	if (normal.length_squared() == 0.0f) {
		return false;
	}
	std::vector<IVec3> src(corners.size());
	for (size_t i = 0; i < corners.size(); i++) {
		src[i] = p_mesh.position_i(corners[i]);
	}
	float amount = p_amount;
	for (int attempt = 0; attempt < 24; attempt++) {
		if (_mitre(normal, src, amount, r_out) && _shrinks_without_inverting(src, r_out)) {
			return true;
		}
		amount *= 0.5f;
	}
	return false;
}

} // namespace

bool faces_alive(const Mesh &p_mesh, const std::vector<FaceId> &p_faces) {
	for (const FaceId id : p_faces) {
		if (!p_mesh.alive(id)) {
			return false;
		}
	}
	return true;
}

bool faces_share_an_edge(const Mesh &p_mesh, const std::vector<FaceId> &p_faces) {
	for (size_t i = 0; i < p_faces.size(); i++) {
		std::vector<EdgeId> ea;
		p_mesh.face_edges(p_faces[i], ea);
		for (size_t j = i + 1; j < p_faces.size(); j++) {
			std::vector<EdgeId> eb;
			p_mesh.face_edges(p_faces[j], eb);
			for (const EdgeId a : ea) {
				for (const EdgeId b : eb) {
					if (a.slot == b.slot) {
						return true;
					}
				}
			}
		}
	}
	return false;
}

MeshFault inset(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, float p_amount) {
	if (p_faces.empty() || !(p_amount > 0.0f)) {
		return _bad(MeshError::DEGENERATE_FACE);
	}
	const Mesh &src = p_edit.scratch();
	if (!faces_alive(src, p_faces)) {
		return _bad(MeshError::STALE_HANDLE);
	}
	if (faces_share_an_edge(src, p_faces)) {
		return _bad(MeshError::ADJACENT_SELECTION);
	}
	std::vector<std::vector<IVec3>> targets(p_faces.size());
	for (size_t i = 0; i < p_faces.size(); i++) {
		if (!_plan_inset(src, p_faces[i], p_amount, targets[i])) {
			return _bad(MeshError::DEGENERATE_FACE, p_faces[i].slot);
		}
	}
	for (size_t i = 0; i < p_faces.size(); i++) {
		const FaceId cap = p_edit.lift_loop(p_faces[i]);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
		std::vector<VertexId> corners;
		p_edit.scratch().face_corners(cap, corners);
		if (corners.size() != targets[i].size()) {
			_poison(p_edit);
			return p_edit.last_fault();
		}
		for (size_t k = 0; k < corners.size(); k++) {
			p_edit.move_vertex(corners[k], targets[i][k]);
			if (!p_edit.last_fault().ok()) {
				return p_edit.last_fault();
			}
		}
	}
	return p_edit.last_fault();
}

MeshFault delete_faces(MeshEdit &p_edit, const std::vector<FaceId> &p_faces) {
	if (p_faces.empty()) {
		return MeshFault{};
	}
	if (!faces_alive(p_edit.scratch(), p_faces)) {
		return _bad(MeshError::STALE_HANDLE);
	}
	// Closing the hole needs a MeshEdit primitive that stitches the orphaned half-edges remove_face
	// leaves behind onto a fresh face. Nothing public allocates a face, so the hole stays open and
	// the caller's commit is what reports NOT_CLOSED.
	for (const FaceId id : p_faces) {
		const MeshFault removed = p_edit.remove_face(id);
		if (!removed.ok()) {
			return removed;
		}
	}
	return p_edit.last_fault();
}

MeshFault flip_faces(MeshEdit &p_edit, const std::vector<FaceId> &p_faces) {
	if (p_faces.empty()) {
		return MeshFault{};
	}
	if (!faces_alive(p_edit.scratch(), p_faces)) {
		return _bad(MeshError::STALE_HANDLE);
	}
	for (const FaceId id : p_faces) {
		const MeshFault flipped = p_edit.flip_face(id);
		if (!flipped.ok()) {
			return flipped;
		}
	}
	return p_edit.last_fault();
}

} // namespace ops
} // namespace slab
