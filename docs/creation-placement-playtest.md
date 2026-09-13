# Creation placement authoring check

The PowerHouse authoring pass repeatedly created parts at the scene origin, then moved them to the room through three Inspector position fields. This check uses the normal Godot editor in Signal Foundry to test the replacement workflow.

## Native editor checks

1. With PowerHouseCeiling selected, click Create for a 2 by 2 by 2 metre box. The scene title stays clean, and no owned Box appears in the Scene tree.
2. Move the pointer onto the courtyard. A gold preview appears in the current work area, and the placement instructions remain visible.
3. Click to place. One Box appears in the Scene tree and becomes Godot's selected object.
4. Press Command-Z. The Box disappears and the scene title returns to clean. Redo restores the Box at the same position. Undo removes it again.
5. Repeat Create with no selected object. The preview still works. Escape removes it and leaves the scene clean.
6. Repeat Create and confirm with Enter after positioning the preview. The Box appears and becomes selected. Undo returns to the saved scene.

These temporary boxes were not saved. After the final reload, scrolling during placement visibly zoomed the editor view. Enter committed the box with its normal grey Prototype Color and Collision Enabled checked in the Inspector. Undo restored the clean scene.

## Findings and corrections

The first live implementation retained the preview's gold prototype color after confirmation. The placement owner now restores the candidate's original color and collision setting before committing. The reload check above confirmed that correction.

Surface Paint's persistent target row was readable in the 1225 by 768 editor, including `PowerHouseCeiling` with no selected face and `PowerHouse` with one face after a paint command. Painting the second object exposed a separate mismatch: Slab targeted PowerHouse while Godot's Inspector still targeted PowerHouseCeiling. Native Undo did nothing until PowerHouse was selected in the Scene tree. The test stroke was then undone, restoring the clean scene.

Synchronizing native selection before the paint edit corrected the Inspector target, but a further live check showed that Command-Z still did nothing while Surface Paint remained active. Leaving Paint mode made the same shortcut work. The paint branch in the viewport controller consumed modified keys after the painter passed them through. The fix must preserve host shortcuts as well as native selection and Undo history ownership.

After the shortcut correction and another editor restart, the author repeated the same ceiling-to-wall paint action. Godot's Scene tree and Inspector switched to PowerHouse. Command-Z immediately restored the clean scene while Surface Paint stayed active. Command-Shift-Z reapplied the edit, and a final Command-Z left the saved scene unchanged. No manual reselection or workspace switch was needed.

## Verification

The full verifier passed in `/tmp/slab-placement-verify.log`, including both native build targets, the kernel harness, placement tests, and gameplay checks. The final shortcut correction then passed focused paint routing tests in `/tmp/slab-paint-undo-shortcut.log` and the native check above. Rendered panel and material-transaction tests passed. Documentation checks reported 28 MDX pages, 75 local references, and no failures; website lint and production build passed.
