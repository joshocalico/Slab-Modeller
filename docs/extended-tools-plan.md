# Extended modelling tools

This work implements all seven requirements requested after the V1 release. A checked kernel test is not evidence of an editor workflow. Each feature needs saved-data coverage, Undo/Redo, refusal recovery, and a real editor pass before completion.

## Required outcomes

1. UV vertices, edges, and faces can be transformed directly. Pins, relaxation, stitching, and island alignment operate on the selected UV elements and persist after reload.
2. Pixel painting has an eraser, brush hardness, named/reorderable layers, and face/island masks. Canvas strokes, model strokes, and Fill Layer obey the same mask.
3. Metallic, tangent-space normal, and height channels join Albedo, Roughness, and Emission. Defaults, material bindings, layer state, saving, and Undo work for all six. Height painting uses Godot's height-map material behavior, not geometry displacement.
4. Authors can mark hard/soft edges and choose smooth shading. Generated normals respect those boundaries, including curved and bevelled geometry.
5. A saved construction stack supports revisiting bevels, arrays, and booleans, editing parameters, bypassing and reordering steps, and rebuilding atomically. The UI exposes invalid downstream references and preserves the last valid result.
6. Mesh interchange and Promote preserve supported material data plus secondary UVs, vertex colours, skinning, and blend shapes. The generated mesh and its skeleton/shape bindings must remain usable after conversion, editing, Undo, and reload. Unsupported deformation combinations must be reported rather than silently discarded.
7. Closed-path sweeps produce closed manifold solids with continuous frames, editable paths, and safe refusals for invalid geometry. Kernel, node, and editor behavior agree.

All seven remain incomplete until their complete workflow is verified. Do not replace these requirements with the subset covered by an intermediate checkpoint.

## Data ownership

`Mesh` owns geometric topology and per-corner surface attributes. A half-edge identifies one face corner, so it can distinguish the UVs and normals on either side of a seam without duplicating geometric vertices. Face projections remain the compact default; explicit corner UVs take over when the author edits individual elements. Pins are corner constraints. Hardness belongs to an undirected mesh edge and is symmetric across its twins.

`MeshEdit` owns atomic mutations and topology attribute propagation. Split operations interpolate corner data; face splits duplicate attributes at their new boundary corners. Serialization is versioned and reads older scenes with their existing defaults. The Godot adapter exposes effective corner UVs so rendering, canvas drawing, picking, painting, and export use the same mapping.

`SlabPaint` owns paint transactions. A frozen stroke mask is derived from effective UVs and applies to every input route. Channel descriptors own material bindings and neutral values. Layer operations retain resource/channel identity through history.

Construction history owns a base state and typed ordered operations, not the editor Undo stack. Rebuilding creates a candidate result and publishes it only when every operation succeeds. Godot Undo snapshots the construction state. Manual mesh edits need an explicit recorded boundary rather than an invisible destructive replacement of earlier history.

Imported deformation and auxiliary attributes must travel with the editable source. Their detailed topology-transfer contract is a separate implementation step; merely retaining the original imported mesh beside a changed solid does not satisfy preservation.

## Alternatives considered

Storing UV edits only in GDScript metadata would leave the kernel emitter, export, and topology mutations using different geometry. Per-corner attributes in the kernel avoid that split ownership. Replacing every projection immediately with explicit UVs would unnecessarily change existing scenes; keeping both representations permits migration on edit.

Saving only output snapshots for construction steps makes Undo easy but cannot recompute downstream operations when a parameter changes. A replayable operation stack is required. Snapshots may cache verified results, but they are not the source of truth for editable parameters.

## Verification ledger

| Requirement | Current evidence | Remaining acceptance |
| --- | --- | --- |
| UV editing | Corner storage and IDs, direct transforms, pins, relax, stitch and alignment. `uv_edit_smoke` passes; `uv_element_modes_smoke` passes 15 cases. Native editor vertex drag, Undo/Redo and Pin exercised on demo face. | Pack/Unwrap must use edited corners and respect pins; topology propagation; broader native gestures and reload |
| Painting | Eraser, hardness, layer organisation and shared face/island masks implemented. `paint_extended_smoke` passes 69 checks; six existing paint suites pass. | Rendered canvas and model strokes, mask/Fill interaction, real layer controls and save |
| Channels | Six channels bind and persist in focused tests. Height uses Godot parallax mapping. | Native material appearance and saved texture review, especially normal/height |
| Shading | Hard edges and smooth normals implemented. `shading_smoke` passes 20 checks, including emitted normals, Undo/Redo and scene reopen. | Native curved/bevelled model acceptance and imported authored-normal interaction |
| Construction history | Saved recipes, replay, parameter edits, bypass, reorder and arrays implemented. Engine passes 33 checks; panel passes 8. | Native complete authoring flow and interaction with manual mesh/UV edits |
| Interchange | Canonical attribute adapter and GLB/glTF source work underway. | Native versioned attribute storage, emission, deformation bindings, topology transfer and complete round trips. Promote's new adapter call is not usable until the native backend lands. |
| Closed sweeps | Kernel closed sweeps pass. `sweep_smoke` passes 22 checks; panel integration passes. | Native closed-path creation, path gizmo drag/Undo/cancel, invalid-edit recovery and scene reopen |

Latest combined kernel run: `scons target=template_debug -j8` and `bin/slab_kernel_test`, 172 tests, 5144 checks, zero failures. `chrome_smoke` passes 42 cases. These counts precede the new interchange backend and Pack/Unwrap changes; rerun after integration.

The native UV check used `demo/demo.tscn` in the extended-tools worktree. The agent selected a face, switched to UV Vert, dragged a corner, used Undo/Redo, pinned it through Tools, then undid both changes. The scene returned to its clean state and was not saved. This proves that interaction sequence only; it is not acceptance of the whole UV requirement.


Build the shared library and kernel test binary together. Run Godot processes serially, including headless checks, so one editor's startup cannot steal input from another editor acceptance run. Keep the original checkout unchanged; this work lives in the `slab-extended-tools` worktree.
