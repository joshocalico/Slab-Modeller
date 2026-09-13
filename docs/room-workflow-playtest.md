# Room workflow replay

13 September 2026. Native Godot 4.7.2, Signal Foundry, 1225 × 768 window.

## Authored in the editor

Created MaintenanceBay with Create Box, dimensions 4 × 3 × 4. Used the Inspector to place it at (26, 0.17, 19). Selected its top face, applied Inset 0.45, then Extrude -2.4. Saved the scene. The persisted room has 14 faces and volume 24.938059.

Created MaintenanceBayDoorCutter, dimensions 1 × 2 × 1, and positioned it at (27.5, 0.77, 18.8). It intersects the negative-Z wall and starts at the room floor. The saved scene retains this cutter; the doorway has not yet been applied through the editor.

A separate, unsaved runtime copy of the saved scene accepted Subtract with error 0, yielding 24 room faces and volume 24.037669. This confirms the placement is geometrically valid. It does not substitute for completing the native boolean interaction or a gameplay traversal.

## Panel change and verification

During Extrude, Inset, and Bevel previews, hide the unrelated command body and pivot/axis settings. Keep the selection mode strip, numeric operation controls, Apply, Cancel, and feedback visible. Restore the modelling controls when the operation ends.

Native replay verified an invalid extrusion with Apply disabled, Cancel restoring the controls, a valid inset with Apply restoring the controls, and Undo followed by scene save restoring the room to 14 faces. The temporary inset is not in the saved scene.

Chrome smoke passed 41 cases, including visibility and restoration checks. The full slab-verify passed all gates. The docs verifier passed 28 MDX pages and 72 local references. Website lint and the 32-page build passed.

## Outstanding findings

- The generic transform gizmo overlaps the operation handle. Clearing Slab's subgizmo selection merely moves the native gizmo back to the object pivot. That attempted fix failed a native replay and was reverted. No supported visibility hook was found in the exposed editor API.
- Fixed in the rendered-preview pass below: the proposed surface now replaces the source display during a valid operation.
- Fixed in the follow-up pass: Slab's status and boolean operand labels now follow selected-node renames immediately. Native rename to MaintenanceBayRenameCheck updated the status without reselection; Undo restored MaintenanceBay in both the tree and Slab. The test rename was undone and the scene saved without a scene diff. Smoke coverage also checks that renaming an unselected solid preserves current feedback.
- The doorway's native multi-selection step remains unfinished. Keyboard range-selection attempts did not produce two boolean operands through the current computer-use session. Do not classify this as a Slab bug without separating editor and input-tool behaviour.
- This bay has no final materials, roof, gameplay interaction, or tested approach route yet. It remains an authoring checkpoint.

The room tutorial now covers installed-addon prerequisites and exact cutter placement using the Inspector, instead of relying on an unspecified wall and drag direction.

## Rendered operation preview replay

Created a temporary 4 × 3 × 4 box in Godot, inset its top by 0.45, and saved that baseline. Extrude -2.4 displayed the cavity before Apply. The old selected-cap fill no longer covered the opening. Save kept the preview active and left the scene file byte-for-byte identical to the baseline. Extrude -4 restored the original surface and disabled Apply; returning to -2.4 recovered the preview. Cancel restored the original display. Apply committed the cavity, and Undo restored the inset cap.

Deleted the temporary box in Godot and restored the cutter's temporary inspection position. Saving returned the scene file to HEAD exactly. A later bevel pick hit PowerHouseVault rather than the intended cutter and was rejected at both 0.5 and 0.05 width. Cancel left its geometry unchanged. Crowded picking needs further investigation.

For a clear bevel replay, temporarily moved the cutter to Y=10 through the Inspector. Selected its exposed vertical edge and previewed a three-segment bevel at widths 0.05 and 0.3. The rendered silhouette changed before Apply; Cancel restored the sharp edge. Restored Y=0.77 and saved, again leaving the scene file identical to HEAD.

The full verifier passed all gates. The viewport smoke covers valid-to-invalid-to-valid preview changes. The new display-preview smoke checks packed scene properties, material references, collision state, mesh export, corrupt preview data, and exact display restoration on Cancel. The docs verifier passed 28 MDX pages and 72 local references.

Undo exposed a separate issue: geometry returned to the inset cap but the native gizmo remained at the extruded floor. The selected face ID had not changed, so the refresh cache missed the geometry change.

Fixed by subscribing to the selected solid's topology changes and invalidating the native gizmo frame. Native replay used an isolated cutter side face: Apply Extrude 0.5 moved the gizmo with the face, Undo restored both, and Redo moved both again. Undid the test edit, restored the cutter's position, and saved with no scene diff.

The full verifier passed all gates. The separate editor-hosted regression passed nine checks, including disconnecting the previously selected solid and preserving pending native drag state while invalidating its cached frame. It now runs in slab-verify. The runtime chrome smoke retains its 41 cases; editor-plugin construction belongs in the editor-hosted test.

## Hidden geometry picking replay

Selected MaintenanceBay, expanded the Inspector's Visibility section, and turned Visible off. Its surface disappeared. Clicked away, then clicked its former location at the left rim. Slab selected the invisible MaintenanceBay again, confirmed by the status label and the Inspector's unchecked Visible property. Restored visibility and saved with no scene diff.

This reproduces a picking defect, not merely an ambiguous click on overlapping visible geometry. Hidden solids must be excluded from both viewport candidates and occlusion checks. X-ray should expose occluded elements of visible solids without making hidden nodes selectable.

After the fix, replayed the same hide-and-click sequence in a restarted editor. The former rim location selected nothing; clicking the visible floor behind the hidden room selected ExteriorCourtyard. Face selection also selected the courtyard with X-ray both off and on. Restored the room's visibility, saved with no scene diff, and selected its visible slanted rim edge successfully.

The picking pass also corrects perspective interpolation: the world point tested for occlusion now projects onto the nearest point along the screen-space edge. Edges crossing the camera near plane are clipped before projection. The focused smoke covers perspective, orthographic, near-plane, hidden-solid, and hidden-ancestor cases. Full slab-verify passed all gates, including the editor-hosted gizmo regression. The docs verifier passed 28 MDX pages and 72 local references; website lint and its 32-page build passed.
