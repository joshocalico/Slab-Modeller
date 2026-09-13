# Modeller UX and documentation acceptance

The goal is ProBuilder or UModeler quality in the editor workflow and manual. A green kernel suite alone does not establish that quality. This record keeps the outstanding work visible across iterations.

The next visual and interaction priorities are recorded in [Modeller design direction](modeller-design-direction.md): active workspace and selection state, material assignment order, and viewport space after leaving paint.

## Verified improvements

- Native Move, Rotate, and Scale pass the rendered-editor pivot and axis matrix, including exact Undo and Redo.
- Extrude, Inset, and Bevel each have one command entry, adjustable preview, Apply, and Cancel. Bevel retains its segment control and viewport handle.
- Invalid operation previews disable Apply. Other modelling commands wait until the preview is applied or cancelled.
- The room tutorial's 4 by 3 by 4 box, Inset 0.45, and Extrude -2.4 pass through the real editor panel. The result retains a 0.6 metre floor. Three undo actions restore the inset, original box, and pre-creation scene.
- The guide has editor orientation and runtime handoff pages. The panel reference uses current rendered screenshots. The website builds 31 routes.
- The verifier rejects GDScript errors even when Godot exits with code zero.

- Surface Paint has an explicit Assign control, a selection count, and brush controls only in Pixel mode. UV Escape cancellation, release, Undo, and Redo pass in a rendered editor using real GUI events.
- Pixel strokes bind the clicked face material and stay on that resource while dragging; crossing a different material breaks interpolation. The verifier includes the dedicated hit-scope regression suite.

- Creation now uses an explicit shape choice, parameters, and Create action. Hover leaves the fields unchanged. The rendered editor verifies a typed height of 5.25 m, repeated identical cylinders, one Undo per creation, and the full room tutorial through the new flow. Settings expand into available dock height; the chosen shape is highlighted.
- Mode buttons leave active tools even when choosing the current mode. Surface Paint accepts 1–4 to return to modelling, and Godot framing with F passes through real viewport keyboard input.
- The guide contents column has been checked in Chrome at 1151, 1440, and 800 px. The narrow desktop outline wraps without clipping; the smaller layout uses collapsible contents.

- Topology editing now keeps output selections: Subdivide selects all resulting faces, Merge selects the surviving face, Edge Connect selects its new edge, and Dissolve clears removed edges. Undo restores selection only for the same solid and mode. Rendered editor tests cover both edit chains and folded Merge recovery.
- Merge rebuilds a connected coplanar region from its outer boundary, including all four Subdivide quads and their internal centre. Kernel tests cover reordered regions, material preservation, and atomic folded/disconnected/holed refusals.
- Unsupported panel promises have been removed: Bridge duplicated Connect; Delete Face and Flip Normals had no verified useful closed-solid workflow. Their native APIs remain. The guide now describes supported topology operations and opening solids through Subtract.
- A copied addon was installed into a fresh project, used to create a 6 by 1 by 6 box through editor controls, saved, and reopened in another editor process. Dimensions, editability, and collision survived. The installation guide documents this verified macOS path and distinguishes unverified platforms.
- At 320 and 390 px, panel and keyboard references have no page-wide horizontal overflow; wide tables scroll locally, and navigation/contents disclosures work.

- Selection modes use a persistent gold highlight, including hover. Empty element selections explain the next viewport action. Materials & UV and Selection command groups start collapsed and remember their state across mode switches for the editor session. Materials & UV reveals its commands and selected-face settings together, with the palette first and UV axes side by side. The rendered panel test verifies keyboard selection while collapsed, keyboard disclosure activation, mode-switch persistence, and the existing room/preview/Undo workflows. The live Signal Foundry editor was also checked with the dock reduced to roughly 250 pixels high. The seven affected guide pages and three panel captures match the new controls.

- Signal Foundry was played from the saved START through all three cells, the four raised service landings, courtyard checkpoint, moving lift, two hazard jumps, and powered exit using computer-controlled normal inputs. A deliberate R verified the new editor-authored CatwalkCheckpoint; a deliberate hazard contact after completion preserved all three cells. This is route reachability and recovery evidence, not a no-reset speedrun or proof of the broader level-design target. See [Signal Foundry playtest](signal-foundry-playtest.md).
- A descending lift was reproduced pushing a player through a static floor. Lower carrier collision priority prevents the fall/reset in a regression at three lateral offsets over multiple cycles; restoring the old priority makes all three cases fail. The main verifier now includes player, interaction, and moving-platform gameplay checks.

## Remaining acceptance work

The PowerHouse now has an editor-authored ceiling, a shallow segmented vault, fitted half-cylinder end panels made with Plane Cut, timber cladding, and a shadow-casting Godot light. A normal-input running-game pass reached the enclosed room and verified ceiling coverage and grounded contact. Selecting that authored light exposed and resolved stale Slab selection ownership; the restarted editor and a regression gate now verify that authored children clear the modelling target. See [PowerHouse roof playtest](powerhouse-roof-playtest.md). The interior finish and broader level design remain incomplete.

Surface Paint now uses the persistent gold active style, separated from the element-mode strip. Native Cmd-Z after material assignment replaces the stale material report with the current object and face count. Rendered acceptance sends the actual editor Undo/Redo shortcuts and verifies both geometry state and feedback. Paint now places its scrolling inspector beside the canvas. The native roof pass verified first-entry layout, typed placement values, Unwrap with immediate island framing, and blank image sizing. The panel reference describes the new Mapping and Image sections; older captures still need a visual freshness audit.

The latest editor authoring pass verified separate Inset, Extrude, and Bevel session values and explicit Boolean target/second-solid controls with Swap. Rendered tests cover native selection order, actual swapped subtraction, tool-value transitions, and existing room/Undo workflows. The PowerHouse shading defect is resolved in both the lit editor and a running-game traversal. Shared whole-loop normals and valid dissolve boundaries pass the full verifier. Merge now explains an opening-specific refusal in the live editor. Surface Paint's loaded-material picker is readable, Quick Load discovers the sample materials, and material assignment marks the scene dirty and supports Undo/Redo. The live check restored the original scene after verification. See [Creation and boolean authoring playtest](creation-and-boolean-playtest.md).

The compact-dock audit distinguished the author-chosen splitter height from the minimum imposed by the active controls. In the native 1225 × 768 editor, Material/UV expanded the compact dock by 57 screen pixels; Pixel released that constraint. A manually enlarged dock kept its chosen height across the same transition. Modelling permits 240 logical pixels. A trial reduction to 200 hid the Materials & UV and Selection disclosures inside the scroller, so it was reverted. Godot's public bottom-panel API does not expose its splitter height. Preserve the author-chosen height without changing private editor ancestors. Paint now uses one minimum for Material/UV and Pixel. Native replay with empty selection and a loaded Teal Steel face keeps the divider at the same position across tool switches, including reopening in Pixel. Entering and leaving the workspace still require a broader layout decision.

| Area | Evidence still required |
| --- | --- |
| First use | Complete every core tutorial from a clean project; basic copied-addon creation/save/reopen is verified. Check save, reopen, collision, and player interaction. |
| Tool discovery | Exercise creation, selection, topology, surface editing, and recovery without relying on internal names or hidden state. Check material creation and assignment across several solids. |
| Tool consistency | Audit modal ownership, native gizmo overlap, typed input, focus, shortcuts, tool switching, cancellation, refusal recovery, and repeat operations across all tools. |
| Topology tools | Extend rendered acceptance to vertex Connect, Weld/Collapse, concave faces and larger multi-material regions. Verify the documented topology guide as a complete user workflow. |
| Materials and UVs | Author a scene with several materials, seams, unwrap, precise UV placement, pixel strokes, texture persistence, and reversible edits. Resolve overlapping legacy UV controls and the Surface Paint workspace. |
| Complex modelling | Build and play a substantial level in the editor with enclosed rooms, curved geometry, thin details, booleans, loops, bevels, platforms, and interaction. Diagnose z-fighting rather than hiding it. |
| Documentation | Replace outdated captures, cross-check every command contract, validate links, and inspect desktop and narrow-screen layouts. Verify small phone widths and every long reference page; the right-hand contents column is checked at 1151 and 1440 px. |
| Release readiness | Reopen saved examples, verify editable source and generated output, run all gates, and record limitations honestly. No claim of parity until the full workflow is verified. |

## Repeatable evidence

`scripts/slab-docs-verify` checks root-relative inline links and media attributes in MDX against local page routes and public files. The current manual passes with 28 MDX pages and 72 local references. A temporary broken-link and missing-image probe was rejected. This check does not establish heading-anchor validity, external-link availability, rendered layout, or screenshot accuracy.

`scripts/slab-install-verify` copies the addon to a disposable project and runs separate rendered creation/save and reopen passes. `project/tests/topology_editor_smoke.gd` exercises Subdivide/Merge and Connect/Dissolve through real panel clicks. Run it with `scripts/godot --editor --path project --script res://tests/topology_editor_smoke.gd`.

`scripts/slab-verify` covers the kernel, extension, focused GDScript suites, and editor initialization. `scripts/slab-native-gizmo-verify` covers real native transform input. `project/tests/panel_editor_smoke.gd` covers the primary operation buttons and the room tutorial in a dedicated rendered editor, without saving the fixture. `project/tests/paint_editor_smoke.gd` checks canvas gestures in a rendered editor without saving the lab scene. Run it with `scripts/godot --editor --path project --script res://tests/paint_editor_smoke.gd`. The commands and evidence formats are described in [Native gizmo verification](native-gizmo-verification.md).

The comparison concerns workflow quality, not identical internals. Slab's closed-solid validity rule remains a product constraint. ProBuilder's official [editing workflow](https://docs.unity3d.com/Packages/com.unity.probuilder@5.0/manual/workflow-edit.html) and [interface overview](https://docs.unity3d.com/Packages/com.unity.probuilder@5.0/manual/overview-ui.html) establish useful onboarding benchmarks.
