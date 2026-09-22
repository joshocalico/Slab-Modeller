# Signal Relay Annex (v3.1 surface pass)

An editor modelling demo with an enclosed bay, a stair, a loft, and a relay rack. The scene contains editable Slab solids, painted materials, a preview camera, and saved lighting. It has no player controller or gameplay script. Use Signal Foundry for the playable platformer example.

## How to try it

1. Open `project/` in Godot 4.7 with the Slab plugin enabled.
2. Open `signal_relay_annex.tscn`.
3. Use the Slab bottom panel to select and edit the solids.
4. Play the current scene to inspect its saved camera and lighting.

Brief: [docs/briefs/prs-40-level-brief.md](../../../../docs/briefs/prs-40-level-brief.md).

## Intended palette

The v3.1 brief calls for this palette:

- Bay floor: cool blue-grey
- Walls: warm ochre
- Ceiling: charcoal
- Loft deck: warm grit / rust (not the bay)
- Door jamb: dark trim
- Rack body: near-black + Roughness
- Bezel: saturated amber + Emission

The historical captures below do not prove the brief's readability and surface-quality criteria. In particular, `annex-06-paint.png` shows the paint controls and amber atlas, but its overexposed, partly occluded scene view does not show the rack and loft clearly enough for acceptance.

The September 23 native-editor pass connected the stair to the loft, raised the ceiling above the rack, continued the ochre wall and dark trim materials, and replaced the opaque loft parapet with open rails and four posts. The stair handrail follows the climb. A camera, sky environment, sunlight, and ceiling light now provide a reproducible lit view. Rack-body emission is disabled; its painted indicator uses the emission texture as a mask. Reopen, collision, and painted-island acceptance are still separate checks.

The scene includes a bay, a loft, a doorway threshold, a pier and half-wall, stairs, a rack on a plinth, and crate, cable, light, and rail props.

## Solids

Thirty-eight `SlabSolid` nodes under `SignalRelayAnnex`:

- Threshold: `ExteriorPad`, `Stoop`, `DoorLintel`, `DoorJambL`, `DoorJambR`, `DoorSill`
- Shell: `BayFloor`, `WallN`, `WallE`, `WallW`, `WallS_L`, `WallS_R`, `Ceiling`
- Bay massing: `BayPier`, `BayHalfWall`
- Loft: `LoftDeck`, `LoftSupportE`, `LoftSupportW`, `LoftBeam`, `LoftRail`, `LoftRailCap`, `LoftRailPost1`–`LoftRailPost4`
- Climb: `AnnexStair`, `StairRail`, `StairRailPost`
- Rack: `RackPlinth`, `RelayRack`, `RackNicheL`, `RackNicheR`
- Props: `Crate`, `CableRun`, `CableDrop`, `OverheadLight`, `LoftPlaque`, `LoftPlaqueR`

## Historical captures

Audit stills use **SubViewport + Camera3D.make_current** and a viewport texture composite (`root.get_viewport().get_texture().get_image()`). **Never** `DisplayServer.screen_get_image`. See [CAPTURE.md](CAPTURE.md). Tip base `2b60ce1`.

- `media/annex-01-create.png`: doorway view and Object controls after Subtract.
- `media/annex-02-topo.png`: Edge mode, with status reporting Connect on RelayRack. The rack geometry is occluded.
- `media/annex-03-soft-select.png`: Soft Select controls with Radius 1.2 and Smooth falloff. The rack deformation is not visible.
- `media/annex-04-face-isolate.png`: Faces isolation active while Soft Select controls remain enabled.
- `media/annex-05-uv-pack.png`: UV outlines with status reporting three packed islands.
- `media/annex-06-paint.png`: Paint controls and a solid amber image. Rack and loft surface readability remains unproven.
- `media/annex-07-export.png`: Object controls with Export available. The still does not show a saved export or round trip.
- `media/annex-08-external-promote.png`: an External mesh selected with Promote available. The still does not show a successful conversion.

## Recorded coverage gaps

The original capture pass did not cover FBX export or UV element selection. These are capture gaps, not a statement about current tool availability.
