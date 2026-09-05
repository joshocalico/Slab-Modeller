#pragma once

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/node3d.hpp>

namespace godot {

class SlabModule : public Node3D {
	GDCLASS(SlabModule, Node3D);

protected:
	static void _bind_methods();

public:
	void set_cell_size(float p_size);
	float get_cell_size() const;

	void set_module_id(const String &p_id);
	String get_module_id() const;

	Vector3i get_footprint() const;
	AABB get_combined_aabb() const;
	Array get_sockets() const;
	Ref<ArrayMesh> bake_mesh() const;

private:
	float cell_size = 2.0f;
	String module_id = "module";
};

} // namespace godot
