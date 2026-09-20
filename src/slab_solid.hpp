#pragma once

#include "kernel/mesh_edit.hpp"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <unordered_set>
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
	Dictionary get_edit_diagnostic() const;

	void set_grid_step(float p_step);
	float get_grid_step() const;

	void set_prototype_color(const Color &p_color);
	Color get_prototype_color() const;

	void set_material(const Ref<Material> &p_material);
	Ref<Material> get_material() const;

	void set_materials(const TypedArray<Material> &p_materials);
	TypedArray<Material> get_materials() const;

	void set_collision_enabled(bool p_enabled);
	bool is_collision_enabled() const;

	PackedInt64Array get_faces() const;
	PackedInt64Array get_last_edited_faces() const;
	PackedInt64Array get_edges() const;
	PackedInt64Array get_vertices() const;
	bool is_alive(int64_t p_id) const;
	Vector3 face_centroid(int64_t p_face) const;
	Vector3 face_normal(int64_t p_face) const;
	PackedVector3Array face_corners(int64_t p_face) const;
	PackedVector3Array edge_endpoints(int64_t p_edge) const;
	Vector3 vertex_position(int64_t p_vertex) const;
	PackedInt64Array face_edges(int64_t p_face) const;
	PackedInt64Array face_vertices(int64_t p_face) const;
	PackedInt64Array edge_faces(int64_t p_edge) const;
	PackedInt64Array edge_vertices(int64_t p_edge) const;
	Dictionary face_uv(int64_t p_face) const;
	PackedInt64Array get_uv_seams() const;
	int face_count() const;
	int edge_count() const;
	int vertex_count() const;
	double volume() const;
	AABB get_local_aabb() const;
	Ref<ArrayMesh> build_mesh() const;
	bool set_display_preview(const PackedByteArray &p_data);
	void clear_display_preview();
	bool has_display_preview() const;
	bool set_display_face_mask(const PackedInt64Array &p_faces);
	void clear_display_face_mask();
	bool has_display_face_mask() const;
	PackedInt64Array get_display_face_mask() const;
	bool is_display_face_visible(int64_t p_face) const;

	int make_box(const Vector3 &p_size);
	int make_plane(const Vector2 &p_size);
	Dictionary import_from_mesh(const PackedVector3Array &p_vertices, const PackedInt32Array &p_indices);
	int make_stair(const Vector3 &p_size, int p_steps);
	int make_cylinder(float p_radius, float p_height, int p_sides);
	int make_arch(float p_span, float p_depth, int p_segments, float p_thickness, double p_arc);
	int make_prism(const PackedVector3Array &p_polygon, float p_height);
	int make_sweep(const PackedVector3Array &p_path, const Vector2 &p_profile, bool p_closed);

	int extrude_faces(const PackedInt64Array &p_faces, float p_distance);
	int inset_faces(const PackedInt64Array &p_faces, float p_amount);
	int delete_faces(const PackedInt64Array &p_faces);
	int flip_faces(const PackedInt64Array &p_faces);
	int subdivide_faces(const PackedInt64Array &p_faces);
	int merge_faces(const PackedInt64Array &p_faces);
	int set_face_uv(const PackedInt64Array &p_faces, const Vector2 &p_scale, const Vector2 &p_offset, float p_rotation);
	int mark_uv_seams(const PackedInt64Array &p_edges, bool p_marked);
	Dictionary unwrap_uv(const PackedInt64Array &p_faces, float p_pixels_per_meter, int p_texture_resolution);
	Dictionary pack_uv(const PackedInt64Array &p_faces, int p_texture_resolution, int p_source_texture_resolution = 0);
	int set_face_material(const PackedInt64Array &p_faces, int p_slot);

	int bevel_edges(const PackedInt64Array &p_edges, float p_amount, int p_segments = 1);
	Dictionary preview_bevel(const PackedInt64Array &p_edges, float p_amount, int p_segments = 1) const;
	int bridge_edges(const PackedInt64Array &p_edges);
	int connect_edges(const PackedInt64Array &p_edges);
	int insert_loop(int64_t p_edge, float p_t);
	int insert_loops(int64_t p_edge, const PackedFloat32Array &p_positions);
	Dictionary preview_loop_cuts(int64_t p_edge, const PackedFloat32Array &p_positions) const;
	int dissolve_edges(const PackedInt64Array &p_edges);

	int weld_vertices(const PackedInt64Array &p_vertices, float p_radius);
	int collapse_vertices(const PackedInt64Array &p_vertices);
	int connect_vertices(const PackedInt64Array &p_vertices);
	int move_vertices(const PackedInt64Array &p_vertices, const Vector3 &p_delta);
	int transform_vertices(const PackedInt64Array &p_vertices, const Transform3D &p_transform);

	int boolean_with(SlabSolid *p_other, int p_mode);
	int plane_cut(const Vector3 &p_origin, const Vector3 &p_normal, bool p_keep_positive, int p_cap_material);
	Dictionary preview_plane_cut(const Vector3 &p_origin, const Vector3 &p_normal, bool p_keep_positive, int p_cap_material) const;
	int mirror(const Vector3 &p_axis);
	int center_pivot();
	int snap_to_grid();

private:
	slab::Mesh live_mesh;
	float grid_step = 0.5f;
	Color prototype_color = Color(0.62f, 0.64f, 0.68f);
	Ref<StandardMaterial3D> prototype_material;
	TypedArray<Material> materials;
	bool collision_enabled = true;
	PackedInt64Array last_edited_faces;
	Dictionary edit_diagnostic;

	MeshInstance3D *mesh_instance = nullptr;
	Ref<ArrayMesh> committed_mesh;
	std::vector<uint32_t> committed_surface_slots;
	StaticBody3D *body = nullptr;
	CollisionShape3D *collider = nullptr;
	bool display_preview_active = false;
	bool display_face_mask_active = false;
	std::unordered_set<int64_t> display_face_mask;

	void _ensure_children();
	void _rebuild();
	void _rebuild_from(const slab::Mesh &p_mesh, bool p_update_collision);
	void _assign_display(const Ref<ArrayMesh> &p_mesh, const std::vector<uint32_t> &p_surface_slots);
	void _assign_committed_display();
	Ref<ArrayMesh> _build_mesh_from(const slab::Mesh &p_mesh, std::vector<uint32_t> &r_surface_slots,
			PackedVector3Array *r_verts = nullptr, PackedInt32Array *r_indices = nullptr,
			const std::unordered_set<int64_t> *p_face_mask = nullptr) const;
	int _reject(const slab::Mesh &p_mesh, slab::MeshFault p_fault,
			slab::FaultElement p_fallback_element = slab::FaultElement::NONE,
			uint32_t p_fallback_slot = slab::INVALID_IDX);
	int _commit(slab::MeshEdit &&p_edit);
	int _unimplemented() const;
	bool _face_ids(const PackedInt64Array &p_ids, std::vector<slab::FaceId> &r_out) const;
	bool _edge_ids(const PackedInt64Array &p_ids, std::vector<slab::EdgeId> &r_out) const;
	bool _vertex_ids(const PackedInt64Array &p_ids, std::vector<slab::VertexId> &r_out) const;
};

} // namespace godot
