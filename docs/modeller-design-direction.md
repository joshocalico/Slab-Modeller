# Modeller design direction

The current editor has a usable visual base. The next pass should make the active workflow easier to read before adding more commands. These priorities come from authoring Signal Foundry in the 1225 by 768 Godot editor.

## Make the current task obvious

Surface Paint now has an active gold highlight and a separator from the selection modes. Keep that distinction: the editing workspace and the vertex, edge, or face selection mode answer different questions.

Keep the selected object and element count beside the active tool, even while an operation reports success. Surface Paint now keeps both in its target row when the main status reports messages such as "Using Timber." Preserve the specific opening-related Merge explanation.

## Give each workflow a clear order

Creation should read as shape, dimensions, placement, then confirmation. The room-authoring pass exposed different Box and Cylinder origins and offscreen creation. The design review compared explicit Origin/Selection/View choices, click-to-place preview, and immediate view placement with Move active. Click-to-place now shows the destination before insertion and works without a selected solid. Each shape uses the bottom centre of its built bounds, preserving the kernel's existing shape origins. Cancellation leaves no owned node or Undo entry; confirmation creates one Undo action. The [native editor check](creation-placement-playtest.md) covers click, Enter, Escape, repeated creation, Undo/Redo, and restored object appearance.

Surface editing should read as selected faces, material, then UV or pixel tools. A material thumbnail and name must remain readable when loaded. Clarify that choosing a material currently assigns it immediately to selected faces, while Assign repeats the active material assignment.

Keep tool options adjacent to the tool that owns them. Preserve separate remembered Inset, Extrude, and Bevel values and the existing Apply/Cancel boundary.

## Protect the modelling view

Surface Paint currently leaves the dock enlarged when returning to modelling. Godot exposes no public bottom-panel splitter height control, so do not resize private editor ancestors. Keep the compact modelling minimum and let the user collapse the dock. Check both a compact dock and a loaded material thumbnail before accepting a layout.

## Keep the first design pass focused

Prioritize placement, persistent target context, and the material-to-UV-to-pixel workflow. Edge loops and richer modelling operations remain useful future work, but they do not resolve these interruptions. Judge each change by building another part of Signal Foundry with it.

## Acceptance

Use the editor to select a wall, assign an existing material, adjust UVs, paint pixels, return to face editing, and undo each edit. Save and reopen the result. Repeat on a curved model and a room with an opening. Record where a control needs explanation or hides the next action. A screenshot alone cannot establish that the flow works.
