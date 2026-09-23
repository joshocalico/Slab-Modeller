#include "emit.hpp"
#include "triangulate.hpp"

#include <godot_cpp/core/math.hpp>
#include <cmath>
#include <unordered_set>

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

godot::Vector2 apply_uv(godot::Vector2 uv, const godot::Vector2 &p_centroid, const FaceAttrs &p_attrs, UvAxis p_axis) {
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

godot::Vector3 corner_normal(const Mesh &mesh, FaceId face, VertexId vertex) {
	const godot::Vector3 flat = mesh.face_normal(face);
	if (!mesh.attrs(face).smooth) return flat;
	std::vector<FaceId> pending{ face };
	std::unordered_set<uint32_t> visited;
	godot::Vector3 sum;
	while (!pending.empty()) {
		const FaceId current = pending.back();
		pending.pop_back();
		if (!visited.insert(current.slot).second) continue;
		sum += mesh.face_normal(current) * float(mesh.face_area(current));
		std::vector<EdgeId> edges;
		mesh.face_edges(current, edges);
		for (EdgeId edge : edges) {
			VertexId a, b;
			mesh.edge_vertices(edge, a, b);
			if ((a.slot != vertex.slot && b.slot != vertex.slot) || mesh.edge_hard(edge)) continue;
			FaceId left, right;
			mesh.edge_faces(edge, left, right);
			const FaceId other = left.slot == current.slot ? right : left;
			if (mesh.alive(other) && mesh.attrs(other).smooth) pending.push_back(other);
		}
	}
	return sum.length_squared() > 1e-12f ? sum.normalized() : flat;
}

void build_tangents(EmitOut &out) {
	std::vector<godot::Vector3> tangents(out.verts.size()), bitangents(out.verts.size());
	for (size_t i = 0; i + 2 < out.indices.size(); i += 3) {
		const int a = out.indices[i], b = out.indices[i + 1], c = out.indices[i + 2];
		const godot::Vector3 e1 = out.verts[b] - out.verts[a], e2 = out.verts[c] - out.verts[a];
		const godot::Vector2 d1 = out.uvs[b] - out.uvs[a], d2 = out.uvs[c] - out.uvs[a];
		const float det = d1.x * d2.y - d1.y * d2.x;
		if (std::abs(det) < 1e-12f) continue;
		const godot::Vector3 t = (e1 * d2.y - e2 * d1.y) / det;
		const godot::Vector3 bt = (e2 * d1.x - e1 * d2.x) / det;
		for (int j : { a, b, c }) { tangents[j] += t; bitangents[j] += bt; }
	}
	out.tangents.reserve(out.verts.size() * 4);
	for (size_t i = 0; i < out.verts.size(); ++i) {
		const godot::Vector3 n = out.normals[i];
		godot::Vector3 t = tangents[i] - n * n.dot(tangents[i]);
		if (t.length_squared() < 1e-12f) {
			const godot::Vector3 axis = std::abs(n.x) < 0.9f ? godot::Vector3(1, 0, 0) : godot::Vector3(0, 1, 0);
			t = axis - n * n.dot(axis);
		}
		t.normalize();
		out.tangents.insert(out.tangents.end(), { t.x, t.y, t.z, n.cross(t).dot(bitangents[i]) < 0 ? -1.0f : 1.0f });
	}
}

} // namespace

void face_uv_points(const Mesh &p_mesh, FaceId p_face, std::vector<godot::Vector2> &r_uvs) {
	r_uvs.clear();
	std::vector<VertexId> corners;
	std::vector<CornerAttrs> attributes;
	p_mesh.face_corners(p_face, corners);
	p_mesh.face_corner_attrs(p_face, attributes);
	if (corners.empty()) return;
	const FaceAttrs attrs = p_mesh.attrs(p_face);
	const UvAxis axis = attrs.uv_axis == UvAxis::AUTO ? dominant_axis(p_mesh.face_normal(p_face)) : attrs.uv_axis;
	godot::Vector2 center;
	for (size_t i = 0; i < corners.size(); ++i) {
		const godot::Vector2 uv = attributes[i].uv_explicit ? attributes[i].uv : face_projection(p_mesh.position(corners[i]), attrs, axis);
		r_uvs.push_back(uv);
		center += uv;
	}
	center /= float(corners.size());
	for (godot::Vector2 &uv : r_uvs) uv = apply_uv(uv, center, attrs, axis);
}

bool face_uv_at_point(const Mesh &p_mesh, FaceId p_face, const godot::Vector3 &p_point, godot::Vector2 &r_uv) {
	std::vector<VertexId> corners;
	p_mesh.face_corners(p_face, corners);
	std::vector<godot::Vector2> uvs;
	face_uv_points(p_mesh, p_face, uvs);
	std::vector<IVec3> loop;
	for (const VertexId corner : corners) loop.push_back(p_mesh.position_i(corner));
	std::vector<int32_t> triangles;
	triangulate_loop(loop, triangles);
	for (size_t i = 0; i + 2 < triangles.size(); i += 3) {
		const int a = triangles[i], b = triangles[i+1], c = triangles[i+2];
		const godot::Vector3 origin = p_mesh.position(corners[a]);
		const godot::Vector3 e0 = p_mesh.position(corners[b]) - origin, e1 = p_mesh.position(corners[c]) - origin;
		const godot::Vector3 delta = p_point - origin;
		const double d00 = e0.dot(e0), d01 = e0.dot(e1), d11 = e1.dot(e1);
		const double determinant = d00 * d11 - d01 * d01;
		if (std::abs(determinant) < 1e-16) continue;
		const double u = (d11 * delta.dot(e0) - d01 * delta.dot(e1)) / determinant;
		const double v = (d00 * delta.dot(e1) - d01 * delta.dot(e0)) / determinant;
		if (u >= -1e-5 && v >= -1e-5 && u + v <= 1.00001) {
			r_uv = uvs[a] * float(1-u-v) + uvs[b] * float(u) + uvs[c] * float(v);
			return true;
		}
	}
	return false;
}

void emit_arrays(const Mesh &p_mesh, EmitOut &r_out) {
	r_out.verts.clear();
	r_out.normals.clear();
	r_out.uvs.clear();
	r_out.tangents.clear();
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
		const FaceAttrs attrs = p_mesh.attrs(id);
		std::vector<godot::Vector2> uvs;
		face_uv_points(p_mesh, id, uvs);
		const int32_t base = int32_t(r_out.verts.size());
		std::vector<IVec3> loop;
		loop.reserve(corners.size());
		for (size_t corner = 0; corner < corners.size(); ++corner) {
			const VertexId v = corners[corner];
			const godot::Vector3 p = p_mesh.position(v);
			r_out.verts.push_back(p);
			r_out.normals.push_back(corner_normal(p_mesh, id, v));
			r_out.uvs.push_back(uvs[corner]);
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
	build_tangents(r_out);
}

} // namespace slab
