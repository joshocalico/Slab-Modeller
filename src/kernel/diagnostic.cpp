#include "mesh.hpp"

#include <algorithm>
#include <unordered_set>

namespace slab {

void diagnostic_segments(const Mesh &p_mesh, const MeshFault &p_fault,
		std::vector<std::pair<IVec3, IVec3>> &r_out) {
	r_out.clear();
	if (p_fault.element == FaultElement::NONE) return;
	auto append_half_edge = [&](uint32_t p_slot) {
		if (!p_mesh._he_live(p_slot)) return;
		const HalfEdge &he = p_mesh.half_edges[p_slot];
		if (he.origin.i == INVALID_IDX || he.next.i == INVALID_IDX || !p_mesh._he_live(he.next.i)) return;
		const HalfEdge &next = p_mesh.half_edges[he.next.i];
		if (next.origin.i == INVALID_IDX || !p_mesh._vertex_live(he.origin.i) ||
				!p_mesh._vertex_live(next.origin.i)) return;
		r_out.push_back({ p_mesh.vertices[he.origin.i].pos, p_mesh.vertices[next.origin.i].pos });
	};
	const uint32_t slots[2] = { p_fault.slot, p_fault.related_slot };
	std::unordered_set<uint64_t> emitted;
	for (const uint32_t slot : slots) {
		if (slot == INVALID_IDX) continue;
		if (p_fault.element == FaultElement::HALF_EDGE) {
			append_half_edge(slot);
		} else if (p_fault.element == FaultElement::FACE) {
			if (!p_mesh._face_live(slot)) continue;
			uint32_t he = p_mesh.faces[slot].he.i;
			const uint32_t start = he;
			for (size_t guard = 0; guard <= p_mesh.half_edges.size(); ++guard) {
				if (!p_mesh._he_live(he)) break;
				append_half_edge(he);
				he = p_mesh.half_edges[he].next.i;
				if (he == start) break;
			}
		} else if (p_fault.element == FaultElement::VERTEX) {
			if (!p_mesh._vertex_live(slot)) continue;
			for (uint32_t he = 0; he < p_mesh.half_edges.size(); ++he) {
				if (!p_mesh._he_live(he)) continue;
				const HalfEdge &item = p_mesh.half_edges[he];
				if (item.origin.i == INVALID_IDX || item.origin.i != slot) continue;
				uint32_t canonical = he;
				if (item.twin.i != INVALID_IDX && p_mesh._he_live(item.twin.i)) canonical = std::min(he, item.twin.i);
				if (!emitted.insert(canonical).second) continue;
				append_half_edge(he);
			}
		}
	}
}

} // namespace slab
