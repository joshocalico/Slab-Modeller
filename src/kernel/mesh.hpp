#pragma once

#include "handles.hpp"
#include "quantize.hpp"

#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <utility>
#include <vector>

namespace slab {

godot::Vector3 oriented_area_normal(const std::vector<IVec3> &p_loop);

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
	uint32_t material_slot = 0;
	bool smooth = false;
	// An unfolded planar face maps positions using these two covectors.
	bool uv_unwrapped = false;
	// Atlas width used to author this mapping. Zero means legacy/unknown.
	uint32_t uv_texture_resolution = 0;
	godot::Vector3 uv_u = godot::Vector3(1, 0, 0);
	godot::Vector3 uv_v = godot::Vector3(0, 1, 0);
	godot::Vector2 uv_origin;
};

struct Vertex {
	uint32_t gen = 0;
	IVec3 pos;
	HalfEdgeIdx out;
};

struct CornerAttrs {
	bool uv_explicit = false;
	bool uv_pinned = false;
	godot::Vector2 uv;
};

struct HalfEdge {
	CornerAttrs corner;
	bool hard = false;
	bool uv_seam = false;
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
	SELF_INTERSECTION,
	MULTIPLE_BOUNDARY_LOOPS,
};

enum class FaultElement : uint8_t { NONE, VERTEX, HALF_EDGE, FACE };

struct MeshFault {
	MeshError code = MeshError::OK;
	uint32_t slot = INVALID_IDX;
	// Diagnostic locations belong to the rejected scratch mesh, not the live mesh.
	FaultElement element = FaultElement::NONE;
	uint32_t related_slot = INVALID_IDX;

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
	bool alive(CornerId p_id) const;
	void face_corner_ids(FaceId p_id, std::vector<CornerId> &r_out) const;
	bool corner_location(CornerId p_id, FaceId &r_face, uint32_t &r_index) const;
	bool alive(EdgeId p_id) const;
	bool alive(VertexId p_id) const;

	godot::Vector3 position(VertexId p_id) const;
	IVec3 position_i(VertexId p_id) const;
	godot::Vector3 face_normal(FaceId p_id) const;
	FaceAttrs attrs(FaceId p_id) const;
	void face_corner_attrs(FaceId p_id, std::vector<CornerAttrs> &r_out) const;
	bool edge_hard(EdgeId p_id) const;
	void face_corners(FaceId p_id, std::vector<VertexId> &r_out) const;
	void all_faces(std::vector<FaceId> &r_out) const;
	void all_vertices(std::vector<VertexId> &r_out) const;
	void all_edges(std::vector<EdgeId> &r_out) const;

	void edge_vertices(EdgeId p_id, VertexId &r_a, VertexId &r_b) const;
	void edge_faces(EdgeId p_id, FaceId &r_a, FaceId &r_b) const;
	bool edge_uv_seam(EdgeId p_id) const;
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
	friend void diagnostic_segments(const Mesh &p_mesh, const MeshFault &p_fault,
			std::vector<std::pair<IVec3, IVec3>> &r_out);

	bool _vertex_live(uint32_t p_slot) const;
	bool _face_live(uint32_t p_slot) const;
	bool _he_live(uint32_t p_slot) const;
	EdgeId _edge_id(uint32_t p_he) const;
};

MeshFault validate(const Mesh &p_mesh);

// Extracts locations from the mesh that produced the fault. Unknown or stale
// locations intentionally produce no segments.
void diagnostic_segments(const Mesh &p_mesh, const MeshFault &p_fault,
		std::vector<std::pair<IVec3, IVec3>> &r_out);

} // namespace slab
