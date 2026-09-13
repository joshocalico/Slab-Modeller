#include "edit.hpp"

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

bool _verts_alive(const Mesh &p_mesh, const std::vector<VertexId> &p_verts) {
	for (const VertexId id : p_verts) {
		if (!p_mesh.alive(id)) {
			return false;
		}
	}
	return true;
}

bool _edges_alive(const Mesh &p_mesh, const std::vector<EdgeId> &p_edges) {
	for (const EdgeId id : p_edges) {
		if (!p_mesh.alive(id)) {
			return false;
		}
	}
	return true;
}

int32_t _snap_coord(int32_t p_v, int32_t p_step) {
	if (p_step <= 0) {
		return p_v;
	}
	const int64_t half = p_v >= 0 ? p_step / 2 : -(p_step / 2);
	return int32_t(((int64_t(p_v) + half) / p_step) * p_step);
}

} // namespace

MeshFault set_face_material(MeshEdit &p_edit, const std::vector<FaceId> &p_faces, uint32_t p_slot) {
	if (!faces_alive(p_edit.scratch(), p_faces)) {
		return _bad(MeshError::STALE_HANDLE);
	}
	for (const FaceId id : p_faces) {
		FaceAttrs attrs = p_edit.scratch().attrs(id);
		attrs.material_slot = p_slot;
		p_edit.set_attrs(id, attrs);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	return p_edit.last_fault();
}

MeshFault merge_faces(MeshEdit &p_edit, const std::vector<FaceId> &p_faces) {
	if (!p_edit.last_fault().ok()) {
		return p_edit.last_fault();
	}
	if (p_faces.size() < 2) {
		return _bad(MeshError::INVALID_SELECTION);
	}
	if (!faces_alive(p_edit.scratch(), p_faces)) {
		return _bad(MeshError::STALE_HANDLE);
	}
	MeshEdit staged(p_edit.scratch());
	const MeshFault merged = staged.merge_face_region(p_faces);
	if (!merged.ok()) {
		return merged;
	}
	p_edit = std::move(staged);
	return p_edit.last_fault();
}

MeshFault dissolve_edges(MeshEdit &p_edit, const std::vector<EdgeId> &p_edges) {
	if (p_edges.empty()) {
		return _bad(MeshError::INVALID_SELECTION);
	}
	if (!_edges_alive(p_edit.scratch(), p_edges)) {
		return _bad(MeshError::STALE_HANDLE);
	}
	for (const EdgeId id : p_edges) {
		if (!p_edit.scratch().alive(id)) {
			return _bad(MeshError::STALE_HANDLE, id.slot);
		}
		const MeshFault dissolved = p_edit.dissolve_edge(id);
		if (!dissolved.ok()) {
			return dissolved;
		}
	}
	return p_edit.last_fault();
}

MeshFault move_vertices(MeshEdit &p_edit, const std::vector<VertexId> &p_verts, const godot::Vector3 &p_delta) {
	if (p_verts.empty()) {
		return _bad(MeshError::INVALID_SELECTION);
	}
	if (!_verts_alive(p_edit.scratch(), p_verts)) {
		return _bad(MeshError::STALE_HANDLE);
	}
	for (const VertexId id : p_verts) {
		const godot::Vector3 next = p_edit.scratch().position(id) + p_delta;
		IVec3 q;
		if (!quantize(next, q)) {
			return _bad(MeshError::COORD_OUT_OF_RANGE);
		}
		p_edit.move_vertex(id, q);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	return p_edit.last_fault();
}

MeshFault center_pivot(MeshEdit &p_edit) {
	const godot::AABB aabb = p_edit.scratch().local_aabb();
	const godot::Vector3 c = aabb.position + aabb.size * 0.5f;
	IVec3 origin;
	if (!quantize(c, origin)) {
		return _bad(MeshError::COORD_OUT_OF_RANGE);
	}
	std::vector<VertexId> verts;
	p_edit.scratch().all_vertices(verts);
	for (const VertexId id : verts) {
		IVec3 p = p_edit.scratch().position_i(id);
		p.x -= origin.x;
		p.y -= origin.y;
		p.z -= origin.z;
		p_edit.move_vertex(id, p);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	return p_edit.last_fault();
}

MeshFault snap_to_grid(MeshEdit &p_edit, float p_step) {
	int32_t step = 0;
	IVec3 q;
	if (!quantize(godot::Vector3(p_step, 0, 0), q) || q.x <= 0) {
		step = LATTICE / 2;
	} else {
		step = q.x;
	}
	std::vector<VertexId> verts;
	p_edit.scratch().all_vertices(verts);
	for (const VertexId id : verts) {
		IVec3 p = p_edit.scratch().position_i(id);
		p.x = _snap_coord(p.x, step);
		p.y = _snap_coord(p.y, step);
		p.z = _snap_coord(p.z, step);
		p_edit.move_vertex(id, p);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	return p_edit.last_fault();
}

MeshFault mirror(MeshEdit &p_edit, const godot::Vector3 &p_scale) {
	const float sx = p_scale.x == 0.0f ? 1.0f : p_scale.x;
	const float sy = p_scale.y == 0.0f ? 1.0f : p_scale.y;
	const float sz = p_scale.z == 0.0f ? 1.0f : p_scale.z;
	int neg = 0;
	if (sx < 0.0f) {
		neg++;
	}
	if (sy < 0.0f) {
		neg++;
	}
	if (sz < 0.0f) {
		neg++;
	}
	std::vector<VertexId> verts;
	p_edit.scratch().all_vertices(verts);
	for (const VertexId id : verts) {
		godot::Vector3 p = p_edit.scratch().position(id);
		p.x *= sx;
		p.y *= sy;
		p.z *= sz;
		IVec3 q;
		if (!quantize(p, q)) {
			return _bad(MeshError::COORD_OUT_OF_RANGE);
		}
		p_edit.move_vertex(id, q);
		if (!p_edit.last_fault().ok()) {
			return p_edit.last_fault();
		}
	}
	if (neg % 2 == 1) {
		return p_edit.flip_all();
	}
	return p_edit.last_fault();
}

} // namespace ops
} // namespace slab
