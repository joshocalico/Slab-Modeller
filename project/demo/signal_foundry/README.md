# Signal Foundry

An editor-authored Slab platformer and modelling workflow test. Open `signal_foundry.tscn` in Godot and press **F6** to run this scene. Collect three cyan energy cells, then reach the courtyard exit.

Use **WASD** and the mouse to move/look, **Space** to jump, **Shift** to sprint, **R** to return to the checkpoint, and **Esc** to release the mouse. **F3** toggles diagnostics. Keyboard-only controls and reusable gameplay components are documented in [gameplay/README.md](gameplay/README.md).

## Route

1. Leave the brick maintenance room through its doorway into the enclosed turbine hall.
2. Climb the staircase to the catwalk for the first cell. Cross the four rising platforms for the second.
3. Leave through the hall's courtyard doorway and activate the checkpoint beacon.
4. Board the moving lift beside the full-circle ring. Transfer to the observation deck at the top and collect the third cell.
5. Return to the courtyard, jump the two red hazard strips, and enter the powered exit. Falling or touching a hazard returns you to the checkpoint with collected cells intact.

The scene includes inset/extruded rooms, boolean doorways, stairs, a partial arch turbine housing, a closed 360-degree ring, several materials, and a saved pixel-painted courtyard surface. Layout, modelling, lighting, material work, and turbine animation were authored through the Godot editor. The turbine uses a looping native `AnimationPlayer`; reusable scripts supply pickups, checkpoint feedback, the lift shuttle, and hazards.

## Live validation — 13 September 2026

Editor and runtime checks covered both room doorways, stair climbing, all four platform jumps, lift boarding/carry/upper transfer, all three pickups, checkpoint recovery, hazard resets and jumps, and the powered exit. A continuous three-cell winning run began at a temporary lift-side test spawn; the normal maintenance-room entry was tested separately. The saved scene restores the normal maintenance-room spawn.

The final hazard-height correction was loaded into a fresh runtime and checked for both contact reset and a successful jump. Full `scripts/slab-verify` passes. Gameplay helper checks are listed in the component README.

This is a compact playable prototype with session-local progress. The courtyard provides an open lift and hazard course; the enclosed hall provides the denser modelling and traversal test.
