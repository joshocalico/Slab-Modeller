#include "rebuild_attributes.hpp"
#include "emit.hpp"
#include "surface_attrs_interpolate.hpp"
#include "triangulate.hpp"
#include <algorithm>
#include <limits>

namespace slab {
namespace {
struct Source {
	const Mesh *mesh;
	FaceId face;
	std::vector<IVec3> loop;
	std::vector<int32_t> triangles;
	std::vector<CornerAttrs> corners;
	std::vector<godot::Vector2> uvs;
	godot::Vector3 normal;
	bool authored_uv = false;
};
struct Sample {
	double distance = std::numeric_limits<double>::infinity();
	int indices[3] = {};
	double weights[3] = {};
};
Sample sample(const Source &s, const godot::Vector3 &p) {
	Sample best;
	for (size_t t = 0; t < s.triangles.size(); t += 3) {
		const int ids[] = {s.triangles[t], s.triangles[t + 1], s.triangles[t + 2]};
		godot::Vector3 v[3];
		for (int k = 0; k < 3; ++k)
			v[k] = dequantize(s.loop[ids[k]]);
		auto consider = [&](double a, double b, double c) {
			const double d = p.distance_squared_to(v[0] * a + v[1] * b + v[2] * c);
			if (d < best.distance) {
				best.distance = d;
				for (int k = 0; k < 3; ++k)
					best.indices[k] = ids[k];
				best.weights[0] = a;
				best.weights[1] = b;
				best.weights[2] = c;
			}
		};
		const auto ab = v[1] - v[0], ac = v[2] - v[0], ap = p - v[0];
		const double aa = ab.dot(ab), bb = ab.dot(ac), cc = ac.dot(ac), den = aa * cc - bb * bb;
		if (den > 1e-20) {
			const double b = (cc * ap.dot(ab) - bb * ap.dot(ac)) / den, c = (aa * ap.dot(ac) - bb * ap.dot(ab)) / den;
			if (b >= 0 && c >= 0 && b + c <= 1)
				consider(1 - b - c, b, c);
		}
		for (int k = 0; k < 3; ++k) {
			const int j = (k + 1) % 3;
			const auto edge = v[j] - v[k];
			const double u = edge.length_squared() > 0
								 ? std::clamp(double((p - v[k]).dot(edge) / edge.length_squared()), 0.0, 1.0)
								 : 0;
			double w[3] = {};
			w[k] = 1 - u;
			w[j] = u;
			consider(w[0], w[1], w[2]);
		}
	}
	return best;
}
bool on_segment(const IVec3 &p, const IVec3 &a, const IVec3 &b) {
	const __int128 x = __int128(b.x) - a.x, y = __int128(b.y) - a.y, z = __int128(b.z) - a.z;
	const __int128 u = __int128(p.x) - a.x, v = __int128(p.y) - a.y, w = __int128(p.z) - a.z;
	return x * v == y * u && x * w == z * u && y * w == z * v && u * x + v * y + w * z >= 0 &&
		   u * x + v * y + w * z <= x * x + y * y + z * z;
}
} // namespace
bool has_authored_attributes(const Mesh &mesh) {
	std::vector<FaceId> faces;
	mesh.all_faces(faces);
	for (auto f : faces) {
		const auto a = mesh.attrs(f);
		if (a.material_slot || a.smooth || a.uv_unwrapped || a.uv_axis != UvAxis::AUTO || a.uv_rotation ||
			a.uv_offset != godot::Vector2() || a.uv_scale != godot::Vector2(1, 1))
			return true;
		std::vector<CornerAttrs> c;
		mesh.face_corner_attrs(f, c);
		for (const auto &v : c)
			if (v.uv_explicit || v.uv_pinned || v.surface.flags || !v.surface.morphs.empty())
				return true;
	}
	std::vector<EdgeId> edges;
	mesh.all_edges(edges);
	for (auto e : edges)
		if (mesh.edge_hard(e) || mesh.edge_uv_seam(e))
			return true;
	return false;
}
void transfer_rebuilt_attributes(MeshEdit &edit, const std::vector<const Mesh *> &meshes, bool restore_faces) {
	std::vector<Source> sources;
	for (const Mesh *mesh : meshes) {
		std::vector<FaceId> faces;
		mesh->all_faces(faces);
		for (auto f : faces) {
			Source s;
			s.mesh = mesh;
			s.face = f;
			s.normal = mesh->face_normal(f);
			std::vector<VertexId> corners;
			mesh->face_corners(f, corners);
			for (auto c : corners)
				s.loop.push_back(mesh->position_i(c));
			triangulate_loop(s.loop, s.triangles);
			mesh->face_corner_attrs(f, s.corners);
			face_uv_points(*mesh, f, s.uvs);
			const auto attrs = mesh->attrs(f);
			s.authored_uv = attrs.uv_unwrapped || attrs.uv_rotation != 0;
			for (const auto &c : s.corners)
				s.authored_uv |= c.uv_explicit || c.uv_pinned;
			if (!s.triangles.empty())
				sources.push_back(std::move(s));
		}
	}
	std::vector<FaceId> faces;
	edit.scratch().all_faces(faces);
	for (auto f : faces) {
		std::vector<VertexId> vertices;
		edit.scratch().face_corners(f, vertices);
		const auto normal = edit.scratch().face_normal(f);
		const Source *owner = nullptr;
		double best = std::numeric_limits<double>::infinity();
		for (const auto &s : sources) {
			if (std::abs(normal.dot(s.normal)) < .9999)
				continue;
			double distance = 0;
			for (auto v : vertices)
				distance = std::max(distance, sample(s, dequantize(edit.scratch().position_i(v))).distance);
			if (distance < best) {
				best = distance;
				owner = &s;
			}
		}
		const bool retained = owner && best < 4.0 / (LATTICE * LATTICE);
		if (retained) {
			auto a = restore_faces ? owner->mesh->attrs(owner->face) : edit.scratch().attrs(f);
			edit.set_attrs(f, a);
		}
		for (uint32_t k = 0; k < vertices.size(); ++k) {
			const auto pos = edit.scratch().position_i(vertices[k]);
			const auto p = dequantize(pos);
			const Source *s = retained ? owner : nullptr;
			Sample pick;
			if (s)
				pick = sample(*s, p);
			else
				for (const auto &candidate : sources) {
					const auto hit = sample(candidate, p);
					if (hit.distance < pick.distance) {
						pick = hit;
						s = &candidate;
					}
				}
			if (!s)
				continue;
			CornerAttrs out;
			SurfaceAttrs values[3];
			for (int j = 0; j < 3; ++j)
				values[j] = s->corners[pick.indices[j]].surface;
			interpolate_surface_attrs(values, pick.weights, 3, out.surface);
			if (retained) {
				out.uv_explicit = s->authored_uv;
				for (int j = 0; j < 3; ++j)
					out.uv += s->uvs[pick.indices[j]] * pick.weights[j];
				for (size_t j = 0; j < s->loop.size(); ++j)
					if (pos == s->loop[j]) {
						out.uv_pinned = s->corners[j].uv_pinned;
						out.surface = s->corners[j].surface;
					}
				if (normal.dot(s->normal) < 0) {
					out.surface.normal = -out.surface.normal;
					out.surface.tangent[3] = -out.surface.tangent[3];
					for (auto &m : out.surface.morphs) {
						m.normal = -m.normal;
						m.tangent_w = -m.tangent_w;
					}
				}
			} else {
				out.surface.flags &= ~(SurfaceAttrs::NORMAL | SurfaceAttrs::TANGENT);
				for (auto &m : out.surface.morphs) {
					m.normal = godot::Vector3();
					m.tangent = godot::Vector3();
					m.tangent_w = 0;
				}
			}
			edit.set_corner_attrs(f, k, out);
		}
		if (retained && owner->authored_uv) {
			// Keep the user-facing placement controls while solving raw corners
			// from the desired UVs. Rotation pivots around the NEW face mean.
			auto attrs = edit.scratch().attrs(f);
			std::vector<CornerAttrs> corners;
			edit.scratch().face_corner_attrs(f, corners);
			if (attrs.uv_scale.x == 0 || attrs.uv_scale.y == 0) {
				attrs.uv_scale = godot::Vector2(1, 1);
				attrs.uv_offset = godot::Vector2();
				attrs.uv_rotation = 0;
				edit.set_attrs(f, attrs);
			} else {
				godot::Vector2 mean;
				for (const auto &corner : corners) mean += corner.uv;
				mean = mean / float(corners.size()) - attrs.uv_offset;
				const double sine = std::sin(attrs.uv_rotation), cosine = std::cos(attrs.uv_rotation);
				for (uint32_t k = 0; k < corners.size(); ++k) {
					const auto delta = corners[k].uv - attrs.uv_offset - mean;
					corners[k].uv = godot::Vector2(delta.x * cosine + delta.y * sine,
							-delta.x * sine + delta.y * cosine) + mean;
					corners[k].uv.x /= attrs.uv_scale.x;
					corners[k].uv.y /= attrs.uv_scale.y;
					edit.set_corner_attrs(f, k, corners[k]);
				}
			}
		}
	}
	std::vector<EdgeId> edges;
	edit.scratch().all_edges(edges);
	for (auto e : edges) {
		VertexId va, vb;
		edit.scratch().edge_vertices(e, va, vb);
		const auto a = edit.scratch().position_i(va), b = edit.scratch().position_i(vb);
		for (const Mesh *mesh : meshes) {
			std::vector<EdgeId> old;
			mesh->all_edges(old);
			for (auto oe : old) {
				if (!mesh->edge_hard(oe) && !mesh->edge_uv_seam(oe))
					continue;
				VertexId oa, ob;
				mesh->edge_vertices(oe, oa, ob);
				if (on_segment(a, mesh->position_i(oa), mesh->position_i(ob)) &&
					on_segment(b, mesh->position_i(oa), mesh->position_i(ob))) {
					if (mesh->edge_hard(oe))
						edit.set_hard_edge(e, true);
					if (mesh->edge_uv_seam(oe))
						edit.set_uv_seam(e, true);
				}
			}
		}
	}
}
} // namespace slab
