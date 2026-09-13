#include "emit.hpp"
#include "triangulate.hpp"

#include <godot_cpp/core/math.hpp>

namespace slab {

namespace {

UvAxis dominant_axis(const godot::Vector3 &p_n) {
	const float ax = godot::Math::abs(p_n.x);
	const float ay = godot::Math::abs(p_n.y);
	const float az = godot::Math::abs(p_n.z);
	if (az >= ax && az >= ay) {
		return UvAxis::Z;
	}
	if (ay >= ax) {
		return UvAxis::Y;
	}
	return UvAxis::X;
}

godot::Vector2 project_uv(const godot::Vector3 &p_p, UvAxis p_axis) {
	switch (p_axis) {
		case UvAxis::X:
			return godot::Vector2(p_p.y, p_p.z);
		case UvAxis::Y:
			return godot::Vector2(p_p.x, p_p.z);
		case UvAxis::Z:
		case UvAxis::AUTO:
		default:
			return godot::Vector2(p_p.x, p_p.y);
	}
}

godot::Vector2 face_projection(const godot::Vector3 &p_p, const FaceAttrs &p_attrs, UvAxis p_axis) {
	if (p_attrs.uv_unwrapped) {
		return godot::Vector2(p_p.dot(p_attrs.uv_u), p_p.dot(p_attrs.uv_v)) + p_attrs.uv_origin;
	}
	return project_uv(p_p, p_axis);
}

godot::Vector2 apply_uv(const godot::Vector3 &p_p, const godot::Vector2 &p_centroid, const FaceAttrs &p_attrs, UvAxis p_axis) {
	godot::Vector2 uv = face_projection(p_p, p_attrs, p_axis);
	uv.x *= p_attrs.uv_scale.x;
	uv.y *= p_attrs.uv_scale.y;
	godot::Vector2 c = p_centroid;
	c.x *= p_attrs.uv_scale.x;
	c.y *= p_attrs.uv_scale.y;
	const float s = godot::Math::sin(p_attrs.uv_rotation);
	const float co = godot::Math::cos(p_attrs.uv_rotation);
	const godot::Vector2 d = uv - c;
	uv = godot::Vector2(d.x * co - d.y * s, d.x * s + d.y * co) + c;
	uv += p_attrs.uv_offset;
	return uv;
}

} // namespace

void emit_arrays(const Mesh &p_mesh, EmitOut &r_out) {
	r_out.verts.clear();
	r_out.normals.clear();
	r_out.uvs.clear();
	r_out.indices.clear();
	r_out.provenance.clear();
	r_out.slots.clear();

	std::vector<FaceId> faces;
	p_mesh.all_faces(faces);
	std::vector<VertexId> corners;
	for (const FaceId id : faces) {
		p_mesh.face_corners(id, corners);
		if (corners.size() < 3) {
			continue;
		}
		const godot::Vector3 n = p_mesh.face_normal(id);
		const FaceAttrs attrs = p_mesh.attrs(id);
		UvAxis axis = attrs.uv_axis;
		if (axis == UvAxis::AUTO) {
			axis = dominant_axis(n);
		}
		const godot::Vector2 centroid = face_projection(p_mesh.face_centroid(id), attrs, axis);
		const int32_t base = int32_t(r_out.verts.size());
		std::vector<IVec3> loop;
		loop.reserve(corners.size());
		for (const VertexId v : corners) {
			const godot::Vector3 p = p_mesh.position(v);
			r_out.verts.push_back(p);
			r_out.normals.push_back(n);
			r_out.uvs.push_back(apply_uv(p, centroid, attrs, axis));
			loop.push_back(p_mesh.position_i(v));
		}
		std::vector<int32_t> tris;
		triangulate_loop(loop, tris);
		for (size_t i = 0; i + 2 < tris.size(); i += 3) {
			r_out.indices.push_back(base + tris[i]);
			r_out.indices.push_back(base + tris[i + 1]);
			r_out.indices.push_back(base + tris[i + 2]);
			r_out.provenance.push_back(id);
			r_out.slots.push_back(attrs.material_slot);
		}
	}
}

} // namespace slab
