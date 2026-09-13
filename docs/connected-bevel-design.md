# Connected bevel requirements

The maintenance-bay roof exposed two separate failures. The editor could not place a handle for all 12 edges because their summed adjacent normals cancelled. Commit `4e90437` fixes that handle case. The kernel also refused the four connected top edges at width 0.03 and three segments. The new connected-edge path addresses that geometry failure.

The caller continues to supply edge handles, width, and segment count to `ops::bevel`. The operation owns shared-corner construction. The editor must not split a connected selection into several independent edits to conceal a kernel limitation.

## Construction

The connected-edge path plans every selected edge from the original mesh. At a vertex with three incident edges and two selected edges, it intersects their offset lines on the shared face. That intersection and the cut on the third edge define one rounded profile. Both incident bevel bands use that profile.

Retained faces and bevel bands are assembled together in a temporary mesh. Retained faces preserve their attributes; bands inherit attributes from a deterministic adjacent source face. Unexpected assembled faces cause a refusal. Validation must succeed before the candidate replaces the caller's mesh. Open-chain endpoints insert their profile into the third face.

Single-edge and disjoint-edge bevels retain the existing path. Exactly three selected edges meeting at one corner retain their corner-patch path. General selections with three selected edges at a vertex, including all 12 box edges, remain unsupported.

Pre-truncating corners before sequential edge edits was rejected. The shortened rails clamped the requested width and did not remove the order dependency.

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

UV seam marks survive on geometrically unchanged edges. Shortened or replaced edges do not currently inherit their original seam marks.

## Verified roof replay

The native Godot pass selected the roof top face, used Select Boundary to select four edges, and applied width 0.03 with three segments. Save and read-only reload confirmed 18 teal-steel faces, volume 3.87238744273782, unchanged bounds and transform, and the original child light. One native Undo and Save restored the complete scene byte-for-byte. Redo and Save restored the bevel.
