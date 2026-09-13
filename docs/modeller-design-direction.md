# Modeller design direction

The current editor has a usable visual base. The next pass should make the active workflow easier to read before adding more commands. These priorities come from authoring Signal Foundry in the 1225 by 768 Godot editor.

## Make the current task obvious

Surface Paint opens a different workspace, but Face keeps the dominant gold highlight while Surface Paint looks inactive. Distinguish the editing workspace from the vertex, edge, and face selection modes. An author should be able to identify both without reading the help sentence.

Keep the selected object and element count beside the active tool. Put actionable refusal feedback there too. Preserve the specific opening-related Merge explanation.

## Give each workflow a clear order

Creation should read as shape, dimensions, placement, then Create. Placement still needs a preview and a deliberate default; the room-authoring pass exposed different Box and Cylinder origins and offscreen creation.

Surface editing should read as selected faces, material, then UV or pixel tools. A material thumbnail and name must remain readable when loaded. Clarify that choosing a material currently assigns it immediately to selected faces, while Assign repeats the active material assignment.

Keep tool options adjacent to the tool that owns them. Preserve separate remembered Inset, Extrude, and Bevel values and the existing Apply/Cancel boundary.

## Protect the modelling view

Surface Paint currently leaves the dock enlarged when returning to modelling. Restore usable viewport space without overwriting an intentional splitter resize. Check both a compact dock and a loaded material thumbnail before accepting a layout.

## Acceptance

Use the editor to select a wall, assign an existing material, adjust UVs, paint pixels, return to face editing, and undo each edit. Save and reopen the result. Repeat on a curved model and a room with an opening. Record where a control needs explanation or hides the next action. A screenshot alone cannot establish that the flow works.
