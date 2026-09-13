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

## Lift boarding landing, 14 September

Created LiftBoardingLanding through the native Slab Create tool, positioned it through the Inspector at `(27, 0.45, 4)`, and assigned Limestone to all six box faces through Surface Paint. The box is 2 × 0.15 × 2 metres. Selected the top face boundary, then applied a 0.025-metre bevel with three segments. Saved through Godot. It is a root-level static solid outside the lift travel footprint. Removing its node block reproduces the previous saved scene exactly.

A fresh native run followed the normal spawn route through the turbine hall to COURTYARD. Walking onto the pad without jumping reached feet `(28.17, 0.60, 5.13)`, grounded on `LiftBoardingLanding/__body`. This verifies the first step of the intended split ascent from courtyard y=0.45 to lift deck y≈0.75.

Boarding was not verified in this pass. Two attempts missed the low-stop pause and reached the courtyard floor under the lift. The returning platform displaced the player and briefly produced a downward velocity around 14.57 m/s. This matches the previously recorded squeeze limitation; this observation alone does not establish floor tunnelling or a regression. The pad makes a safe waiting position, but departure timing and access beneath the deck still need work. Do not treat the pad as completing lift usability.

## Bevel mapping acceptance, 14 September

Selected all 18 LiftBoardingLanding faces through Face mode and opened Surface Paint. Mapping reported Limestone across the selection. Set Pixels/metre to 16 with Texture px 256 and clicked Unwrap. The panel reported one island and 15 automatic cuts. The canvas reframed and the viewport updated. This checks the native authoring path on narrow segmented bevel strips; it does not prove packing optimality or absence of UV overlap.

Saved the temporary unwrapped state through Godot, then used native Cmd-Z and Save. The complete saved scene matched the committed scene byte-for-byte. Cmd-Shift-Z and Save reproduced the complete temporary unwrapped scene byte-for-byte. A final Cmd-Z and Save restored the original limestone mapping. No acceptance-only mapping change remains in the scene.

Undo retains the canvas framing established by Unwrap, so the restored planar outlines extend outside the visible canvas. Fit UV remains available, but recovery framing deserves a further interaction pass. Native transform handles also remain visible during Paint; the design record documents the public API limitation and selection-ownership tradeoffs.

## UV recovery follow-up

The canvas now detects restored mapping bases as well as face selection changes. A rendered editor regression reproduces the prior failure: Unwrap Undo restored exact planar data but left its UV corners outside the canvas. With the fix, the restored corners are visible and centred. It also covers Undo/Redo after changing the density of an already unwrapped face. Repeat, rotation, UV movement, cancellation, and their history keep the view steady. Explicit Unwrap still frames the result when a repeat operation resets placement without changing the mapping basis. The final rendered run passed with zero failures in `/tmp/slab-uv-recovery-final.log`.

The reviewed regression capture also exposes a separate limit: very small UV islands occupy little canvas space even after Fit UV because framing uses a minimum 0.25-unit span. This recovery fix makes restored layouts visible; closer framing and smooth wheel zoom for tiny islands remain to be assessed.

## Small-island framing follow-up

Fit UV now uses actual selected UV extents, with shared finite limits across Fit, wheel zoom, and pointer conversion. The rendered before/after regression reproduced the small-island framing failure and passed after the fix. Both small and large transient mappings occupy 82% of the limiting canvas dimension; wheel input zooms in and back out without jumping and preserves the UV point under the pointer. A point-only mapping remains finite. The temporary geometry data is restored exactly.

Reviewed `/tmp/slab-paint-small-unwrap-after.png`, `/tmp/slab-paint-tiny-fit-after.png`, and `/tmp/slab-paint-tiny-zoom-after.png` with the Brick brush texture. The ordinary small unwrap has a readable outline over the magnified texture; the extreme tiny mapping remains visible and grows about the off-centre pointer. `/tmp/slab-uv-extremes-final.log` reports zero rendered failures. Saved level geometry and materials remain unchanged. Scale and rotation drag sensitivity still needs work across zoom levels.

## UV modifier sensitivity follow-up

Scale and rotation now measure editor-scaled screen distance from the initial press. The regression first reproduced four failures: differing results across zoom levels and incorrect expected amounts for both modifiers. After the fix, a 25-logical-pixel horizontal drag rotates 25 degrees at either tested zoom. A diagonal Shift-drag of `(25, 15)` logical pixels multiplies U/V by `(1 + 25/180, 1 + 15/180)`. Twelve wheel steps separate the views.

The rendered checks send held modifiers, mouse motion and release, verify exact Escape cancellation and native Undo/Redo, and retain stable framing. Ordinary Move still follows the UV point under the pointer. `/tmp/slab-uv-modifier-after.log` reports zero rendered failures; the focused headless paint suite also passes. No saved level data changed.

## Courtyard ring materials, 14 September

Authored the ring's materials through Godot. In Front view, selected all 96 faces and assigned Limestone through Surface Paint Quick Load. Selected one front-band face, used Select Coplanar to obtain its 24-face band, and assigned Brick. Repeated from Rear view for the opposite 24-face band, reusing Brick from the loaded material palette. Saved through Godot.

The saved ring has 48 Limestone faces on its inner and outer curves and 48 Brick faces across both side bands. A read-only comparison against the preceding committed scene verified identical face IDs, vertex IDs, face vertices/corners, all UV attributes except material slot, transform, and volume of 27.5499954223633. Only the CourtyardRing scene block changed.

A fresh native run walked from START through the turbine hall to COURTYARD. At feet approximately `(25.33, 0.45, 2.88)`, grounded on ExteriorCourtyard, the brick band and limestone interior were visible beside the boarding pad. The material distinction was readable in the running game. This pass does not establish continuous texture flow around the curved band; its existing per-face planar UVs remain unchanged.

Select Coplanar avoided picking 24 side faces individually. Reusing the Brick palette required scrolling down to the palette, then back up to Assign. This is usable but adds travel during repeated material work in the compact dock. The normal camera Focus Selection centred the node's origin without fitting its whole extent, so framing the ring required zoom adjustment and an orthographic view.

## Remaining work

- Give the second-cell route a visible return path to the courtyard doorway.
- Mark the lift boarding area and make upper-deck departure easier to read.
- Replace the sparse exterior with a stronger architectural setting and deliberate lighting.
- Review pickup, checkpoint, and exit labels that currently render through walls.
- Make completion persistent and visibly change the exit destination.
- Continue editor-authored complex modelling and material/UV workflows. A reachable three-cell route alone does not meet the requested level ambition.
