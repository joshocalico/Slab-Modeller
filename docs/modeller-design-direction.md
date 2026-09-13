# Modeller design direction

The current editor has a usable visual base. The next pass should make the active workflow easier to read before adding more commands. These priorities come from authoring Signal Foundry in the 1225 by 768 Godot editor.

## Make the current task obvious

Surface Paint now has an active gold highlight and a separator from the selection modes. Keep that distinction: the editing workspace and the vertex, edge, or face selection mode answer different questions.

Keep the selected object and element count beside the active tool, even while an operation reports success. The panel header now preserves this context in modelling and painting. Preserve the specific opening-related Merge explanation.

## Give each workflow a clear order

Creation should read as shape, dimensions, placement, then confirmation. The room-authoring pass exposed different Box and Cylinder origins and offscreen creation. The design review compared explicit Origin/Selection/View choices, click-to-place preview, and immediate view placement with Move active. Click-to-place now shows the destination before insertion and works without a selected solid. Each shape uses the bottom centre of its built bounds, preserving the kernel's existing shape origins. Cancellation leaves no owned node or Undo entry; confirmation creates one Undo action. The [native editor check](creation-placement-playtest.md) covers click, Enter, Escape, repeated creation, Undo/Redo, and restored object appearance.

Surface editing should read as selected faces, material, then UV or pixel tools. A material thumbnail and name must remain readable when loaded. Choosing a palette brush and assigning it are separate steps. The canvas now labels a brush preview when it differs from the selected faces' material. Keep that distinction visible before the author edits UVs or pixels.

Keep tool options adjacent to the tool that owns them. Preserve separate remembered Inset, Extrude, and Bevel values and the existing Apply/Cancel boundary.

## Protect the modelling view

Godot exposes no public bottom-panel splitter height control, so do not resize private editor ancestors. Keep the compact modelling minimum and let the user resize or collapse the dock. Check both a compact dock and a loaded material thumbnail before accepting a layout. The side-inspector Paint layout now fits the authoring dock without expanding it on entry.

## Keep the first design pass focused

Placement and persistent target context now have native editor evidence. The remaining layout work should give active operation settings and Apply/Cancel a consistent location, reduce duplicate material and UV controls, and preserve enough viewport space for picking. Compare compact layouts using a selected face with a loaded material before choosing one.

Selection conversion also matters during authoring. Rounding a roof requires its perimeter edges; selecting the top face should provide a direct route to that set. Judge this and other modelling additions by building another part of Signal Foundry with them.

## Consolidate surface editing without losing capabilities

Surface Paint owns material choice, Assign, UV placement, and Mapping. Face mode keeps geometry commands and the Selection disclosure. Its right-hand settings appear for Align Face rather than repeating Paint's fields.

Unwrap is distinct from adjusting placement. It unfolds adjacent faces, uses marked and automatic seams, packs islands at physical density, and writes their mapping bases. Apply UV adjusts placement on the existing mapping. Edge-mode Mark Seam and Clear Seam remain available. Pixel's Image section controls blank image size and reports existing artwork dimensions.

Resize expands beside the image with Width, Height, Keep aspect, resampling, Apply Resize, and Cancel. The canvas stays visible while the author chooses dimensions. Only Apply changes the image; UV placement remains unchanged. This uses the modelling tools' explicit Apply and Cancel controls. The form shows pending dimensions, not a preview of the resampled pixels.

Preserve brush identity across solids. Surface Paint chooses a material resource, then Assign applies it to selected faces. A target-local numeric slot is not a transferable brush. The material picker and palette both choose the Brush without changing the solid. Assign or a viewport paint click applies it. Sample adopts the selected material and UV values.

New StandardMaterial3D in the picker replaces adding anonymous blank slots. Click its preview to edit it in Godot's Inspector, then Assign. Repeat ×2 and Repeat ÷2 preserve the old doubling and halving shortcuts beside Placement. These commit pending typed fields before applying one undoable edit.

The house tutorial follows this order: assign a wall material to all faces, select the roof and assign another resource, then repeat for the gables. It no longer relies on numeric material slots or the removed disclosure. The native room-workflow pass verified normal Face mode, Align Face settings and cancellation, quick repeats, saved UV values, and exact Undo restoration after this consolidation.

## Paint layout comparison

The native 1225 × 768 editor gives Slab about 815 screen pixels between Godot's sidebars. With Paint open, the divider is at Y=409. Material/UV's canvas spans approximately Y=603–738, while Pixel's spans Y=516–738. Switching tools keeps the divider stable.

Compared stacked controls, a left properties column beside the canvas, and a canvas-first toolbar with disclosed numeric fields. The side column is a candidate because paired U/V fields avoid horizontal scrolling and leave the canvas independent of property scrolling. It also reduces canvas width. The HTML sketches clipped lower fields at full size, so their proposed viewport-height gains are not acceptance evidence. A disposable Godot prototype must measure the actual controls, loaded picker, canvas, and scroll behavior before production adoption.

The initial native study moved actual controls beside the canvas. At the same dock height, the canvas changed from approximately 812 by 135 to 588 by 268 reference screen pixels. Its 222-pixel properties column fit the loaded material picker, paired UV fields, and Apply controls without vertical scrolling. That prototype doubled canvas height but did not establish a viewport-height gain. Its mode tabs and clipped duplicate target text needed further work. Advanced mapping controls still need a separate placement pass.

Production uses compact mode tabs above both columns, one selected-face/material summary in the Slab header, and Brush or Texture identity beside the actions. The native Signal Foundry replay entered Paint with the divider at Y=466 and a UV canvas approximately 561 by 186 screen pixels. Compared with the earlier stacked layout, the modelling view gained 57 pixels of height and the UV canvas gained 51. Pixel uses a narrower inspector and keeps the same dock height. These measurements describe this editor size and saved dock position, not a fixed layout on every display.

The inspector owns scrolling. Its action and UV sections use natural container heights; nested fixed-height scroll sections clipped the loaded picker and Apply buttons on initial entry. Material palette chips and Pixel's lower brush controls require a short scroll at the compact height. This is an accepted limitation of this checkpoint, not evidence that all controls fit at once. The study script now captures and checks the production layout rather than reparenting controls.

Native acceptance covered first entry, typed Rotation 15 without Enter followed by Apply UV, a UV canvas drag, Make Unique, Pixel canvas painting, scrolling to Opacity and Show UV, and returning to Face mode. Undo and Save restored Signal Foundry with no scene diff. The full verifier passed.

## Reference workflows

ProBuilder's [UV Editor](https://docs.unity3d.com/Packages/com.unity.probuilder@6.1/manual/uv-editor.html) separates its canvas from a context-sensitive Actions panel and distinguishes automatic mapping from manual UV editing. UModeler's [UV workflow](https://unity.umodeler.com/manual/editable-mesh/uv-editor/uv-editor-guide) moves from unwrapping through island placement to checking the applied texture. Its [painting inspector](https://unity.umodeler.com/manual/editable-mesh/painting-3d-editor/painting-mode-guide) groups setup and tools into collapsible sections.

For Slab, these support making mapping state and the next action visible, giving unwrap a clear place beside placement, and grouping secondary setup without hiding the canvas. They do not establish that Slab matches either product's capabilities or usability.

## Acceptance

Use the editor to select a wall, assign an existing material, adjust UVs, paint pixels, return to face editing, and undo each edit. Save and reopen the result. Repeat on a curved model and a room with an opening. Record where a control needs explanation or hides the next action. A screenshot alone cannot establish that the flow works.

## Native gizmo ownership during Paint

The 14 September native landing pass still shows Godot's transform arrows and rotation rings over the painted face. Paint consumes its gestures, but these handles imply an available transform action and obscure narrow bevel strips.

The installed Godot 4.7.2 extension API has no public native-transform visibility switch. Hiding a plugin gizmo affects its own drawing; clearing Slab subgizmo selection falls back to the selected object's transform gizmo. Removing native selection through EditorSelection could hide it while Slab retains a paint target, but would remove the Scene tree highlight and native Focus Selection target. It also requires explicit ownership across deferred selection signals, scene changes, target deletion, and external selection. Do not treat a temporary signal guard as sufficient restoration logic.

Preserve native selection behavior for now. A future detached paint-target prototype must prove framing, Inspector context, tree selection, switching solids, scene changes, and restoration before adoption. The ordinary Godot View Transform Gizmo toggle remains a manual option. This limitation is still open.

## Fit UV at different mapping scales

Fit UV should use the selected mapping's actual bounds and retain a margin around the outline. A quarter-tile minimum made low-density islands too small to edit. Wheel zoom must start from the fitted scale, with the point beneath the pointer held in place. Use the same finite scale limits for framing, wheel changes, and inverse pointer mapping.

A line fits its nonzero dimension. A point-only mapping uses a one-tile view rather than dividing by zero. These cases must not change mesh data or create history. Pixel image zoom remains a separate interaction.

Scale and rotation modifier drags still derive sensitivity from UV-space distance. After fitting very small or large islands, those gestures need a separate consistency pass; framing alone does not establish a complete editing workflow.
