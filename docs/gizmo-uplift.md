# Selection and gizmo uplift

## Accepted checkpoint, 13 September 2026

The native transform acceptance blocker is resolved. `scripts/slab-native-gizmo-verify` passes nine rendered-editor cases: Move, Rotate, and Scale across selection/world, active/local, and custom/face configurations. Fixtures include rotated, nonuniformly scaled solids. Every case changes mesh data, preserves the node transform, and passes exact Undo and Redo restoration. Gesture endpoints stay inside the viewport. Rendered Move, Rotate, and Scale captures were inspected.

The new Escape test found and pinned a product bug: Slab consumed Escape during a native drag. Slab now passes that event to Godot and preserves selection through release. Native cancellation restores the original mesh without creating an undo action. The viewport suite passes 41 cases, and `scripts/slab-verify` passes all gates after the fix. The lab scene remains unchanged.

The runner sends held-button mouse events through Godot's native viewport input handler. It does not invoke Slab transform callbacks directly. [Native gizmo verification](native-gizmo-verification.md) describes the command and evidence format. Final run logs: `/tmp/slab-native-matrix-final.log` and `/tmp/slab-native-fix-verify.log`.

## Implementation and earlier acceptance record

Implement, test, document and exercise all eight workflows in the real Godot editor. Preserve the existing closed-solid validation gate and reversible previews.

| Requirement | Current work | Completion evidence required |
| --- | --- | --- |
| Hover exactly predicts click | Shared viewport hover/click candidate path implemented; X-ray cycling regression passes | Vertex, edge and concave-face hover/click agreement |
| Distinct visual states | White hover, amber selection, cyan preview, red refusal; lighter fill started | Live overlapping states and legibility |
| Less obstruction | Smaller vertex marks, lighter face fill and concave triangulation implemented; fill regression passes | Live detailed room and small feature inspection |
| Selection, active and custom pivots | Frame helper, atomic transform binding and gizmo integration implemented; live custom pivot (2,0,0) moves gizmo without changing geometry | UI controls, move/rotate/scale around each pivot, undo |
| World, local and face axes | Frame helper, atomic transform binding and gizmo integration implemented; live custom pivot (2,0,0) moves gizmo without changing geometry | Rotated and scaled objects, stable face frame |
| Generous picking and cycling | Tab/Shift-Tab cycling integrated with deterministic ordered candidates | Near-edge hits, overlapping candidates and deterministic cycling |
| Visible-only and X-ray | Visible-only/X-ray control connected to cross-solid occlusion-aware picking | Explicit UI and occluded geometry selection |
| Extrude, inset and bevel handles | Helper and shared modal controls integrated; exact preview, Apply, cap selection and Cancel regression passes; operation shapes and numeric overlay labels integrated; first live extrusion label verified; camera-navigation routing corrected and awaits reload | Drag handles, displayed values, exact entry, cancel/undo |

No requirement is complete on the strength of a helper alone. Shared viewport, selection, panel and gizmo integration remain required. A final pass must cover editor interaction, focused regression tests, full verification, and user-facing documentation before committing completion.

Live editor pass: opened modeller_lab in the rebuilt extension. Pivot controls appear in a compact row. Selecting Custom moves the gizmo to world origin; entering X=2 moves it to (2,0,0) while the selected room face remains fixed and the scene stays unmodified. Menu keyboard navigation works; direct CUA popup clicks were unreliable. Numeric entry verified after focus settled.

Live extrusion handle: changed camera to Front through Godot view menu while preview stayed active; dragged arrow upward from 0.5 to 1.078 m and label/field updated together. Entered exact 0.375 m, Apply, saved: Box2 ten faces, volume 4.5, top 1.125 (original six faces, volume 3, top 0.75). One editor Undo restores original data; saved again.

Live inset: drag reduced 0.5 to 0.251 m; exact 0.25 Apply saved Box2 with ten faces and unchanged volume 3/top 0.75, then one Undo. Live bevel: drag reduced 0.5 to 0.241 m; exact 0.2 Apply saved seven faces, volume 2.95992183685303, then one Undo. Visual acceptance remains blocked on opaque-looking face fill and poorly distinguishable operation lines; material/render-order audit underway. This is actionable implementation work, not an external blocker.

Live follow-up (13 Sep): replaced engine-generated overlay material variants with one explicit material per fill/operation state. Selected Box2 now retains its base grey surface under the tint; the inset result wire is visible. Added foreground screen-space handle outlines, but native transform-gizmo overlap still needs visual refinement. Inset drag 0.500 → 0.975 updated field and label together, then Cancel left the scene unchanged.

Live occlusion/cycling: Top view with X-ray enabled showed Candidate 2 / 2 after Tab. Clicking that candidate and switching to Front put the selected face pivot on Box2's underside (y=0). Returning to Top, turning X-ray off, and clicking the same point selected the top face; Front confirmed pivot y=0.75. Tab no longer offered the hidden underside. This verifies actual click/candidate agreement and the visible-only filter, beyond the automated regression.

Full scripts/slab-verify passed after the explicit overlay materials and foreground drawing changes (/tmp/slab-gizmo-current-verify.log). Goal remains open for handle legibility, remaining live transform/picking cases, and final documentation audit.

Live transform routing audit: native X-axis drag originally cleared the face selection. Deferring plain selection changes until mouse release now preserves it, including when another candidate lies under the handle (40 viewport regression cases pass). However, live combined-gizmo and explicit Move-tool drags still produce no mesh change; native transform dispatch is under investigation. This is an unresolved functional issue, not accepted on test coverage alone.

Refusal check: entering Extrude -3.000 on Box2 produces the crossing-face explanation and a red diagnostic outline below the floor in Front view, while the original solid stays unchanged. Corrected the negative extrusion handle's direction so its arrow points inward rather than outward; helper regression passes.

Operation documentation added to relevant how-to/reference pages; website lint and 29-page production build passed.

Live near-silhouette picking: in Top view, clicks about 5 screen pixels beyond Box2's lower-left corner selected its vertex, and about 6 pixels outside the left boundary selected the edge. The panel and gizmo anchored to the corresponding element. Bevel on that edge now shows a distinguishable purple arc and endpoint; dragging the endpoint changed 0.500 → 0.790 with matching numeric label/field, then Cancel restored the idle state without modifying the scene.

Live rotated/nonuniform axes check: temporarily set Box4 rotation Y=30 degrees and scale X=1.5 in the Inspector. Switching World to Object local changed the menu but not the displayed native gizmo axes. The two Inspector edits were undone and the original lab saved; no scene diff. Native orientation synchronization remains required. The bounded native press PASS change also still yields no geometry motion in the live simple Box2 axis test, so callback instrumentation is being investigated.

Native axes gate verified live: with Box2 rotated Y=30 degrees and Slab Object local selected, focusing the viewport then pressing Godot's T shortcut rotated the native red/blue axes to match the solid. T was toggled back, Inspector rotation undone, and original lab saved. This isolates the remaining orientation issue to synchronization with Godot's native local-space state.

## Earlier input-tool blocker

The apparent native-drag failure is now isolated to computer-use input, not a proven remaining Slab failure. Live trace on 13 Sep recorded native press PASS and commit, but its intervening motion had changing absolute position with `button_mask=0`, `relative=(0,0)` and `screen_relative=(0,0)`. Godot requires the LEFT button mask before applying native motion, so no `_set_subgizmo_transform` callback ran. Do not weaken product event handling to accommodate malformed synthetic input. Native move/rotate/scale acceptance still needs a real held-button gesture or corrected computer-use tool.

Automatic World/Object-local synchronization passed in the actual editor after the fix: choosing Object local on a Y=30-degree solid rotated native axes and enabled Godot local space; choosing World restored world axes and disabled local space. No manual T was needed. The temporary rotation was undone and the original scene saved.

Active pivot also passed visually: selecting all eight Box2 vertices placed the default pivot at their centre; choosing Active element moved it to the last vertex while retaining all eight selected vertices and leaving geometry unchanged. Selection-centre was restored. Earlier custom-world pivot evidence remains valid.

Final checkpoint verification: scripts/slab-verify rebuilt the shared extension and kernel test, then passed all gates (/tmp/slab-gizmo-final-verify.log). Temporary tracing has been removed. Website lint/build passed after the documentation changes. Native Move/Rotate/Scale real-input acceptance remains unproven because the available computer-use drag emits no held LEFT button. The goal is not complete.
