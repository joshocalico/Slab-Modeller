# Connected bevel requirements

The maintenance-bay roof exposed two separate failures. The editor could not place a handle for all 12 edges because their summed adjacent normals cancelled. Commit `4e90437` fixes that handle case. The kernel also refuses the four connected top edges at width 0.03 and three segments. That geometry limitation remains under implementation.

The caller continues to supply edge handles, width, and segment count to `ops::bevel`. The operation owns shared-corner construction. The editor must not split a connected selection into several independent edits to conceal a kernel limitation.

## Construction under evaluation

The current algorithm edits edges sequentially. Its existing special case truncates one corner when exactly three selected edges meet there. The proposed extension plans all affected corners from the original mesh before modifying any edge. A single rebuild creates the corner geometry, after which edge bands are generated.

Separating endpoints does not by itself prove independence. Two bands may still share a corner face or rail. Selection permutations and profile measurements must establish whether this preparation removes the mutation-order dependency. If it does not, construct the affected faces, corner patches, and edge bands together from the source mesh.

## Acceptance evidence

- A four-edge perimeter on a 4.4 × 0.2 × 4.4 roof commits at width 0.03 with one and three segments.
- Every selection permutation produces the same oriented face geometry and material/UV assignments, independent of handle allocation order.
- The committed result passes the existing embedding validation, has positive volume, and retains the topology of the source solid.
- The intended bevel width remains consistent along each band. Corner preparation must not silently reduce the width through short-rail clamps.
- Distinct source-face attributes survive on retained faces. New faces inherit a deterministic adjacent source assignment rather than an unrelated material or default UV mapping.
- Refused widths or unsupported vertex configurations cannot leave a partially truncated result that commits successfully.
- Existing single-edge, disjoint-edge, and three-edge corner cases remain valid.
- Native Godot replay previews the roof perimeter, applies it in one Undo action, restores it with Undo, and retains the intended material after Save and reload.

Complete-box bevels, mixed corner degrees, and higher-valence vertices remain part of the broader modelling work. Passing the roof case does not establish support for those configurations.
