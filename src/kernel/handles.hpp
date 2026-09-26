#pragma once

#include <cstdint>

namespace slab {

struct VertexIdx {
	uint32_t i = 0xFFFFFFFFu;
};

struct HalfEdgeIdx {
	uint32_t i = 0xFFFFFFFFu;
};

struct FaceIdx {
	uint32_t i = 0xFFFFFFFFu;
};

static constexpr uint32_t INVALID_IDX = 0xFFFFFFFFu;

struct VertexId {
	uint32_t slot = 0;
	uint32_t gen = 0;
};

struct CornerId {
	uint32_t slot = 0;
	uint32_t gen = 0;
};

struct FaceId {
	uint32_t slot = 0;
	uint32_t gen = 0;
};

struct EdgeId {
	uint32_t slot = 0;
	uint32_t gen = 0;
};

inline int64_t pack(CornerId p_id) {
	return (int64_t(p_id.slot) << 32) | int64_t(p_id.gen);
}

inline CornerId unpack_corner(int64_t p_v) {
	return CornerId{ uint32_t(p_v >> 32), uint32_t(p_v) };
}

inline int64_t pack(FaceId p_id) {
	return (int64_t(p_id.slot) << 32) | int64_t(p_id.gen);
}

inline int64_t pack(EdgeId p_id) {
	return (int64_t(p_id.slot) << 32) | int64_t(p_id.gen);
}

inline int64_t pack(VertexId p_id) {
	return (int64_t(p_id.slot) << 32) | int64_t(p_id.gen);
}

inline FaceId unpack_face(int64_t p_v) {
	return FaceId{ uint32_t(p_v >> 32), uint32_t(p_v) };
}

inline EdgeId unpack_edge(int64_t p_v) {
	return EdgeId{ uint32_t(p_v >> 32), uint32_t(p_v) };
}

inline VertexId unpack_vertex(int64_t p_v) {
	return VertexId{ uint32_t(p_v >> 32), uint32_t(p_v) };
}

} // namespace slab
