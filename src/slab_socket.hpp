#pragma once

#include <godot_cpp/classes/node3d.hpp>

namespace godot {

class SlabSocket : public Node3D {
	GDCLASS(SlabSocket, Node3D);

public:
	enum Kind {
		KIND_DOOR = 0,
		KIND_OPEN = 1,
		KIND_WINDOW = 2,
	};

protected:
	static void _bind_methods();

public:
	void set_face(int p_face);
	int get_face() const;

	void set_offset(const Vector2 &p_offset);
	Vector2 get_offset() const;

	void set_opening(const Vector2 &p_opening);
	Vector2 get_opening() const;

	void set_kind(int p_kind);
	int get_kind() const;

	Dictionary to_dictionary() const;

private:
	int face = 4; // FACE_PZ — "south" in Godot -Z-forward maps oddly; +Z is fine as default
	Vector2 offset = Vector2(0.5, 0);
	Vector2 opening = Vector2(1, 2);
	int kind = KIND_DOOR;
};

} // namespace godot

VARIANT_ENUM_CAST(SlabSocket::Kind);
