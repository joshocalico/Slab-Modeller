#include "slab_socket.hpp"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void SlabSocket::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_face", "face"), &SlabSocket::set_face);
	ClassDB::bind_method(D_METHOD("get_face"), &SlabSocket::get_face);
	ClassDB::bind_method(D_METHOD("set_offset", "offset"), &SlabSocket::set_offset);
	ClassDB::bind_method(D_METHOD("get_offset"), &SlabSocket::get_offset);
	ClassDB::bind_method(D_METHOD("set_opening", "opening"), &SlabSocket::set_opening);
	ClassDB::bind_method(D_METHOD("get_opening"), &SlabSocket::get_opening);
	ClassDB::bind_method(D_METHOD("set_kind", "kind"), &SlabSocket::set_kind);
	ClassDB::bind_method(D_METHOD("get_kind"), &SlabSocket::get_kind);
	ClassDB::bind_method(D_METHOD("to_dictionary"), &SlabSocket::to_dictionary);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "face", PROPERTY_HINT_ENUM, "PX,NX,PY,NY,PZ,NZ"), "set_face", "get_face");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "offset", PROPERTY_HINT_NONE, "suffix:m"), "set_offset", "get_offset");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "opening", PROPERTY_HINT_NONE, "suffix:m"), "set_opening", "get_opening");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "kind", PROPERTY_HINT_ENUM, "Door,Open,Window"), "set_kind", "get_kind");

	BIND_ENUM_CONSTANT(KIND_DOOR);
	BIND_ENUM_CONSTANT(KIND_OPEN);
	BIND_ENUM_CONSTANT(KIND_WINDOW);
}

void SlabSocket::set_face(int p_face) {
	face = CLAMP(p_face, 0, 5);
}

int SlabSocket::get_face() const {
	return face;
}

void SlabSocket::set_offset(const Vector2 &p_offset) {
	offset = p_offset;
}

Vector2 SlabSocket::get_offset() const {
	return offset;
}

void SlabSocket::set_opening(const Vector2 &p_opening) {
	opening = Vector2(MAX(p_opening.x, 0.05f), MAX(p_opening.y, 0.05f));
}

Vector2 SlabSocket::get_opening() const {
	return opening;
}

void SlabSocket::set_kind(int p_kind) {
	kind = p_kind;
}

int SlabSocket::get_kind() const {
	return kind;
}

Dictionary SlabSocket::to_dictionary() const {
	Dictionary d;
	d["face"] = face;
	d["offset"] = offset;
	d["opening"] = opening;
	d["kind"] = kind;
	d["origin"] = get_global_position();
	return d;
}
