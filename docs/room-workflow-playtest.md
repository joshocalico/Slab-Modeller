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
- Operation previews draw result wire over the unchanged opaque source mesh. An inward extrusion's cavity becomes readable only after Apply. Rendered result geometry needs a deliberate preview lifecycle and source visibility strategy.
- Slab's status retains the old node name immediately after a scene-tree rename, until selection is refreshed.
- The doorway's native multi-selection step remains unfinished. Keyboard range-selection attempts did not produce two boolean operands through the current computer-use session. Do not classify this as a Slab bug without separating editor and input-tool behaviour.
- This bay has no final materials, roof, gameplay interaction, or tested approach route yet. It remains an authoring checkpoint.

The room tutorial now covers installed-addon prerequisites and exact cutter placement using the Inspector, instead of relying on an unspecified wall and drag direction.
