#include "serialize.hpp"

#include <cstring>
#include <cmath>
#include <utility>

namespace slab {

namespace {

constexpr uint32_t MAGIC = 0x31424C53u;
constexpr uint32_t VERSION = 6;
constexpr uint32_t VERSION_SLOT_U8 = 1;

MeshFault fault(MeshError p_code, uint32_t p_slot = INVALID_IDX) {
	MeshFault f;
	f.code = p_code;
	f.slot = p_slot;
	return f;
}

void write_u8(std::vector<uint8_t> &r_out, uint8_t p_v) {
	r_out.push_back(p_v);
}

void write_u32(std::vector<uint8_t> &r_out, uint32_t p_v) {
	r_out.push_back(uint8_t(p_v));
	r_out.push_back(uint8_t(p_v >> 8));
	r_out.push_back(uint8_t(p_v >> 16));
	r_out.push_back(uint8_t(p_v >> 24));
}

void write_i32(std::vector<uint8_t> &r_out, int32_t p_v) {
	write_u32(r_out, uint32_t(p_v));
}

void write_f32(std::vector<uint8_t> &r_out, float p_v) {
	uint32_t u = 0;
	std::memcpy(&u, &p_v, 4);
	write_u32(r_out, u);
}

struct Reader {
	const uint8_t *p = nullptr;
	const uint8_t *end = nullptr;
	bool ok = true;

	bool remain(size_t p_n) const {
		return ok && size_t(end - p) >= p_n;
	}

	uint8_t u8() {
		if (!remain(1)) {
			ok = false;
			return 0;
		}
		return *p++;
	}

	uint32_t u32() {
		if (!remain(4)) {
			ok = false;
			return 0;
		}
		const uint32_t v = uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
		p += 4;
		return v;
	}

	int32_t i32() {
		return int32_t(u32());
	}

	float f32() {
		const uint32_t u = u32();
		float v = 0;
		std::memcpy(&v, &u, 4);
		return v;
	}
};

bool in_bound(uint32_t p_idx, uint32_t p_count) {
	return p_idx == INVALID_IDX || p_idx < p_count;
}

void write_free_list(std::vector<uint8_t> &r_out, const std::vector<uint32_t> &p_free) {
	write_u32(r_out, uint32_t(p_free.size()));
	for (uint32_t slot : p_free) {
		write_u32(r_out, slot);
	}
}

MeshFault read_free_list(Reader &r_in, uint32_t p_count, std::vector<uint32_t> &r_free) {
	const uint32_t n = r_in.u32();
	if (!r_in.ok) {
		return fault(MeshError::CORRUPT_DATA);
	}
	if (uint64_t(n) * 4u > uint64_t(r_in.end - r_in.p)) {
		return fault(MeshError::CORRUPT_DATA);
	}
	r_free.resize(n);
	for (uint32_t i = 0; i < n; i++) {
		const uint32_t slot = r_in.u32();
		if (!r_in.ok || slot >= p_count) {
			return fault(MeshError::CORRUPT_DATA, slot);
		}
		r_free[i] = slot;
	}
	return MeshFault{};
}

} // namespace

std::vector<uint8_t> serialize(const Mesh &p_mesh) {
	std::vector<uint8_t> out;
	write_u32(out, MAGIC);
	bool extended = false;
	for (const HalfEdge &he : p_mesh.half_edges)
		extended |= he.corner.surface.flags != 0 || !he.corner.surface.morphs.empty();
	write_u32(out, extended ? VERSION : 5);
	write_u32(out, uint32_t(p_mesh.vertices.size()));
	write_u32(out, uint32_t(p_mesh.half_edges.size()));
	write_u32(out, uint32_t(p_mesh.faces.size()));

	for (const Vertex &v : p_mesh.vertices) {
		write_u32(out, v.gen);
		write_i32(out, v.pos.x);
		write_i32(out, v.pos.y);
		write_i32(out, v.pos.z);
		write_u32(out, v.out.i);
	}
	for (const HalfEdge &he : p_mesh.half_edges) {
		write_u32(out, he.gen);
		write_u32(out, he.next.i);
		write_u32(out, he.twin.i);
		write_u32(out, he.origin.i);
		write_u32(out, he.face.i);
	}
	for (const Face &f : p_mesh.faces) {
		write_u32(out, f.gen);
		write_u32(out, f.he.i);
		write_f32(out, f.attrs.uv_scale.x);
		write_f32(out, f.attrs.uv_scale.y);
		write_f32(out, f.attrs.uv_offset.x);
		write_f32(out, f.attrs.uv_offset.y);
		write_f32(out, f.attrs.uv_rotation);
		write_u8(out, uint8_t(f.attrs.uv_axis));
		write_u8(out, f.attrs.smooth ? 1 : 0);
		write_u8(out, 0);
		write_u8(out, 0);
		write_u32(out, f.attrs.material_slot);
	}

	write_free_list(out, p_mesh.free_vertices);
	write_free_list(out, p_mesh.free_half_edges);
	write_free_list(out, p_mesh.free_faces);
	for (const HalfEdge &he : p_mesh.half_edges) write_u8(out, he.uv_seam ? 1 : 0);
	for (const Face &f : p_mesh.faces) {
		write_u8(out, f.attrs.uv_unwrapped ? 1 : 0);
		write_f32(out, f.attrs.uv_u.x);
		write_f32(out, f.attrs.uv_u.y);
		write_f32(out, f.attrs.uv_u.z);
		write_f32(out, f.attrs.uv_v.x);
		write_f32(out, f.attrs.uv_v.y);
		write_f32(out, f.attrs.uv_v.z);
		write_f32(out, f.attrs.uv_origin.x);
		write_f32(out, f.attrs.uv_origin.y);
	}
	for (const Face &f : p_mesh.faces) write_u32(out, f.attrs.uv_texture_resolution);
	for (const HalfEdge &he : p_mesh.half_edges) {
		write_u8(out, (he.corner.uv_explicit ? 1 : 0) | (he.corner.uv_pinned ? 2 : 0) | (he.hard ? 4 : 0));
		write_f32(out, he.corner.uv.x);
		write_f32(out, he.corner.uv.y);
	}
	if (extended) {
		for (const HalfEdge &he : p_mesh.half_edges) {
			const SurfaceAttrs &a = he.corner.surface;
			write_u8(out, a.flags);
			if (a.flags & SurfaceAttrs::UV2) for (int k = 0; k < 2; ++k) write_f32(out, a.uv2[k]);
			if (a.flags & SurfaceAttrs::COLOR) for (int k = 0; k < 4; ++k) write_f32(out, a.color[k]);
			if (a.flags & SurfaceAttrs::NORMAL) for (int k = 0; k < 3; ++k) write_f32(out, a.normal[k]);
			if (a.flags & SurfaceAttrs::TANGENT) for (float v : a.tangent) write_f32(out, v);
			if (a.flags & SurfaceAttrs::SKIN) {
				for (int32_t v : a.bones) write_i32(out, v);
				for (float v : a.weights) write_f32(out, v);
			}
			write_u32(out, uint32_t(a.morphs.size()));
			for (const MorphDelta &m : a.morphs) {
				for (int k = 0; k < 3; ++k) write_f32(out, m.position[k]);
				for (int k = 0; k < 3; ++k) write_f32(out, m.normal[k]);
				for (int k = 0; k < 3; ++k) write_f32(out, m.tangent[k]);
				write_f32(out, m.tangent_w);
			}
		}
	}
	return out;
}

MeshFault deserialize(const std::vector<uint8_t> &p_bytes, Mesh &r_out) {
	if (p_bytes.size() < 20) {
		return fault(MeshError::CORRUPT_DATA);
	}
	Reader r;
	r.p = p_bytes.data();
	r.end = p_bytes.data() + p_bytes.size();

	const uint32_t magic = r.u32();
	const uint32_t version = r.u32();
	if (!r.ok || magic != MAGIC || (version != VERSION && version != 5 && version != 4 && version != 3 && version != 2 && version != VERSION_SLOT_U8)) {
		return fault(MeshError::CORRUPT_DATA);
	}

	const uint32_t vcount = r.u32();
	const uint32_t hcount = r.u32();
	const uint32_t fcount = r.u32();
	if (!r.ok) {
		return fault(MeshError::CORRUPT_DATA);
	}
	const uint64_t face_bytes = version == VERSION_SLOT_U8 ? 32u : 36u;
	const uint64_t left = uint64_t(r.end - r.p);
	const uint64_t need = uint64_t(vcount) * 20u + uint64_t(hcount) * 20u + uint64_t(fcount) * face_bytes + 12u;
	if (need > left) {
		return fault(MeshError::CORRUPT_DATA);
	}

	Mesh tmp;
	tmp.vertices.resize(vcount);
	for (uint32_t i = 0; i < vcount; i++) {
		Vertex &v = tmp.vertices[i];
		v.gen = r.u32();
		v.pos.x = r.i32();
		v.pos.y = r.i32();
		v.pos.z = r.i32();
		v.out.i = r.u32();
		if (!r.ok || !in_bound(v.out.i, hcount)) {
			return fault(MeshError::CORRUPT_DATA, i);
		}
	}
	tmp.half_edges.resize(hcount);
	for (uint32_t i = 0; i < hcount; i++) {
		HalfEdge &he = tmp.half_edges[i];
		he.gen = r.u32();
		he.next.i = r.u32();
		he.twin.i = r.u32();
		he.origin.i = r.u32();
		he.face.i = r.u32();
		if (!r.ok || !in_bound(he.next.i, hcount) || !in_bound(he.twin.i, hcount) || !in_bound(he.origin.i, vcount) || !in_bound(he.face.i, fcount)) {
			return fault(MeshError::CORRUPT_DATA, i);
		}
	}
	tmp.faces.resize(fcount);
	for (uint32_t i = 0; i < fcount; i++) {
		Face &f = tmp.faces[i];
		f.gen = r.u32();
		f.he.i = r.u32();
		f.attrs.uv_scale.x = r.f32();
		f.attrs.uv_scale.y = r.f32();
		f.attrs.uv_offset.x = r.f32();
		f.attrs.uv_offset.y = r.f32();
		f.attrs.uv_rotation = r.f32();
		const uint8_t axis = r.u8();
		if (version == VERSION_SLOT_U8) {
			f.attrs.material_slot = r.u8();
			f.attrs.smooth = r.u8() != 0;
			(void)r.u8();
		} else {
			f.attrs.smooth = r.u8() != 0;
			(void)r.u8();
			(void)r.u8();
			f.attrs.material_slot = r.u32();
		}
		if (!r.ok || axis > uint8_t(UvAxis::Z) || !in_bound(f.he.i, hcount)) {
			return fault(MeshError::CORRUPT_DATA, i);
		}
		f.attrs.uv_axis = UvAxis(axis);
	}

	MeshFault fl = read_free_list(r, vcount, tmp.free_vertices);
	if (!fl.ok()) {
		return fl;
	}
	fl = read_free_list(r, hcount, tmp.free_half_edges);
	if (!fl.ok()) {
		return fl;
	}
	fl = read_free_list(r, fcount, tmp.free_faces);
	if (!fl.ok()) {
		return fl;
	}
	if (version >= 3) {
		for (HalfEdge &he : tmp.half_edges) {
			const uint8_t flag = r.u8();
			if (flag > 1) return fault(MeshError::CORRUPT_DATA);
			he.uv_seam = flag != 0;
		}
		for (Face &f : tmp.faces) {
			const uint8_t flag = r.u8();
			if (flag > 1) return fault(MeshError::CORRUPT_DATA);
			f.attrs.uv_unwrapped = flag != 0;
			f.attrs.uv_u.x = r.f32();
			f.attrs.uv_u.y = r.f32();
			f.attrs.uv_u.z = r.f32();
			f.attrs.uv_v.x = r.f32();
			f.attrs.uv_v.y = r.f32();
			f.attrs.uv_v.z = r.f32();
			f.attrs.uv_origin.x = r.f32();
			f.attrs.uv_origin.y = r.f32();
			for (float value : {f.attrs.uv_u.x, f.attrs.uv_u.y, f.attrs.uv_u.z,
					f.attrs.uv_v.x, f.attrs.uv_v.y, f.attrs.uv_v.z, f.attrs.uv_origin.x, f.attrs.uv_origin.y}) {
				if (!std::isfinite(value)) return fault(MeshError::CORRUPT_DATA);
			}
		}
		for (const HalfEdge &he : tmp.half_edges) {
			if (he.twin.i != INVALID_IDX && he.uv_seam != tmp.half_edges[he.twin.i].uv_seam)
				return fault(MeshError::CORRUPT_DATA);
		}
	}
	if (version >= 4) {
		for (Face &f : tmp.faces) f.attrs.uv_texture_resolution = r.u32();
	}
	if (version >= 5) {
		for (HalfEdge &he : tmp.half_edges) {
			const uint8_t flags = r.u8();
			he.corner.uv_explicit = (flags & 1) != 0;
			he.corner.uv_pinned = (flags & 2) != 0;
			he.hard = (flags & 4) != 0;
			he.corner.uv = godot::Vector2(r.f32(), 0);
			he.corner.uv.y = r.f32();
			if (flags > 7 || !std::isfinite(he.corner.uv.x) || !std::isfinite(he.corner.uv.y))
				return fault(MeshError::CORRUPT_DATA);
		}
		for (const HalfEdge &he : tmp.half_edges) {
			if (he.twin.i != INVALID_IDX && he.hard != tmp.half_edges[he.twin.i].hard)
				return fault(MeshError::CORRUPT_DATA);
		}
	}
	if (version >= 6) {
		for (HalfEdge &he : tmp.half_edges) {
			SurfaceAttrs &a = he.corner.surface;
			a.flags = r.u8();
			if (!r.ok || a.flags > 31) return fault(MeshError::CORRUPT_DATA);
			if (a.flags & SurfaceAttrs::UV2) for (int k = 0; k < 2; ++k) a.uv2[k] = r.f32();
			if (a.flags & SurfaceAttrs::COLOR) for (int k = 0; k < 4; ++k) a.color[k] = r.f32();
			if (a.flags & SurfaceAttrs::NORMAL) for (int k = 0; k < 3; ++k) a.normal[k] = r.f32();
			if (a.flags & SurfaceAttrs::TANGENT) for (float &v : a.tangent) v = r.f32();
			if (a.flags & SurfaceAttrs::SKIN) {
				for (int32_t &v : a.bones) v = r.i32();
				for (float &v : a.weights) v = r.f32();
			}
			const uint32_t count = r.u32();
			if (!r.ok || uint64_t(count) * 40 > uint64_t(r.end - r.p)) return fault(MeshError::CORRUPT_DATA);
			a.morphs.resize(count);
			for (MorphDelta &m : a.morphs) {
				for (int k = 0; k < 3; ++k) m.position[k] = r.f32();
				for (int k = 0; k < 3; ++k) m.normal[k] = r.f32();
				for (int k = 0; k < 3; ++k) m.tangent[k] = r.f32();
				m.tangent_w = r.f32();
			}
			if (!r.ok || !valid_surface_attrs(a)) return fault(MeshError::CORRUPT_DATA);
		}
	}
	if (!r.ok || r.p != r.end) {
		return fault(MeshError::CORRUPT_DATA);
	}

	fl = validate(tmp);
	if (!fl.ok()) {
		return fl;
	}
	r_out = std::move(tmp);
	return MeshFault{};
}

} // namespace slab
