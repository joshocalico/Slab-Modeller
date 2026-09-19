# Relay Yard

Open `relay_yard.tscn` and run the current scene. Recover three cells in the workshop, gallery and lookout, then return to the south gate. WASD, mouse look, Space jump, E interact, R reset, Esc release mouse.

The scene uses 88 Slab solids and seven textured materials. Stress surfaces include a C-shaped concave console, a hollow inset/extruded workshop with Boolean door/window, united crossing segmented arches, a 16-step staircase, narrow rails and sloping braces. Geometry and assets remain editable.

Rebuild (overwrites generated scene/material resources; do not run after hand painting without preserving edits):

```sh
scripts/godot --headless --path project --script res://demo/relay_yard/build_yard.gd
```

The default build includes all three right-wall windows and a 45° through-wall window. Boolean cleanup previously warped the straight-window faces; that is fixed. The angled cutter now starts outside the wall, creating a proper through-cut.

Negative control (deliberately touches the wall along an edge, must reject with NON_MANIFOLD_VERTEX 4 and leave the saved scene intact):

```sh
scripts/godot --headless --path project --script res://demo/relay_yard/build_yard.gd -- --knife-edge
```

Status: generated successfully and launched/rendered in real Godot. Headless traversal using the actual player controller, input actions and Slab collision passes the full route: doorway/threshold, all three cells, stair ascent/descent, walkway, gate opening and win condition. No teleporting or hidden collision ramp. Replay with:

```sh
scripts/godot --headless --path project --script res://demo/relay_yard/traverse_yard.gd
```

Final review (12 September 2026): actual Godot runtime renders of the player view, overhead layout and workshop were inspected. HUD and material separation are readable. The full route above is controller/physics verification; manual end-to-end gameplay has not been verified. The separate original demo is unchanged.

Surface Paint was exercised in the loaded Godot editor through multiple Cursor/Codex iterations: face material assignment, canvas and 3D pixel strokes, move/scale/free rotation, reset, undo/redo, PNG save and scene save. On macOS use **Cmd-drag** to rotate UVs (Shift-drag scales; unmodified drag moves). A measured free rotation reached 66.26°, and the platform hint now matches the working gesture.

`paint_acceptance.tscn` is a separate scratch artifact containing painted limestone. A fresh process verifies 18,086 red pixels on one assigned face, with UVs reset to identity. It intentionally retains experimental unused material slots; use `relay_yard.tscn` for the clean game.

```sh
scripts/godot --headless --path project --script res://demo/relay_yard/check_paint_saved.gd
```

Latest Cursor verification: `scripts/slab-verify` all gates green, 90 kernel tests / 1143 checks. Imported texture readback, real undo, dark/transparent textures and modifier dispatch have regression coverage. No commits were created.
