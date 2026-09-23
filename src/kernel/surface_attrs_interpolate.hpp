#pragma once
#include "surface_attrs.hpp"
#include <cstddef>

namespace slab {
// Nonnegative barycentric weights are normalized. Optional channels interpolate
// over contributing corners carrying that channel; morph absence means zero.
// Skin influences merge by bone, keep the strongest eight, and renormalize.
bool interpolate_surface_attrs(const SurfaceAttrs *p_values, const double *p_weights,
		size_t p_count, SurfaceAttrs &r_out);
SurfaceAttrs lerp_surface_attrs(const SurfaceAttrs &p_a, const SurfaceAttrs &p_b, double p_t);
}
