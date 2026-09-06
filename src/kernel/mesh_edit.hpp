#pragma once

#include "mesh.hpp"

#include <vector>

namespace slab {

class MeshEdit {
public:
	MeshEdit() = default;
	static MeshEdit empty();
	explicit MeshEdit(const Mesh &p_base);

	FaceId make_lamina(const IVec3 *p_loop, int p_count);
	FaceId lift_loop(FaceId p_face);
	void move_vertex(VertexId p_v, IVec3 p_pos);
	void set_attrs(FaceId p_face, const FaceAttrs &p_attrs);

	VertexId split_edge(EdgeId p_edge, IVec3 p_pos);
	EdgeId split_face(FaceId p_face, VertexId p_a, VertexId p_b);
	MeshFault remove_face(FaceId p_face);
	MeshFault dissolve_edge(EdgeId p_edge);
	MeshFault collapse_edge(EdgeId p_edge);
	MeshFault append(const Mesh &p_other, bool p_flip);
	MeshFault replace_with(const Mesh &p_mesh);
	MeshFault assemble(const std::vector<std::vector<IVec3>> &p_loops);
	MeshFault flip_face(FaceId p_face);
	MeshFault flip_all();

	const Mesh &scratch() const {
		return work;
	}

	MeshFault last_fault() const {
		return fault;
	}

	void clear_fault() {
		fault = MeshFault{};
	}

	MeshFault commit(Mesh &r_out) &&;

private:
	Mesh work;
	MeshFault fault;

	VertexIdx _alloc_vertex(IVec3 p_pos);
	HalfEdgeIdx _alloc_half_edge();
	FaceIdx _alloc_face();
	void free_vertex(VertexIdx p_v);
	void free_half_edge(HalfEdgeIdx p_he);
	void free_face(FaceIdx p_f);
	bool loop_of(FaceId p_face, std::vector<HalfEdgeIdx> &r_out);
	int _valence(VertexIdx p_v) const;
	VertexId _id(VertexIdx p_v) const;
	FaceId _id(FaceIdx p_f) const;
	EdgeId _id(HalfEdgeIdx p_he) const;
};

} // namespace slab
