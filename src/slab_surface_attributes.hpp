#pragma once
#include "kernel/surface_attrs.hpp"
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
namespace godot {
bool decode_slab_surface_attributes(const Dictionary &p_input, int64_t p_count,
		std::vector<slab::SurfaceAttrs> &r_attributes, String &r_error);
}
