# Modeller expansion

Goal: build, test, and document all eight requested modelling workflows. A kernel implementation alone is not completion. Each needs editor interaction, undo/cancel behavior, regression coverage, documentation, and live Godot validation.

| Workflow | Implementation | Tests | Live editor | Documentation |
| --- | --- | --- | --- | --- |
| Interactive loop cut/slide: preview, multiple cuts, exact placement | Implemented | Kernel and editor smoke pass | Exact placement, four cuts, sliding, cancellation and undo exercised | Lint and production build pass |
| Vertex snapping and face alignment | Controller and shared editor wiring implemented; source anchor is an actual vertex | Controller/integration and UI smokes pass | Pending | Lint and production build pass |
| Plane cutting with closed caps | Implemented; precision field corrected | Kernel and 12 editor smoke assertions pass | Axis and oblique cuts through a subdivided solid, undo/redo and cancel exercised; latest UI corrections need reload | Lint and production build pass |
| Connected-region extrusion and inset | Kernel and editor integration implemented; cap selection survives rebuild and undo | Six kernel tests and editor smoke checks pass | Four-face top selected, inset 0.25, extruded -1.5 into room; saved volume 4.625; undo to 8 and redo; cap selection retained | Lint and production build pass |
| Segmented bevel with live preview | Kernel includes shared corner; preview controller, binding and shared UI implemented | Joint-corner regression, preview/cancel/undo smoke and UI checks pass | Live 0.2 m / four-segment preview and Apply on Box4; saved ten faces; live undo/cancel still pending | Lint and production build pass |
| Linear/radial duplication with exact spacing | Ghost source and real editor undo API fixed; two-choice mode controls being improved | Controller/integration and UI checks pass; test undo API now matches EditorUndoRedoManager | Linear preview, exact (2.75,0.5,0) spacing, Apply, single Undo, Redo and cancel exercised; saved Box4/Box5 transforms match; radial still pending | Lint and production build pass |
| Refused-edit explanations and geometry highlights | Typed face/edge/vertex scratch locations and early-failure replacement implemented | 13 diagnostic smoke checks and kernel coverage pass | Refused inward plate extrusion exercised; saved geometry unchanged; broader highlight inspection pending | Lint and production build pass |
| UV seams, unwrap, consistent texel density | v3 storage, overlap detection, explicit automatic cuts, bindings, painter mapping and shared UI implemented | Six kernel cases plus 17 painter/binding smoke checks pass | Pending | Lint and production build pass |

Preserve the closed, consistently oriented, positive-volume embedded manifold gate. Invalid previews must not overwrite the saved solid. Confirmation is one undo action; cancel restores the exact original state. Keep the documentation's existing terse voice and one mode per page.

Verification: rebuild both shared library and kernel test with `scons target=template_debug -j8`, run `bin/slab_kernel_test`, then `scripts/slab-verify` and the matching editor smokes. Use a real Godot editor pass for every UI workflow, including undo/redo, cancellation, precise values, and a nontrivial solid.

Keep existing unrelated/untracked demo artifacts and the excluded website pnpm files and docs_capture UID out of checkpoints. No remote, push, or PR.

Latest combined kernel report: 129 tests, 2,706 checks, zero failures, including joint-corner bevel, UV unfolding and typed diagnostics. Full scripts/slab-verify reports all gates green; website lint/build passes all 29 routes. Remaining live interaction checks are incomplete. Implementation checkpoint prepared; this is not the completion audit.
