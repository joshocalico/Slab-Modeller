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

All seven requirements are implemented and verified by focused regressions, the full verifier, and native editor acceptance. The ledger distinguishes completed evidence from additional manual exploration; these extra checks are not missing implementations. Supported limits are recorded below.

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

| Requirement | Implementation and verification | Further manual exploration |
| --- | --- | --- |
| UV editing | Direct corner transforms, vertex/edge/face selection, pins, relax, stitch and alignment. Pin-aware Pack/Unwrap and rebuild propagation pass focused tests. Native vertex drag, Undo/Redo and Pin pass. | More combinations of gestures and reopened scenes. |
| Painting | Eraser, hardness, named/reorderable layers, shared face/island masks and masked Fill. Extended smoke passes 69 checks. Native soft/hard strokes, erasing, model painting and Undo pass. Rendered controls and 1280/1440 layout pass. | Longer painting sessions across complex models. |
| Channels | Six channels bind, persist and undo. Rendered Save Paint writes exact displayed PNG pixels to six independent paths. Native directional normal painting passes. | Broader material appearance review, especially height/parallax under different lighting. |
| Shading | Hard/soft edges, smooth/flat faces, imported-normal replacement and neutral morph shading pass focused tests and scene reload. Native four-segment bevel, smooth shading and hard/soft appearance pass with Undo. | Additional curved models and lighting setups. |
| Construction history | Saved recipes, replay, parameter edits, bypass, reorder and arrays: 33 engine checks, 8 panel checks. Deformation recipes: 12 checks through Undo/Redo and scene reopen. Native mesh source → array → count edit → Undo/Redo → bypass passes. | More native reorder and manual-checkpoint combinations. |
| Interchange | UV2, colours, skinning, morphs, materials and version 6 persistence. Promote deformation passes 55 checks; exchange passes 44. Boolean/bevel/cut transfer and material tables have dedicated regressions. Native GLB export/import and whole-hierarchy Undo/Redo pass. | More third-party asset fixtures. |
| Closed sweeps | Closed manifold kernel sweeps, continuous frames and refusal coverage. Node smoke passes 22 checks. Native closed creation, Inspector path authoring, handle drag, Undo/Redo, invalid two-point recovery and scene reopen pass. | Tilted handle planes and live drag cancellation. |

Latest combined kernel run: `scons target=template_debug -j8` and `bin/slab_kernel_test`, 190 tests, 6330 checks, zero failures. `chrome_smoke` passes 42 cases. This kernel run includes surface attribute storage/interpolation and pin-aware Pack/Unwrap. The first resumed full verifier passed all gates after fixing the stale UV drag assertion, paint clipping, editor-only GLTF import, and native sweep input routing. The final full verifier also passed all gates after material-table remapping and morph-direction encoding fixes (`/tmp/slab-extended-final-verify.log`).

The native UV check used `demo/demo.tscn` in the extended-tools worktree. The agent selected a face, switched to UV Vert, dragged a corner, used Undo/Redo, pinned it through Tools, then undid both changes. The scene returned to its clean state and was not saved. This proves that interaction sequence only; it is not acceptance of the whole UV requirement.


Build the shared library and kernel test binary together. Run Godot processes serially, including headless checks, so one editor's startup cannot steal input from another editor acceptance run. Keep the original checkout unchanged; this work lives in the `slab-extended-tools` worktree.

## Attribute transfer policy

Retained Boolean, bevel and cut faces sample the original triangulated surface. New cap and bevel faces inherit nearest-surface colour, UV2, skin weights and position morph deltas; shading directions are recomputed. Pins survive at exact retained source corners, while new corners start unpinned. Authored Boolean inputs keep coplanar subdivisions to preserve material and UV boundaries, so they can produce more faces than plain graybox inputs.

Booleans on skinned solids refuse explicitly until binding remapping is implemented. A morph-bearing cutter must use the receiving solid's blend shape names. Construction checkpoints preserve deformation envelopes as well as geometry and materials; generated array copies rebase skeleton paths to their child-node location.

## Native acceptance, 24 September 2026

Using the actual Godot editor, exported demo Solid to `/tmp/slab-native-extended.glb`, imported it through Import Mesh, then verified that one Undo removed the hierarchy and Redo restored it. The first attempt exposed an editor-only importer-node conversion bug; the repaired workflow was repeated successfully.

Started construction history from the existing demo solid, added a linear array, changed Count from 3 to 4, verified Undo/Redo and bypass, then undid the full sequence to restore the demo.

Created and placed a closed Curve Sweep through the Slab panel. Separately added SlabSweep through Godot's Add Node dialog and authored its four rectangle points in the Inspector. Reducing the closed path to two points displayed a warning and retained the previous mesh; Undo restored the valid path. Saved this as `project/demo/extended_tools_acceptance.tscn` and reopened it. Direct path-handle dragging initially selected the SlabSolid underneath; the native-input routing fix was repeated successfully. Dragging changed point 2 from `(2, 0, 2)` to `(3, 0, 2)`; Undo and Redo restored each exact value. The saved fixture retains the original rectangular path.

## Rebuilt selection safety

Whole-mesh rebuilds use `MeshEdit::assemble`, which replaces the mesh and restarts allocation generations at 1. A cached face or UV-corner handle can therefore become valid for a different rebuilt element. The editor now clears face/edge IDs, cached UV IDs, hover and face-isolation masks when Boolean, bevel or plane cut rebuilds geometry. Undo restores original IDs only against the same solid and selection mode; Redo clears them again. Thirteen focused regressions cover these boundaries, and the native face-bevel apply/Undo/Redo sequence passes. External kernel callers must still discard handles across whole-mesh assembly.

The ordinary Boolean adapter now merges material tables atomically and records them with geometry in Undo/Redo. Sixteen checks cover distinct material colours, shared resource identity, refusal, scene reload and prototype fallback snapshots. Construction uses the same native mapping contract.

Godot packs normal/tangent arrays as directions, so a zero relative morph normal cannot survive its storage format. Slab now emits normalized blend shapes with absolute target vertices and directions while keeping relative deltas in its kernel. The Promote/deformation suite passes 55 checks, including neutral normals/tangents and displacement weights above one; exchange passes 44 checks.

Documentation reference verification passes and the production Next.js build succeeds.

The final native paint pass exercised soft and hard strokes, erasing and Undo. It exposed a material-slot collision: Make Unique on a default face also changed unselected faces. Make Unique and material assignment now reserve a shared null fallback for unresolved slots before appending a material. Focused tests cover slot zero, sparse slot 65535, emitted prototype-colour faces, bounded tables and exact Undo. The native recheck confirmed only the selected front face changed while the top remained orange, and Undo returned the scene to its clean state.

After the material-slot fix, `paint_smoke`, `paint_material_scope_smoke` and the rendered `paint_editor_smoke` pass. The latter saves and compares exact PNG pixels for all six channels. The final native pass also painted directly onto the model and created a directional normal-map stroke through the colour picker. A four-segment face bevel was shaded smooth, marked hard, then softened; the viewport showed the expected difference and four Undo actions restored the clean saved fixture. Selection safety follow-up tests (`rebuild_selection_smoke`, `bevel_smoke`, `plane_cut_smoke`, `boolean_materials_smoke`) all pass.

A final Paint issue was traced to deferred subgizmo selection refresh: Make Unique emitted topology changes that recreated element transform handles despite the native edit lock. `_sync_subgizmo` now clears element handles while UV/Paint is active. The rendered regression inspects actual selected gizmos after entry and Make Unique, rather than relying only on lock metadata.

The final rendered Paint regression passes with zero failures after the subgizmo fix. Verification remains layered: the full verifier passed before the final material/selection/gizmo fixes, and the affected focused and rendered suites passed after those fixes.

The final native gizmo recheck passed: Make Unique changed only the selected face, kept both native and Slab transform handles hidden, and Undo restored the clean scene. Returning to Face mode restored modelling handles. The editor is left open on the saved acceptance fixture.
