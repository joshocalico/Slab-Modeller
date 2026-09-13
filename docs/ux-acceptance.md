# Modeller UX and documentation acceptance

The goal is ProBuilder or UModeler quality in the editor workflow and manual. A green kernel suite alone does not establish that quality. This record keeps the outstanding work visible across iterations.

## Verified improvements

- Native Move, Rotate, and Scale pass the rendered-editor pivot and axis matrix, including exact Undo and Redo.
- Extrude, Inset, and Bevel each have one command entry, adjustable preview, Apply, and Cancel. Bevel retains its segment control and viewport handle.
- Invalid operation previews disable Apply. Other modelling commands wait until the preview is applied or cancelled.
- The room tutorial's 4 by 3 by 4 box, Inset 0.45, and Extrude -2.4 pass through the real editor panel. The result retains a 0.6 metre floor. Three undo actions restore the inset, original box, and pre-creation scene.
- The guide has editor orientation and runtime handoff pages. The panel reference uses current rendered screenshots. The website builds 31 routes.
- The verifier rejects GDScript errors even when Godot exits with code zero.

- Surface Paint has explicit Assign and Add Material controls, a selection count, and brush controls only in Pixel mode. UV Escape cancellation, release, Undo, and Redo pass in a rendered editor using real GUI events.
- Pixel strokes bind the clicked face material and stay on that resource while dragging; crossing a different material breaks interpolation. The verifier includes the dedicated hit-scope regression suite.

## Remaining acceptance work

| Area | Evidence still required |
| --- | --- |
| First use | Follow installation and every core tutorial from a clean project. Check save, reopen, collision, and player interaction. |
| Tool discovery | Exercise creation, selection, topology, surface editing, and recovery without relying on internal names or hidden state. Check material creation and assignment across several solids. |
| Tool consistency | Audit modal ownership, native gizmo overlap, typed input, focus, shortcuts, tool switching, cancellation, refusal recovery, and repeat operations across all tools. |
| Topology tools | Document and test selection constraints, resulting selection, undo units, and refusals for Connect, Bridge, Dissolve, Delete, Flip Normals, Merge, and Subdivide. |
| Materials and UVs | Author a scene with several materials, seams, unwrap, precise UV placement, pixel strokes, texture persistence, and reversible edits. Resolve overlapping legacy UV controls and the Surface Paint workspace. |
| Complex modelling | Build and play a substantial level in the editor with enclosed rooms, curved geometry, thin details, booleans, loops, bevels, platforms, and interaction. Diagnose z-fighting rather than hiding it. |
| Documentation | Replace outdated captures, cross-check every command contract, validate links, and inspect desktop and narrow-screen layouts. The right-hand contents column needs a responsive-layout check. |
| Release readiness | Reopen saved examples, verify editable source and generated output, run all gates, and record limitations honestly. No claim of parity until the full workflow is verified. |

## Repeatable evidence

`scripts/slab-verify` covers the kernel, extension, focused GDScript suites, and editor initialization. `scripts/slab-native-gizmo-verify` covers real native transform input. `project/tests/panel_editor_smoke.gd` covers the primary operation buttons and the room tutorial in a dedicated rendered editor, without saving the fixture. `project/tests/paint_editor_smoke.gd` checks canvas gestures in a rendered editor without saving the lab scene. Run it with `scripts/godot --editor --path project --script res://tests/paint_editor_smoke.gd`. The commands and evidence formats are described in [Native gizmo verification](native-gizmo-verification.md).

The comparison concerns workflow quality, not identical internals. Slab's closed-solid validity rule remains a product constraint. ProBuilder's official [editing workflow](https://docs.unity3d.com/Packages/com.unity.probuilder@5.0/manual/workflow-edit.html) and [interface overview](https://docs.unity3d.com/Packages/com.unity.probuilder@5.0/manual/overview-ui.html) establish useful onboarding benchmarks.
