#include "surface_attrs_interpolate.hpp"
#include <algorithm>
#include <cmath>
#include <map>
#include <utility>

namespace slab {
bool interpolate_surface_attrs(const SurfaceAttrs *p_values, const double *p_weights,
		size_t p_count, SurfaceAttrs &r_out) {
	if (!p_values || !p_weights || p_count == 0) return false;
	double total = 0.0;
	size_t morph_count = 0;
	for (size_t i = 0; i < p_count; ++i) {
		if (!std::isfinite(p_weights[i]) || p_weights[i] < 0.0) return false;
		total += p_weights[i];
		if (p_weights[i] > 0.0) morph_count = std::max(morph_count, p_values[i].morphs.size());
	}
	if (!std::isfinite(total) || total <= 0.0) return false;
	SurfaceAttrs out;
	out.color = godot::Color(0, 0, 0, 0);
	out.tangent = {};
	out.morphs.resize(morph_count);
	double channel_weight[5] = {};
	std::map<int32_t, double> influences;
	for (size_t i = 0; i < p_count; ++i) {
		const double w = p_weights[i] / total;
		if (w == 0.0) continue;
		const auto &a = p_values[i];
		out.flags |= a.flags;
		for (int channel = 0; channel < 5; ++channel) {
			if (a.flags & (1 << channel)) channel_weight[channel] += w;
		}
		if (a.flags & SurfaceAttrs::UV2) out.uv2 += a.uv2 * w;
		if (a.flags & SurfaceAttrs::COLOR) out.color += a.color * w;
		if (a.flags & SurfaceAttrs::NORMAL) out.normal += a.normal * w;
		if (a.flags & SurfaceAttrs::TANGENT) {
			for (int k = 0; k < 4; ++k) out.tangent[k] += a.tangent[k] * w;
		}
		if (a.flags & SurfaceAttrs::SKIN) {
			for (int k = 0; k < 8; ++k) {
				if (a.bones[k] < 0 || !std::isfinite(a.weights[k]) || a.weights[k] < 0.0f) return false;
				influences[a.bones[k]] += a.weights[k] * w;
			}
		}
		for (size_t k = 0; k < a.morphs.size(); ++k) {
			out.morphs[k].position += a.morphs[k].position * w;
			out.morphs[k].normal += a.morphs[k].normal * w;
			out.morphs[k].tangent += a.morphs[k].tangent * w;
			out.morphs[k].tangent_w += a.morphs[k].tangent_w * w;
		}
	}
	if (channel_weight[0] > 0.0) out.uv2 /= channel_weight[0];
	if (channel_weight[1] > 0.0) out.color /= channel_weight[1];
	else out.color = godot::Color(1, 1, 1, 1);
	if (channel_weight[2] > 0.0) out.normal.normalize();
	if (channel_weight[3] > 0.0) {
		godot::Vector3 tangent(out.tangent[0], out.tangent[1], out.tangent[2]);
		tangent.normalize();
		out.tangent = {float(tangent.x), float(tangent.y), float(tangent.z), out.tangent[3] < 0 ? -1.0f : 1.0f};
	} else out.tangent = {1, 0, 0, 1};
	if (out.flags & SurfaceAttrs::SKIN) {
		std::vector<std::pair<int32_t, double>> sorted;
		for (const auto &entry : influences) if (entry.second > 0.0) sorted.push_back(entry);
		std::sort(sorted.begin(), sorted.end(), [](const auto &a, const auto &b) {
			return a.second == b.second ? a.first < b.first : a.second > b.second;
		});
		if (sorted.size() > 8) sorted.resize(8);
		double sum = 0.0;
		for (const auto &entry : sorted) sum += entry.second;
		if (sum <= 0.0) return false;
		for (size_t k = 0; k < sorted.size(); ++k) {
			out.bones[k] = sorted[k].first;
			out.weights[k] = sorted[k].second / sum;
		}
	}
	r_out = std::move(out);
	return true;
}

SurfaceAttrs lerp_surface_attrs(const SurfaceAttrs &p_a, const SurfaceAttrs &p_b, double p_t) {
	SurfaceAttrs result;
	const SurfaceAttrs values[] = {p_a, p_b};
	const double weights[] = {1.0 - p_t, p_t};
	interpolate_surface_attrs(values, weights, 2, result);
	return result;
}
}
