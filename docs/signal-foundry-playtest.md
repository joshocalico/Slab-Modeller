# Signal Foundry playtest

## Scope

On 13 September 2026, the saved scene was played in Godot through normal keyboard input, without changing the player spawn or teleporting to pickups. The run included a deliberate R at the catwalk checkpoint. It proves route reachability and checkpoint recovery, not an uninterrupted no-reset run or completion of the modeller UX acceptance goal.

## Verified route

| Stage | Observed result |
| --- | --- |
| START, maintenance room | Player begins at approximately (3, 0.35, 3.5). The doorway and bridge lead into the turbine hall. |
| Stairs and cell 01 | Stairs climb to feet y=3.45 on UpperCatwalk. First cell collected at approximately (15, 3.45, -1.6). |
| Catwalk checkpoint | The editor-authored checkpoint activates during the approach. R returns to (15, 3.45, -1.7), grounded on UpperCatwalk and facing +Z toward the jumps. Cell count is preserved. |
| Service landings | Four walking-speed jumps reach JumpLanding01 through JumpLanding04. Feet heights are 3.95, 4.45, 4.95, and 5.45. Cell 02 is reachable on the last landing. |
| Courtyard | Returning along the lower landings, then walking to the east doorway near z=3, reaches the courtyard checkpoint. |
| Ring lift | F3 reports MovingPlatform as the floor during carriage. Transfer onto RingObservationDeck reaches feet y=6.75 and cell 03. |
| Hazard lane | Both red strips can be jumped at walking speed. |
| Exit | With three cells, the exit reports EXIT POWERED · FOUNDRY COMPLETE. |
| Hazard recovery | Deliberately walking into a strip afterward returns to COURTYARD and preserves all three cells. |

The final service-jump sign was checked from the catwalk respawn after saving. It is visible above the first landing and reads SERVICE JUMPS / CELL 02.

## Editor-authored changes

The catwalk checkpoint was duplicated, named, positioned, configured, and saved through Godot. Its origin is (14.5, 3.45, -2.1), rotation Y is 180 degrees, and its local respawn offset is (-0.5, 0, -0.4). A Label3D child supplies the service-jump cue.

Saving upgraded older Slab serialization to version 3. Loading the previous and current scenes through the current extension produced identical normalized data, transforms, and stored material properties for all 20 existing Slab solids. No existing geometry was changed for this pass.

## Lift failure and regression

Standing on the courtyard floor beneath a returning lift caused the player to pass through the floor and trigger the y < -6 reset. A separate physics fixture reproduced this without loading or writing the level.

The reusable moving platform now has collision priority 0.1, below the static world. The regression places players at three lateral positions under a descending platform for multiple cycles. All remain above the floor tolerance and avoid a reset. Forcing the previous priority of 1.0 makes all three cases fail. The original rider-carriage checks still pass.

This prevents floor tunnelling. A player trapped under a platform can still be displaced by the squeeze; a marked boarding area or barrier remains useful.

`scripts/slab-verify` now runs the player, interaction, and animation gameplay checks alongside the kernel and editor suites. All gates passed after the scene and mover changes.

## Courtyard route cue, 14 September

A fresh normal-spawn playtest reached the turbine hall and courtyard checkpoint. The turbine dominates the doorway view, and the hall's courtyard opening had no nearby direction cue. A native Label3D was created, named CourtyardRouteSign, styled, positioned, and saved through Godot as a child of TurbineHall.

An above-door placement was tested in the game and rejected because the overhead landing obscured the lettering from the walking approach. The final sign sits beside the opening at hall-local `(11.52, 2.4, 9.5)`, Y rotation -90 degrees, with 64-pixel text and a 4-pixel outline. It reads `<- COURTYARD` and `LIFT / CELL 03`. Depth testing remains enabled. A typed Unicode arrow did not reach the saved text through computer input; the final sign uses a verified ASCII arrow.

The final fresh run began at the unchanged maintenance-room spawn. At feet `(14.28, 0.45, 6.67)`, facing east, both lines and the arrow were visible against the hall wall without looking up. Turning left, aligning with the opening, and walking through reached COURTYARD at approximately `(25.42, 0.45, 2.38)`, grounded on `ExteriorCourtyard/__body`. The saved scene differs only by the new label block; removing that block reproduces the previous scene exactly. No Slab geometry, artwork, player spawn, or gameplay component changed.

## Remaining work

- Give the second-cell route a visible return path to the courtyard doorway.
- Mark the lift boarding area and make upper-deck departure easier to read.
- Replace the sparse exterior with a stronger architectural setting and deliberate lighting.
- Review pickup, checkpoint, and exit labels that currently render through walls.
- Make completion persistent and visibly change the exit destination.
- Continue editor-authored complex modelling and material/UV workflows. A reachable three-cell route alone does not meet the requested level ambition.
