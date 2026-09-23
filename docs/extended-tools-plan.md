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
| UV editing | Corner storage and IDs, direct transforms, pins, relax, stitch and alignment. `uv_edit_smoke` passes; `uv_element_modes_smoke` passes 15 cases. Native editor vertex drag, Undo/Redo and Pin exercised on demo face. | Pin-aware Pack/Unwrap and rebuild propagation now implemented and tested; broader native gestures and reload remain |
| Painting | Eraser, hardness, layer organisation and shared face/island masks implemented. `paint_extended_smoke` passes 69 checks; six existing paint suites pass. | Rendered paint editor smoke passes, including six channel saves, layer controls and 1280/1440 layout. Hands-on model strokes and visual channel review remain |
| Channels | Six channels bind and persist in focused tests. Height uses Godot parallax mapping. | Native material appearance and saved texture review, especially normal/height |
| Shading | Hard edges and smooth normals implemented. `shading_smoke` passes 20 checks, including emitted normals, Undo/Redo and scene reopen. | Imported authored-normal replacement and neutral morph shading pass focused tests. Native curved/bevelled visual acceptance remains |
| Construction history | Saved recipes, replay, parameter edits, bypass, reorder and arrays implemented. Engine passes 33 checks; panel passes 8. | Deformation recipe snapshots and generated bindings pass 12 checks through Undo/Redo and scene reopen. Native mesh-source → array → count edit → Undo/Redo → bypass passes. Reorder and manual checkpoint gestures remain to exercise |
| Interchange | Native per-corner attributes and version 6 persistence implemented. Promote deformation test passes 36 checks, including edit, Undo/Redo, scene reload and actual GLB/glTF round trips with current morph weights. | Boolean/bevel/cut attribute transfer and Import/Export dialogs implemented. Native GLB export/import and whole-hierarchy Undo/Redo pass after fixing editor-only importer node conversion. Broader native acceptance remains. |
| Closed sweeps | Kernel closed sweeps pass. `sweep_smoke` passes 22 checks; panel integration passes. | Native closed creation, Inspector-authored loop, path drag, Undo/Redo, invalid two-point recovery and scene reopen pass. Tilted handle plane and drag cancellation remain to exercise |

Latest combined kernel run: `scons target=template_debug -j8` and `bin/slab_kernel_test`, 190 tests, 6330 checks, zero failures. `chrome_smoke` passes 42 cases. This kernel run includes surface attribute storage/interpolation and pin-aware Pack/Unwrap. The first resumed full verifier passed all gates after fixing the stale UV drag assertion, paint clipping, editor-only GLTF import, and native sweep input routing. A final run is in progress after material-table remapping and morph-direction encoding fixes.

The native UV check used `demo/demo.tscn` in the extended-tools worktree. The agent selected a face, switched to UV Vert, dragged a corner, used Undo/Redo, pinned it through Tools, then undid both changes. The scene returned to its clean state and was not saved. This proves that interaction sequence only; it is not acceptance of the whole UV requirement.


Build the shared library and kernel test binary together. Run Godot processes serially, including headless checks, so one editor's startup cannot steal input from another editor acceptance run. Keep the original checkout unchanged; this work lives in the `slab-extended-tools` worktree.

## Attribute transfer policy

Retained Boolean, bevel and cut faces sample the original triangulated surface. New cap and bevel faces inherit nearest-surface colour, UV2, skin weights and position morph deltas; shading directions are recomputed. Pins survive at exact retained source corners, while new corners start unpinned. Authored Boolean inputs keep coplanar subdivisions to preserve material and UV boundaries, so they can produce more faces than plain graybox inputs.

Booleans on skinned solids refuse explicitly until binding remapping is implemented. A morph-bearing cutter must use the receiving solid's blend shape names. Construction checkpoints preserve deformation envelopes as well as geometry and materials; generated array copies rebase skeleton paths to their child-node location.

## Native acceptance, 24 September 2026

Using the actual Godot editor, exported demo Solid to `/tmp/slab-native-extended.glb`, imported it through Import Mesh, then verified that one Undo removed the hierarchy and Redo restored it. The first attempt exposed an editor-only importer-node conversion bug; the repaired workflow was repeated successfully.

Started construction history from the existing demo solid, added a linear array, changed Count from 3 to 4, verified Undo/Redo and bypass, then undid the full sequence to restore the demo.

Created and placed a closed Curve Sweep through the Slab panel. Separately added SlabSweep through Godot's Add Node dialog and authored its four rectangle points in the Inspector. Reducing the closed path to two points displayed a warning and retained the previous mesh; Undo restored the valid path. Saved this as `project/demo/extended_tools_acceptance.tscn` and reopened it. Direct path-handle dragging initially selected the SlabSolid underneath; the native-input routing fix was repeated successfully. Dragging changed point 2 from `(2, 0, 2)` to `(3, 0, 2)`; Undo and Redo restored each exact value. The saved fixture retains the original rectangular path.

## Known pre-existing handle lifetime gap

Whole-mesh rebuilds use `MeshEdit::assemble`, which replaces the mesh and restarts allocation generations at 1. A cached face or UV-corner handle can therefore become valid for a different rebuilt element. The connected-bevel, plane-cut and Boolean rebuild paths need generation invalidation or explicit selection remapping/clearing. The attribute-transfer implementation uses immutable source snapshots and does not depend on old handles referring to rebuilt elements, but editor selection lifetime remains a separate unresolved issue.

The ordinary Boolean adapter now merges material tables atomically and records them with geometry in Undo/Redo. Sixteen checks cover distinct material colours, shared resource identity, refusal, scene reload and prototype fallback snapshots. Construction uses the same native mapping contract.

Godot packs normal/tangent arrays as directions, so a zero relative morph normal cannot survive its storage format. Slab now emits normalized blend shapes with absolute target vertices and directions while keeping relative deltas in its kernel. The Promote/deformation suite passes 55 checks, including neutral normals/tangents and displacement weights above one; exchange passes 44 checks.

Documentation reference verification passes and the production Next.js build succeeds.
