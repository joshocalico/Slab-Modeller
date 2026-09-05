#include "boolean.hpp"

namespace slab {
namespace ops {

namespace {

MeshFault _bad(MeshError p_code) {
	MeshFault f;
	f.code = p_code;
	return f;
}

bool _aabb_disjoint(const godot::AABB &p_a, const godot::AABB &p_b) {
	return !p_a.intersects(p_b);
}

bool _aabb_strictly_encloses(const godot::AABB &p_outer, const godot::AABB &p_inner) {
	if (!p_outer.encloses(p_inner)) {
		return false;
	}
	const godot::Vector3 a0 = p_outer.position;
	const godot::Vector3 a1 = p_outer.position + p_outer.size;
	const godot::Vector3 b0 = p_inner.position;
	const godot::Vector3 b1 = p_inner.position + p_inner.size;
	return b0.x > a0.x && b0.y > a0.y && b0.z > a0.z && b1.x < a1.x && b1.y < a1.y && b1.z < a1.z;
}

} // namespace

MeshFault boolean(MeshEdit &p_edit, const Mesh &p_other, int p_mode) {
	if (p_other.face_count() < 1) {
		return _bad(MeshError::RESULT_EMPTY);
	}
	const godot::AABB a = p_edit.scratch().local_aabb();
	const godot::AABB b = p_other.local_aabb();
	if (p_mode == 0) {
		if (!_aabb_disjoint(a, b) && !_aabb_strictly_encloses(a, b) && !_aabb_strictly_encloses(b, a)) {
			return _bad(MeshError::NO_INTERSECTION);
		}
		if (_aabb_strictly_encloses(a, b) || _aabb_strictly_encloses(b, a)) {
			return _bad(MeshError::NO_INTERSECTION);
		}
		return p_edit.append(p_other, false);
	}
	if (p_mode == 1) {
		if (_aabb_disjoint(a, b)) {
			return p_edit.last_fault();
		}
		if (_aabb_strictly_encloses(b, a)) {
			return _bad(MeshError::RESULT_EMPTY);
		}
		if (_aabb_strictly_encloses(a, b)) {
			return p_edit.append(p_other, true);
		}
		return _bad(MeshError::NO_INTERSECTION);
	}
	if (p_mode == 2) {
		if (_aabb_disjoint(a, b)) {
			return _bad(MeshError::NO_INTERSECTION);
		}
		if (_aabb_strictly_encloses(a, b)) {
			return p_edit.replace_with(p_other);
		}
		if (_aabb_strictly_encloses(b, a)) {
			return p_edit.last_fault();
		}
		return _bad(MeshError::NO_INTERSECTION);
	}
	return _bad(MeshError::INVALID_SELECTION);
}

} // namespace ops
} // namespace slab
