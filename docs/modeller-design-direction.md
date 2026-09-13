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

Surface Paint currently leaves the dock enlarged when returning to modelling. Godot exposes no public bottom-panel splitter height control, so do not resize private editor ancestors. Keep the compact modelling minimum and let the user collapse the dock. Check both a compact dock and a loaded material thumbnail before accepting a layout.

## Keep the first design pass focused

Placement and persistent target context now have native editor evidence. The remaining layout work should give active operation settings and Apply/Cancel a consistent location, reduce duplicate material and UV controls, and preserve enough viewport space for picking. Compare compact layouts using a selected face with a loaded material before choosing one.

Selection conversion also matters during authoring. Rounding a roof requires its perimeter edges; selecting the top face should provide a direct route to that set. Judge this and other modelling additions by building another part of Signal Foundry with them.

## Acceptance

Use the editor to select a wall, assign an existing material, adjust UVs, paint pixels, return to face editing, and undo each edit. Save and reopen the result. Repeat on a curved model and a room with an opening. Record where a control needs explanation or hides the next action. A screenshot alone cannot establish that the flow works.
