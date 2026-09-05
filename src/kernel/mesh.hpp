#pragma once

#include "handles.hpp"
#include "quantize.hpp"

#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

namespace slab {

enum class UvAxis : uint8_t {
	AUTO = 0,
	X = 1,
	Y = 2,
	Z = 3,
};

struct FaceAttrs {
	godot::Vector2 uv_scale = godot::Vector2(1, 1);
	godot::Vector2 uv_offset = godot::Vector2(0, 0);
	float uv_rotation = 0.0f;
	UvAxis uv_axis = UvAxis::AUTO;
	uint8_t material_slot = 0;
	bool smooth = false;
};

struct Vertex {
	uint32_t gen = 0;
	IVec3 pos;
	HalfEdgeIdx out;
};

struct HalfEdge {
	uint32_t gen = 0;
	HalfEdgeIdx next;
	HalfEdgeIdx twin;
	VertexIdx origin;
	FaceIdx face;
};

struct Face {
	uint32_t gen = 0;
	HalfEdgeIdx he;
	FaceAttrs attrs;
};

enum class MeshError : uint8_t {
	OK = 0,
	STALE_HANDLE,
	NOT_CLOSED,
	TWIN_MISMATCH,
	NON_MANIFOLD_VERTEX,
	DEGENERATE_FACE,
	LOOP_TOO_SHORT,
	INCONSISTENT_ORIENTATION,
	INVERTED_VOLUME,
	RESULT_EMPTY,
	COORD_OUT_OF_RANGE,
	ADJACENT_SELECTION,
	SNAP_COLLAPSED_TOPOLOGY,
	NO_INTERSECTION,
	CORRUPT_DATA,
	INVALID_SELECTION,
};

struct MeshFault {
	MeshError code = MeshError::OK;
	uint32_t slot = INVALID_IDX;

	bool ok() const {
		return code == MeshError::OK;
	}
};

class Mesh {
public:
	int face_count() const;
	int edge_count() const;
	int vertex_count() const;

	bool alive(FaceId p_id) const;
	bool alive(EdgeId p_id) const;
	bool alive(VertexId p_id) const;

	godot::Vector3 position(VertexId p_id) const;
	IVec3 position_i(VertexId p_id) const;
	godot::Vector3 face_normal(FaceId p_id) const;
	FaceAttrs attrs(FaceId p_id) const;
	void face_corners(FaceId p_id, std::vector<VertexId> &r_out) const;
	void all_faces(std::vector<FaceId> &r_out) const;
	void all_vertices(std::vector<VertexId> &r_out) const;
	void all_edges(std::vector<EdgeId> &r_out) const;

	void edge_vertices(EdgeId p_id, VertexId &r_a, VertexId &r_b) const;
	void edge_faces(EdgeId p_id, FaceId &r_a, FaceId &r_b) const;
	void face_edges(FaceId p_id, std::vector<EdgeId> &r_out) const;
	void vertex_edges(VertexId p_id, std::vector<EdgeId> &r_out) const;
	void vertex_faces(VertexId p_id, std::vector<FaceId> &r_out) const;

	godot::Vector3 face_centroid(FaceId p_id) const;
	double face_area(FaceId p_id) const;
	godot::AABB local_aabb() const;

	double signed_volume() const;

private:
	std::vector<Vertex> vertices;
	std::vector<HalfEdge> half_edges;
	std::vector<Face> faces;
	std::vector<uint32_t> free_vertices;
	std::vector<uint32_t> free_half_edges;
	std::vector<uint32_t> free_faces;

	friend class MeshEdit;
	friend MeshFault validate(const Mesh &p_mesh);
	friend std::vector<uint8_t> serialize(const Mesh &p_mesh);
	friend MeshFault deserialize(const std::vector<uint8_t> &p_bytes, Mesh &r_out);

	bool _vertex_live(uint32_t p_slot) const;
	bool _face_live(uint32_t p_slot) const;
	bool _he_live(uint32_t p_slot) const;
	EdgeId _edge_id(uint32_t p_he) const;
};

MeshFault validate(const Mesh &p_mesh);

} // namespace slab
