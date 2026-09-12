#include "slab_solid.hpp"

#include "kernel/emit.hpp"
#include "kernel/handles.hpp"
#include "kernel/ops/bevel.hpp"
#include "kernel/ops/boolean.hpp"
#include "kernel/ops/bridge.hpp"
#include "kernel/ops/edit.hpp"
#include "kernel/ops/inset.hpp"
#include "kernel/ops/loop.hpp"
#include "kernel/ops/offset_loop.hpp"
#include "kernel/ops/primitives.hpp"
#include "kernel/ops/subdivide.hpp"
#include "kernel/ops/weld.hpp"
#include "kernel/quantize.hpp"
#include "kernel/serialize.hpp"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/shape3d.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <cstring>
#include <map>
#include <utility>

using namespace godot;

void SlabSolid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_data", "data"), &SlabSolid::set_data);
	ClassDB::bind_method(D_METHOD("get_data"), &SlabSolid::get_data);
	ClassDB::bind_method(D_METHOD("set_grid_step", "step"), &SlabSolid::set_grid_step);
	ClassDB::bind_method(D_METHOD("get_grid_step"), &SlabSolid::get_grid_step);
	ClassDB::bind_method(D_METHOD("set_prototype_color", "color"), &SlabSolid::set_prototype_color);
	ClassDB::bind_method(D_METHOD("get_prototype_color"), &SlabSolid::get_prototype_color);
	ClassDB::bind_method(D_METHOD("set_material", "material"), &SlabSolid::set_material);
	ClassDB::bind_method(D_METHOD("get_material"), &SlabSolid::get_material);
	ClassDB::bind_method(D_METHOD("set_materials", "materials"), &SlabSolid::set_materials);
	ClassDB::bind_method(D_METHOD("get_materials"), &SlabSolid::get_materials);
	ClassDB::bind_method(D_METHOD("set_collision_enabled", "enabled"), &SlabSolid::set_collision_enabled);
	ClassDB::bind_method(D_METHOD("is_collision_enabled"), &SlabSolid::is_collision_enabled);

	ClassDB::bind_method(D_METHOD("get_faces"), &SlabSolid::get_faces);
	ClassDB::bind_method(D_METHOD("get_edges"), &SlabSolid::get_edges);
	ClassDB::bind_method(D_METHOD("get_vertices"), &SlabSolid::get_vertices);
	ClassDB::bind_method(D_METHOD("is_alive", "id"), &SlabSolid::is_alive);
	ClassDB::bind_method(D_METHOD("face_centroid", "face"), &SlabSolid::face_centroid);
	ClassDB::bind_method(D_METHOD("face_normal", "face"), &SlabSolid::face_normal);
	ClassDB::bind_method(D_METHOD("face_corners", "face"), &SlabSolid::face_corners);
	ClassDB::bind_method(D_METHOD("edge_endpoints", "edge"), &SlabSolid::edge_endpoints);
	ClassDB::bind_method(D_METHOD("vertex_position", "vertex"), &SlabSolid::vertex_position);
	ClassDB::bind_method(D_METHOD("face_edges", "face"), &SlabSolid::face_edges);
	ClassDB::bind_method(D_METHOD("face_vertices", "face"), &SlabSolid::face_vertices);
	ClassDB::bind_method(D_METHOD("edge_faces", "edge"), &SlabSolid::edge_faces);
	ClassDB::bind_method(D_METHOD("edge_vertices", "edge"), &SlabSolid::edge_vertices);
	ClassDB::bind_method(D_METHOD("face_uv", "face"), &SlabSolid::face_uv);
	ClassDB::bind_method(D_METHOD("face_count"), &SlabSolid::face_count);
	ClassDB::bind_method(D_METHOD("edge_count"), &SlabSolid::edge_count);
	ClassDB::bind_method(D_METHOD("vertex_count"), &SlabSolid::vertex_count);
	ClassDB::bind_method(D_METHOD("volume"), &SlabSolid::volume);
	ClassDB::bind_method(D_METHOD("get_local_aabb"), &SlabSolid::get_local_aabb);
	ClassDB::bind_method(D_METHOD("build_mesh"), &SlabSolid::build_mesh);

	ClassDB::bind_method(D_METHOD("make_box", "size"), &SlabSolid::make_box);
	ClassDB::bind_method(D_METHOD("make_plane", "size"), &SlabSolid::make_plane);
	ClassDB::bind_method(D_METHOD("make_stair", "size", "steps"), &SlabSolid::make_stair);
	ClassDB::bind_method(D_METHOD("make_cylinder", "radius", "height", "sides"), &SlabSolid::make_cylinder);
	ClassDB::bind_method(D_METHOD("make_arch", "span", "depth", "segments", "thickness", "arc"), &SlabSolid::make_arch, DEFVAL(Math_PI));
	ClassDB::bind_method(D_METHOD("make_prism", "polygon", "height"), &SlabSolid::make_prism);
	ClassDB::bind_method(D_METHOD("make_sweep", "path", "profile", "closed"), &SlabSolid::make_sweep);

	ClassDB::bind_method(D_METHOD("extrude_faces", "faces", "distance"), &SlabSolid::extrude_faces);
	ClassDB::bind_method(D_METHOD("inset_faces", "faces", "amount"), &SlabSolid::inset_faces);
	ClassDB::bind_method(D_METHOD("delete_faces", "faces"), &SlabSolid::delete_faces);
	ClassDB::bind_method(D_METHOD("flip_faces", "faces"), &SlabSolid::flip_faces);
	ClassDB::bind_method(D_METHOD("subdivide_faces", "faces"), &SlabSolid::subdivide_faces);
	ClassDB::bind_method(D_METHOD("merge_faces", "faces"), &SlabSolid::merge_faces);
	ClassDB::bind_method(D_METHOD("set_face_uv", "faces", "scale", "offset", "rotation"), &SlabSolid::set_face_uv);
	ClassDB::bind_method(D_METHOD("set_face_material", "faces", "slot"), &SlabSolid::set_face_material);

	ClassDB::bind_method(D_METHOD("bevel_edges", "edges", "amount"), &SlabSolid::bevel_edges);
	ClassDB::bind_method(D_METHOD("bridge_edges", "edges"), &SlabSolid::bridge_edges);
	ClassDB::bind_method(D_METHOD("connect_edges", "edges"), &SlabSolid::connect_edges);
	ClassDB::bind_method(D_METHOD("insert_loop", "edge", "t"), &SlabSolid::insert_loop);
	ClassDB::bind_method(D_METHOD("dissolve_edges", "edges"), &SlabSolid::dissolve_edges);

	ClassDB::bind_method(D_METHOD("weld_vertices", "vertices", "radius"), &SlabSolid::weld_vertices);
	ClassDB::bind_method(D_METHOD("collapse_vertices", "vertices"), &SlabSolid::collapse_vertices);
	ClassDB::bind_method(D_METHOD("connect_vertices", "vertices"), &SlabSolid::connect_vertices);
	ClassDB::bind_method(D_METHOD("move_vertices", "vertices", "delta"), &SlabSolid::move_vertices);

	ClassDB::bind_method(D_METHOD("boolean_with", "other", "mode"), &SlabSolid::boolean_with);
	ClassDB::bind_method(D_METHOD("mirror", "axis"), &SlabSolid::mirror);
	ClassDB::bind_method(D_METHOD("center_pivot"), &SlabSolid::center_pivot);
	ClassDB::bind_method(D_METHOD("snap_to_grid"), &SlabSolid::snap_to_grid);

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_BYTE_ARRAY, "data", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_data", "get_data");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "grid_step", PROPERTY_HINT_RANGE, "0.05,8,0.05,suffix:m"), "set_grid_step", "get_grid_step");
	ADD_PROPERTY(PropertyInfo(Variant::COLOR, "prototype_color"), "set_prototype_color", "get_prototype_color");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "materials", PROPERTY_HINT_ARRAY_TYPE, "Material"), "set_materials", "get_materials");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "material", PROPERTY_HINT_RESOURCE_TYPE, "Material", PROPERTY_USAGE_NO_EDITOR | PROPERTY_USAGE_STORAGE), "set_material", "get_material");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "collision_enabled"), "set_collision_enabled", "is_collision_enabled");

	ADD_SIGNAL(MethodInfo("topology_changed"));
}

void SlabSolid::_notification(int p_what) {
	if (p_what == NOTIFICATION_READY || p_what == NOTIFICATION_ENTER_TREE) {
		if (live_mesh.face_count() < 1) {
			make_box(Vector3(2, 2, 2));
			return;
		}
		_rebuild();
	}
}

void SlabSolid::set_data(const PackedByteArray &p_data) {
	std::vector<uint8_t> bytes(size_t(p_data.size()));
	if (!bytes.empty()) {
		std::memcpy(bytes.data(), p_data.ptr(), bytes.size());
	}
	slab::Mesh loaded;
	const slab::MeshFault fault = slab::deserialize(bytes, loaded);
	if (!fault.ok()) {
		live_mesh = slab::Mesh();
		_rebuild();
		return;
	}
	live_mesh = std::move(loaded);
	_rebuild();
	emit_signal("topology_changed");
}

PackedByteArray SlabSolid::get_data() const {
	const std::vector<uint8_t> bytes = slab::serialize(live_mesh);
	PackedByteArray out;
	out.resize(int64_t(bytes.size()));
	if (!bytes.empty()) {
		std::memcpy(out.ptrw(), bytes.data(), bytes.size());
	}
	return out;
}

void SlabSolid::set_grid_step(float p_step) {
	grid_step = MAX(p_step, 0.0f);
}

float SlabSolid::get_grid_step() const {
	return grid_step;
}

void SlabSolid::set_prototype_color(const Color &p_color) {
	prototype_color = p_color;
	_rebuild();
}

Color SlabSolid::get_prototype_color() const {
	return prototype_color;
}

void SlabSolid::set_material(const Ref<Material> &p_material) {
	if (materials.size() < 1) {
		materials.resize(1);
	}
	materials[0] = p_material;
	_rebuild();
}

Ref<Material> SlabSolid::get_material() const {
	if (materials.size() < 1) {
		return Ref<Material>();
	}
	return materials[0];
}

void SlabSolid::set_materials(const TypedArray<Material> &p_materials) {
	materials = p_materials;
	_rebuild();
}

TypedArray<Material> SlabSolid::get_materials() const {
	return materials;
}

void SlabSolid::set_collision_enabled(bool p_enabled) {
	if (collision_enabled == p_enabled) {
		return;
	}
	collision_enabled = p_enabled;
	if (collider == nullptr) {
		return;
	}
	collider->set_disabled(!collision_enabled);
	if (body != nullptr) {
		body->set_visible(collision_enabled);
	}
	if (collision_enabled && collider->get_shape().is_null() && live_mesh.face_count() > 0) {
		_rebuild();
	}
}

bool SlabSolid::is_collision_enabled() const {
	return collision_enabled;
}

PackedInt64Array SlabSolid::get_faces() const {
	std::vector<slab::FaceId> ids;
	live_mesh.all_faces(ids);
	PackedInt64Array out;
	out.resize(int64_t(ids.size()));
	for (int64_t i = 0; i < out.size(); i++) {
		out.set(i, slab::pack(ids[size_t(i)]));
	}
	return out;
}

PackedInt64Array SlabSolid::get_edges() const {
	std::vector<slab::EdgeId> ids;
	live_mesh.all_edges(ids);
	PackedInt64Array out;
	out.resize(int64_t(ids.size()));
	for (int64_t i = 0; i < out.size(); i++) {
		out.set(i, slab::pack(ids[size_t(i)]));
	}
	return out;
}

PackedInt64Array SlabSolid::get_vertices() const {
	std::vector<slab::VertexId> ids;
	live_mesh.all_vertices(ids);
	PackedInt64Array out;
	out.resize(int64_t(ids.size()));
	for (int64_t i = 0; i < out.size(); i++) {
		out.set(i, slab::pack(ids[size_t(i)]));
	}
	return out;
}

bool SlabSolid::is_alive(int64_t p_id) const {
	return live_mesh.alive(slab::unpack_face(p_id)) || live_mesh.alive(slab::unpack_edge(p_id)) || live_mesh.alive(slab::unpack_vertex(p_id));
}

Vector3 SlabSolid::face_centroid(int64_t p_face) const {
	return live_mesh.face_centroid(slab::unpack_face(p_face));
}

Vector3 SlabSolid::face_normal(int64_t p_face) const {
	return live_mesh.face_normal(slab::unpack_face(p_face));
}

PackedVector3Array SlabSolid::face_corners(int64_t p_face) const {
	std::vector<slab::VertexId> corners;
	live_mesh.face_corners(slab::unpack_face(p_face), corners);
	PackedVector3Array out;
	out.resize(int64_t(corners.size()));
	for (int64_t i = 0; i < out.size(); i++) {
		out.set(i, live_mesh.position(corners[size_t(i)]));
	}
	return out;
}

PackedVector3Array SlabSolid::edge_endpoints(int64_t p_edge) const {
	slab::VertexId a;
	slab::VertexId b;
	live_mesh.edge_vertices(slab::unpack_edge(p_edge), a, b);
	PackedVector3Array out;
	if (!live_mesh.alive(a) || !live_mesh.alive(b)) {
		return out;
	}
	out.resize(2);
	out.set(0, live_mesh.position(a));
	out.set(1, live_mesh.position(b));
	return out;
}

Vector3 SlabSolid::vertex_position(int64_t p_vertex) const {
	return live_mesh.position(slab::unpack_vertex(p_vertex));
}

PackedInt64Array SlabSolid::face_edges(int64_t p_face) const {
	std::vector<slab::EdgeId> ids;
	live_mesh.face_edges(slab::unpack_face(p_face), ids);
	PackedInt64Array out;
	out.resize(int64_t(ids.size()));
	for (int64_t i = 0; i < out.size(); i++) {
		out.set(i, slab::pack(ids[size_t(i)]));
	}
	return out;
}

PackedInt64Array SlabSolid::face_vertices(int64_t p_face) const {
	std::vector<slab::VertexId> ids;
	live_mesh.face_corners(slab::unpack_face(p_face), ids);
	PackedInt64Array out;
	out.resize(int64_t(ids.size()));
	for (int64_t i = 0; i < out.size(); i++) {
		out.set(i, slab::pack(ids[size_t(i)]));
	}
	return out;
}

PackedInt64Array SlabSolid::edge_faces(int64_t p_edge) const {
	slab::FaceId a;
	slab::FaceId b;
	live_mesh.edge_faces(slab::unpack_edge(p_edge), a, b);
	PackedInt64Array out;
	if (live_mesh.alive(a)) {
		out.push_back(slab::pack(a));
	}
	if (live_mesh.alive(b)) {
		out.push_back(slab::pack(b));
	}
	return out;
}

PackedInt64Array SlabSolid::edge_vertices(int64_t p_edge) const {
	slab::VertexId a;
	slab::VertexId b;
	live_mesh.edge_vertices(slab::unpack_edge(p_edge), a, b);
	PackedInt64Array out;
	if (live_mesh.alive(a)) {
		out.push_back(slab::pack(a));
	}
	if (live_mesh.alive(b)) {
		out.push_back(slab::pack(b));
	}
	return out;
}

Dictionary SlabSolid::face_uv(int64_t p_face) const {
	Dictionary out;
	const slab::FaceId id = slab::unpack_face(p_face);
	if (!live_mesh.alive(id)) {
		return out;
	}
	const slab::FaceAttrs attrs = live_mesh.attrs(id);
	out["scale"] = attrs.uv_scale;
	out["offset"] = attrs.uv_offset;
	out["rotation"] = attrs.uv_rotation;
	out["axis"] = int(attrs.uv_axis);
	out["slot"] = int(attrs.material_slot);
	return out;
}

int SlabSolid::face_count() const {
	return live_mesh.face_count();
}

int SlabSolid::edge_count() const {
	return live_mesh.edge_count();
}

int SlabSolid::vertex_count() const {
	return live_mesh.vertex_count();
}

double SlabSolid::volume() const {
	return live_mesh.signed_volume();
}

AABB SlabSolid::get_local_aabb() const {
	return live_mesh.local_aabb();
}

Ref<ArrayMesh> SlabSolid::build_mesh() const {
	Ref<ArrayMesh> out;
	if (mesh_instance != nullptr) {
		out = mesh_instance->get_mesh();
	}
	if (out.is_null()) {
		out.instantiate();
	}
	return out;
}

int SlabSolid::make_box(const Vector3 &p_size) {
	slab::MeshEdit edit = slab::MeshEdit::empty();
	const slab::MeshFault fault = slab::ops::box(edit, p_size);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::extrude_faces(const PackedInt64Array &p_faces, float p_distance) {
	std::vector<slab::FaceId> ids;
	if (!_face_ids(p_faces, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::extrude(edit, ids, p_distance);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::set_face_uv(const PackedInt64Array &p_faces, const Vector2 &p_scale, const Vector2 &p_offset, float p_rotation) {
	std::vector<slab::FaceId> ids;
	if (!_face_ids(p_faces, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	for (const slab::FaceId id : ids) {
		slab::FaceAttrs attrs = edit.scratch().attrs(id);
		attrs.uv_scale = p_scale;
		attrs.uv_offset = p_offset;
		attrs.uv_rotation = p_rotation;
		edit.set_attrs(id, attrs);
	}
	if (!edit.last_fault().ok()) {
		return int(edit.last_fault().code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::make_plane(const Vector2 &p_size) {
	slab::MeshEdit edit = slab::MeshEdit::empty();
	const slab::MeshFault fault = slab::ops::plane(edit, p_size, grid_step);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::make_stair(const Vector3 &p_size, int p_steps) {
	slab::MeshEdit edit = slab::MeshEdit::empty();
	const slab::MeshFault fault = slab::ops::stair(edit, p_size, p_steps);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::make_cylinder(float p_radius, float p_height, int p_sides) {
	slab::MeshEdit edit = slab::MeshEdit::empty();
	const slab::MeshFault fault = slab::ops::cylinder(edit, p_radius, p_height, p_sides);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::make_arch(float p_span, float p_depth, int p_segments, float p_thickness, double p_arc) {
	slab::MeshEdit edit = slab::MeshEdit::empty();
	const slab::MeshFault fault = slab::ops::arch(edit, p_span, p_depth, p_segments, p_thickness, p_arc);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::make_prism(const PackedVector3Array &p_polygon, float p_height) {
	std::vector<slab::IVec3> loop(size_t(p_polygon.size()));
	for (int64_t i = 0; i < p_polygon.size(); i++) {
		if (!slab::quantize(p_polygon[i], loop[size_t(i)])) {
			return int(slab::MeshError::COORD_OUT_OF_RANGE);
		}
	}
	slab::IVec3 height;
	if (!slab::quantize(Vector3(0, p_height, 0), height)) {
		return int(slab::MeshError::COORD_OUT_OF_RANGE);
	}
	slab::MeshEdit edit = slab::MeshEdit::empty();
	const slab::MeshFault fault = slab::ops::prism(edit, loop.data(), int(loop.size()), height.y);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::make_sweep(const PackedVector3Array &p_path, const Vector2 &p_profile, bool p_closed) {
	std::vector<slab::IVec3> path(size_t(p_path.size()));
	for (int64_t i = 0; i < p_path.size(); i++) {
		if (!slab::quantize(p_path[i], path[size_t(i)])) {
			return int(slab::MeshError::COORD_OUT_OF_RANGE);
		}
	}
	slab::IVec3 half;
	if (!slab::quantize(Vector3(p_profile.x * 0.5f, p_profile.y * 0.5f, 0), half)) {
		return int(slab::MeshError::COORD_OUT_OF_RANGE);
	}
	if (half.x == 0 || half.y == 0) {
		return int(slab::MeshError::DEGENERATE_FACE);
	}
	const slab::IVec3 profile[4] = {
		slab::IVec3{ -half.x, -half.y, 0 },
		slab::IVec3{ half.x, -half.y, 0 },
		slab::IVec3{ half.x, half.y, 0 },
		slab::IVec3{ -half.x, half.y, 0 },
	};
	slab::MeshEdit edit = slab::MeshEdit::empty();
	const slab::MeshFault fault = slab::ops::sweep(edit, path.data(), int(path.size()), profile, 4, p_closed);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::inset_faces(const PackedInt64Array &p_faces, float p_amount) {
	std::vector<slab::FaceId> ids;
	if (!_face_ids(p_faces, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::inset(edit, ids, p_amount);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::delete_faces(const PackedInt64Array &p_faces) {
	std::vector<slab::FaceId> ids;
	if (!_face_ids(p_faces, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::delete_faces(edit, ids);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::flip_faces(const PackedInt64Array &p_faces) {
	std::vector<slab::FaceId> ids;
	if (!_face_ids(p_faces, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::flip_faces(edit, ids);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::subdivide_faces(const PackedInt64Array &p_faces) {
	std::vector<slab::FaceId> ids;
	if (!_face_ids(p_faces, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::subdivide(edit, ids);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::merge_faces(const PackedInt64Array &p_faces) {
	std::vector<slab::FaceId> ids;
	if (!_face_ids(p_faces, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::merge_faces(edit, ids);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::set_face_material(const PackedInt64Array &p_faces, int p_slot) {
	if (p_slot < 0) {
		return int(slab::MeshError::INVALID_SELECTION);
	}
	std::vector<slab::FaceId> ids;
	if (!_face_ids(p_faces, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::set_face_material(edit, ids, uint32_t(p_slot));
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::bevel_edges(const PackedInt64Array &p_edges, float p_amount) {
	std::vector<slab::EdgeId> ids;
	if (!_edge_ids(p_edges, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::bevel(edit, ids, p_amount);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::bridge_edges(const PackedInt64Array &p_edges) {
	std::vector<slab::EdgeId> ids;
	if (!_edge_ids(p_edges, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	if (ids.size() != 2) {
		return int(slab::MeshError::INVALID_SELECTION);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::bridge(edit, ids[0], ids[1]);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::connect_edges(const PackedInt64Array &p_edges) {
	std::vector<slab::EdgeId> ids;
	if (!_edge_ids(p_edges, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	if (ids.size() != 2) {
		return int(slab::MeshError::INVALID_SELECTION);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::connect_edges(edit, ids[0], ids[1]);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::insert_loop(int64_t p_edge, float p_t) {
	const slab::EdgeId id = slab::unpack_edge(p_edge);
	if (!live_mesh.alive(id)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::insert_loop(edit, id, p_t);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::dissolve_edges(const PackedInt64Array &p_edges) {
	std::vector<slab::EdgeId> ids;
	if (!_edge_ids(p_edges, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::dissolve_edges(edit, ids);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::weld_vertices(const PackedInt64Array &p_vertices, float p_radius) {
	std::vector<slab::VertexId> ids;
	if (!_vertex_ids(p_vertices, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::weld(edit, ids, p_radius);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::collapse_vertices(const PackedInt64Array &p_vertices) {
	std::vector<slab::VertexId> ids;
	if (!_vertex_ids(p_vertices, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::collapse(edit, ids);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::connect_vertices(const PackedInt64Array &p_vertices) {
	std::vector<slab::VertexId> ids;
	if (!_vertex_ids(p_vertices, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	if (ids.size() != 2) {
		return int(slab::MeshError::INVALID_SELECTION);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::connect_vertices(edit, ids[0], ids[1]);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::move_vertices(const PackedInt64Array &p_vertices, const Vector3 &p_delta) {
	std::vector<slab::VertexId> ids;
	if (!_vertex_ids(p_vertices, ids)) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::move_vertices(edit, ids, p_delta);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::boolean_with(SlabSolid *p_other, int p_mode) {
	if (p_other == nullptr) {
		return int(slab::MeshError::STALE_HANDLE);
	}
	slab::Mesh cutter = p_other->live_mesh;
	const Transform3D to_host = get_global_transform().affine_inverse() * p_other->get_global_transform();
	const bool moved = to_host.origin != Vector3() || to_host.basis != Basis();
	if (moved) {
		slab::MeshEdit xf(cutter);
		std::vector<slab::VertexId> verts;
		cutter.all_vertices(verts);
		for (const slab::VertexId id : verts) {
			slab::IVec3 q;
			if (!slab::quantize(to_host.xform(cutter.position(id)), q)) {
				return int(slab::MeshError::COORD_OUT_OF_RANGE);
			}
			xf.move_vertex(id, q);
		}
		const slab::MeshFault baked = std::move(xf).commit(cutter);
		if (!baked.ok()) {
			return int(baked.code);
		}
	}
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::boolean(edit, cutter, p_mode);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::mirror(const Vector3 &p_axis) {
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::mirror(edit, p_axis);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::center_pivot() {
	const Vector3 c = live_mesh.local_aabb().position + live_mesh.local_aabb().size * 0.5f;
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::center_pivot(edit);
	if (!fault.ok()) {
		return int(fault.code);
	}
	const int err = _commit(std::move(edit));
	if (err == 0) {
		set_position(get_position() + c);
	}
	return err;
}

int SlabSolid::snap_to_grid() {
	slab::MeshEdit edit(live_mesh);
	const slab::MeshFault fault = slab::ops::snap_to_grid(edit, grid_step);
	if (!fault.ok()) {
		return int(fault.code);
	}
	return _commit(std::move(edit));
}

int SlabSolid::_unimplemented() const {
	return int(slab::MeshError::COORD_OUT_OF_RANGE);
}

bool SlabSolid::_face_ids(const PackedInt64Array &p_ids, std::vector<slab::FaceId> &r_out) const {
	r_out.clear();
	r_out.reserve(size_t(p_ids.size()));
	for (int64_t i = 0; i < p_ids.size(); i++) {
		const slab::FaceId id = slab::unpack_face(p_ids[i]);
		if (!live_mesh.alive(id)) {
			r_out.clear();
			return false;
		}
		r_out.push_back(id);
	}
	return true;
}

bool SlabSolid::_edge_ids(const PackedInt64Array &p_ids, std::vector<slab::EdgeId> &r_out) const {
	r_out.clear();
	r_out.reserve(size_t(p_ids.size()));
	for (int64_t i = 0; i < p_ids.size(); i++) {
		const slab::EdgeId id = slab::unpack_edge(p_ids[i]);
		if (!live_mesh.alive(id)) {
			r_out.clear();
			return false;
		}
		r_out.push_back(id);
	}
	return true;
}

bool SlabSolid::_vertex_ids(const PackedInt64Array &p_ids, std::vector<slab::VertexId> &r_out) const {
	r_out.clear();
	r_out.reserve(size_t(p_ids.size()));
	for (int64_t i = 0; i < p_ids.size(); i++) {
		const slab::VertexId id = slab::unpack_vertex(p_ids[i]);
		if (!live_mesh.alive(id)) {
			r_out.clear();
			return false;
		}
		r_out.push_back(id);
	}
	return true;
}

int SlabSolid::_commit(slab::MeshEdit &&p_edit) {
	const slab::MeshFault fault = std::move(p_edit).commit(live_mesh);
	if (!fault.ok()) {
		return int(fault.code);
	}
	_rebuild();
	emit_signal("topology_changed");
	return 0;
}

void SlabSolid::_ensure_children() {
	if (mesh_instance == nullptr) {
		mesh_instance = Object::cast_to<MeshInstance3D>(get_node_or_null("Mesh"));
		if (mesh_instance == nullptr) {
			mesh_instance = memnew(MeshInstance3D);
			mesh_instance->set_name("Mesh");
			add_child(mesh_instance, false, Node::INTERNAL_MODE_BACK);
		} else {
			Node *parent = mesh_instance->get_parent();
			if (parent == this) {
				remove_child(mesh_instance);
			}
			add_child(mesh_instance, false, Node::INTERNAL_MODE_BACK);
		}
	}
	if (body == nullptr) {
		body = Object::cast_to<StaticBody3D>(get_node_or_null("__body"));
		if (body == nullptr) {
			body = memnew(StaticBody3D);
			body->set_name("__body");
			add_child(body, false, Node::INTERNAL_MODE_BACK);
		}
	}
	if (collider == nullptr) {
		collider = Object::cast_to<CollisionShape3D>(body->get_node_or_null("__shape"));
		if (collider == nullptr) {
			collider = memnew(CollisionShape3D);
			collider->set_name("__shape");
			body->add_child(collider);
		}
	}
}

void SlabSolid::_rebuild() {
	_ensure_children();

	slab::EmitOut emitted;
	slab::emit_arrays(live_mesh, emitted);

	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedVector2Array uvs;
	PackedInt32Array indices;
	verts.resize(int64_t(emitted.verts.size()));
	normals.resize(int64_t(emitted.normals.size()));
	uvs.resize(int64_t(emitted.uvs.size()));
	indices.resize(int64_t(emitted.indices.size()));
	for (int64_t i = 0; i < verts.size(); i++) {
		verts.set(i, emitted.verts[size_t(i)]);
	}
	for (int64_t i = 0; i < normals.size(); i++) {
		normals.set(i, emitted.normals[size_t(i)]);
	}
	for (int64_t i = 0; i < uvs.size(); i++) {
		uvs.set(i, emitted.uvs[size_t(i)]);
	}
	for (int64_t i = 0; i < indices.size(); i++) {
		indices.set(i, emitted.indices[size_t(i)]);
	}

	Ref<ArrayMesh> array_mesh;
	array_mesh.instantiate();
	std::vector<uint32_t> surface_slots;
	if (emitted.provenance.size() > 0 && emitted.indices.size() >= 3) {
		struct Bucket {
			PackedVector3Array verts;
			PackedVector3Array normals;
			PackedVector2Array uvs;
			PackedInt32Array indices;
			std::map<int32_t, int32_t> remap;
		};
		std::map<uint32_t, Bucket> buckets;
		std::vector<uint32_t> order;
		for (size_t t = 0; t < emitted.provenance.size(); t++) {
			const uint32_t slot = t < emitted.slots.size() ? emitted.slots[t] : 0;
			if (buckets.find(slot) == buckets.end()) {
				order.push_back(slot);
			}
			Bucket &bucket = buckets[slot];
			for (int k = 0; k < 3; k++) {
				const int32_t src = emitted.indices[t * 3 + size_t(k)];
				if (bucket.remap.find(src) == bucket.remap.end()) {
					bucket.remap[src] = int32_t(bucket.verts.size());
					bucket.verts.append(emitted.verts[size_t(src)]);
					bucket.normals.append(emitted.normals[size_t(src)]);
					bucket.uvs.append(emitted.uvs[size_t(src)]);
				}
				bucket.indices.append(bucket.remap[src]);
			}
		}
		for (uint32_t slot : order) {
			const Bucket &bucket = buckets[slot];
			Array arrays;
			arrays.resize(Mesh::ARRAY_MAX);
			arrays[Mesh::ARRAY_VERTEX] = bucket.verts;
			arrays[Mesh::ARRAY_NORMAL] = bucket.normals;
			arrays[Mesh::ARRAY_TEX_UV] = bucket.uvs;
			arrays[Mesh::ARRAY_INDEX] = bucket.indices;
			array_mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
			surface_slots.push_back(slot);
		}
	}
	mesh_instance->set_mesh(array_mesh);
	for (int i = 0; i < int(surface_slots.size()); i++) {
		const uint32_t slot = surface_slots[size_t(i)];
		Ref<Material> mat;
		if (slot < uint32_t(materials.size())) {
			mat = materials[slot];
		}
		if (mat.is_null()) {
			Ref<StandardMaterial3D> proto;
			proto.instantiate();
			proto->set_albedo(prototype_color);
			proto->set_roughness(0.7f);
			proto->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
			mat = proto;
		}
		mesh_instance->set_surface_override_material(i, mat);
	}

	if (collision_enabled && indices.size() >= 3) {
		PackedVector3Array soup;
		soup.resize(indices.size());
		for (int64_t i = 0; i < indices.size(); i++) {
			soup.set(i, verts[indices[i]]);
		}
		Ref<ConcavePolygonShape3D> shape;
		shape.instantiate();
		shape->set_faces(soup);
		collider->set_shape(shape);
	} else {
		collider->set_shape(Ref<Shape3D>());
	}
	collider->set_disabled(!collision_enabled);
	body->set_visible(collision_enabled);
}
