#include "slab_module.hpp"

#include "slab_socket.hpp"
#include "slab_solid.hpp"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void SlabModule::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_cell_size", "size"), &SlabModule::set_cell_size);
	ClassDB::bind_method(D_METHOD("get_cell_size"), &SlabModule::get_cell_size);
	ClassDB::bind_method(D_METHOD("set_module_id", "id"), &SlabModule::set_module_id);
	ClassDB::bind_method(D_METHOD("get_module_id"), &SlabModule::get_module_id);
	ClassDB::bind_method(D_METHOD("get_footprint"), &SlabModule::get_footprint);
	ClassDB::bind_method(D_METHOD("get_combined_aabb"), &SlabModule::get_combined_aabb);
	ClassDB::bind_method(D_METHOD("get_sockets"), &SlabModule::get_sockets);
	ClassDB::bind_method(D_METHOD("bake_mesh"), &SlabModule::bake_mesh);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cell_size", PROPERTY_HINT_RANGE, "0.25,16,0.25,suffix:m"), "set_cell_size", "get_cell_size");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "module_id"), "set_module_id", "get_module_id");
}

void SlabModule::set_cell_size(float p_size) {
	cell_size = MAX(p_size, 0.25f);
}

float SlabModule::get_cell_size() const {
	return cell_size;
}

void SlabModule::set_module_id(const String &p_id) {
	module_id = p_id;
}

String SlabModule::get_module_id() const {
	return module_id;
}

AABB SlabModule::get_combined_aabb() const {
	AABB combined;
	bool first = true;
	for (int i = 0; i < get_child_count(); i++) {
		SlabSolid *solid = Object::cast_to<SlabSolid>(get_child(i));
		if (solid == nullptr) {
			continue;
		}
		const AABB local = solid->get_local_aabb();
		const AABB world(solid->get_position() + local.position, local.size);
		if (first) {
			combined = world;
			first = false;
		} else {
			combined = combined.merge(world);
		}
	}
	return combined;
}

Vector3i SlabModule::get_footprint() const {
	const AABB aabb = get_combined_aabb();
	if (aabb.size == Vector3()) {
		return Vector3i();
	}
	const float cs = cell_size;
	return Vector3i(
			MAX(1, (int)Math::ceil(aabb.size.x / cs)),
			MAX(1, (int)Math::ceil(aabb.size.y / cs)),
			MAX(1, (int)Math::ceil(aabb.size.z / cs)));
}

Array SlabModule::get_sockets() const {
	Array out;
	for (int i = 0; i < get_child_count(); i++) {
		SlabSocket *socket = Object::cast_to<SlabSocket>(get_child(i));
		if (socket != nullptr) {
			out.push_back(socket->to_dictionary());
		}
	}
	return out;
}

Ref<ArrayMesh> SlabModule::bake_mesh() const {
	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedVector2Array uvs;
	PackedInt32Array indices;

	for (int i = 0; i < get_child_count(); i++) {
		SlabSolid *solid = Object::cast_to<SlabSolid>(get_child(i));
		if (solid == nullptr) {
			continue;
		}
		Ref<ArrayMesh> piece = solid->build_mesh();
		if (piece.is_null() || piece->get_surface_count() == 0) {
			continue;
		}
		Array arrays = piece->surface_get_arrays(0);
		PackedVector3Array pv = arrays[Mesh::ARRAY_VERTEX];
		PackedVector3Array pn = arrays[Mesh::ARRAY_NORMAL];
		PackedVector2Array pu = arrays[Mesh::ARRAY_TEX_UV];
		PackedInt32Array pi = arrays[Mesh::ARRAY_INDEX];
		const Transform3D xf = solid->get_transform();
		const int base = verts.size();
		for (int v = 0; v < pv.size(); v++) {
			verts.push_back(xf.xform(pv[v]));
			normals.push_back(xf.basis.xform(pn[v]).normalized());
			uvs.push_back(pu[v]);
		}
		for (int x = 0; x < pi.size(); x++) {
			indices.push_back(pi[x] + base);
		}
	}

	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	if (verts.is_empty()) {
		return mesh;
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = verts;
	arrays[Mesh::ARRAY_NORMAL] = normals;
	arrays[Mesh::ARRAY_TEX_UV] = uvs;
	arrays[Mesh::ARRAY_INDEX] = indices;
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	return mesh;
}
