#pragma once

#include "kernel/mesh_edit.hpp"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <vector>

namespace godot {

class SlabSolid : public Node3D {
	GDCLASS(SlabSolid, Node3D);

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	void set_data(const PackedByteArray &p_data);
	PackedByteArray get_data() const;

	void set_grid_step(float p_step);
	float get_grid_step() const;

	void set_prototype_color(const Color &p_color);
	Color get_prototype_color() const;

	void set_material(const Ref<Material> &p_material);
	Ref<Material> get_material() const;

	void set_collision_enabled(bool p_enabled);
	bool is_collision_enabled() const;

	PackedInt64Array get_faces() const;
	PackedInt64Array get_edges() const;
	PackedInt64Array get_vertices() const;
	bool is_alive(int64_t p_id) const;
	Vector3 face_centroid(int64_t p_face) const;
	Vector3 face_normal(int64_t p_face) const;
	PackedVector3Array face_corners(int64_t p_face) const;
	PackedVector3Array edge_endpoints(int64_t p_edge) const;
	Vector3 vertex_position(int64_t p_vertex) const;
	PackedInt64Array face_edges(int64_t p_face) const;
	PackedInt64Array edge_faces(int64_t p_edge) const;
	Dictionary face_uv(int64_t p_face) const;
	int face_count() const;
	int edge_count() const;
	int vertex_count() const;
	double volume() const;
	AABB get_local_aabb() const;
	Ref<ArrayMesh> build_mesh() const;

	int make_box(const Vector3 &p_size);
	int make_plane(const Vector2 &p_size);
	int make_stair(const Vector3 &p_size, int p_steps);
	int make_cylinder(float p_radius, float p_height, int p_sides);
	int make_arch(const Vector3 &p_size, int p_segments, float p_thickness);
	int make_prism(const PackedVector3Array &p_polygon, float p_height);
	int make_sweep(const PackedVector3Array &p_path, const Vector2 &p_profile, bool p_closed);

	int extrude_faces(const PackedInt64Array &p_faces, float p_distance);
	int inset_faces(const PackedInt64Array &p_faces, float p_amount);
	int delete_faces(const PackedInt64Array &p_faces);
	int flip_faces(const PackedInt64Array &p_faces);
	int subdivide_faces(const PackedInt64Array &p_faces);
	int merge_faces(const PackedInt64Array &p_faces);
	int set_face_uv(const PackedInt64Array &p_faces, const Vector2 &p_scale, const Vector2 &p_offset, float p_rotation);
	int set_face_material(const PackedInt64Array &p_faces, int p_slot);

	int bevel_edges(const PackedInt64Array &p_edges, float p_amount);
	int bridge_edges(const PackedInt64Array &p_edges);
	int connect_edges(const PackedInt64Array &p_edges);
	int insert_loop(int64_t p_edge, float p_t);
	int dissolve_edges(const PackedInt64Array &p_edges);

	int weld_vertices(const PackedInt64Array &p_vertices, float p_radius);
	int collapse_vertices(const PackedInt64Array &p_vertices);
	int connect_vertices(const PackedInt64Array &p_vertices);
	int move_vertices(const PackedInt64Array &p_vertices, const Vector3 &p_delta);

	int boolean_with(SlabSolid *p_other, int p_mode);
	int mirror(const Vector3 &p_axis);
	int center_pivot();
	int snap_to_grid();

private:
	slab::Mesh live_mesh;
	float grid_step = 0.5f;
	Color prototype_color = Color(0.62f, 0.64f, 0.68f);
	Ref<Material> material;
	bool collision_enabled = true;

	MeshInstance3D *mesh_instance = nullptr;
	StaticBody3D *body = nullptr;
	CollisionShape3D *collider = nullptr;

	void _ensure_children();
	void _rebuild();
	int _commit(slab::MeshEdit &&p_edit);
	int _unimplemented() const;
	bool _face_ids(const PackedInt64Array &p_ids, std::vector<slab::FaceId> &r_out) const;
	bool _edge_ids(const PackedInt64Array &p_ids, std::vector<slab::EdgeId> &r_out) const;
	bool _vertex_ids(const PackedInt64Array &p_ids, std::vector<slab::VertexId> &r_out) const;
};

} // namespace godot
