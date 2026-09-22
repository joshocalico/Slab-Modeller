# Signal Relay Annex (v3.1 surface pass)

An editor modelling demo with an enclosed bay, a stair, a loft, and a relay rack. The scene contains editable Slab solids, painted materials, a preview camera, and saved lighting. It has no player controller or gameplay script. Use Signal Foundry for the playable platformer example.

## How to try it

1. Open `project/` in Godot 4.7 with the Slab plugin enabled.
2. Open `signal_relay_annex.tscn`.
3. Use the Slab bottom panel to select and edit the solids.
4. Play the current scene to inspect its saved camera and lighting.
5. For the threshold view, select `EntranceCamera` and enable the viewport's **Preview** checkbox. `Camera3D` remains the runtime camera.

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

The historical captures below do not prove the brief's readability and surface-quality criteria. Use the September 23 native captures for the current scene. In particular, the old `annex-06-paint.png` is overexposed and partly occluded.

The September 23 native-editor pass connected the stair to the loft, raised the ceiling above the rack, continued the ochre wall and dark trim materials, and replaced the opaque loft parapet with open rails and four posts. The stair handrail follows the climb. Saved cameras, a sky environment, sunlight, and a ceiling light provide repeatable views. Rack-body emission is disabled; its painted indicator uses a small white emission mask on black.

Seven painted materials are saved as binary Godot resources in `materials/`. This removes large embedded image strings from the scene while preserving the artwork. Unused rack material slots are empty; the used slot indices remain unchanged.

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

## Native editor evidence — September 23

These are actual Godot window captures, including a runtime view after closing and reopening the editor:

- [UV workspace](media/annex-09-native-uv.png): BayFloor selected after Unwrap at 32 px/m, Pack, and Fit UV. The initial 256 px/m attempt refused an undersized atlas without changing the solid.
- [Paint workspace](media/annex-10-native-paint.png): filled amber bezel albedo with the loft, stair, and rack visible.
- [Emission mask](media/annex-11-native-emission.png): black image with a small white indicator. Fill Layer, keyboard Undo/Redo, a pixel stroke, Flatten, and saving with Paint open were exercised in the editor.
- [Threshold](media/annex-12-native-threshold.png): the saved entrance inspection camera.
- [Reopened runtime](media/annex-13-native-runtime.png): the saved lighting, materials, stair, open loft rails, and indicator.

The saved-scene audit found 38 valid, editable solids with enabled collision and no temporary editor locks. Required albedo colours cover 100% of the sampled UV footprints. The emission patch is 9×9 pixels, with all 69 lit pixels inside the bezel's UV footprint. All preexisting albedo image bytes survived material externalization unchanged. See [the repeatable audit](../../../../docs/qa/annex-acceptance/README.md) for the method and limits.

## Historical captures

The original stills use **SubViewport + Camera3D.make_current** and a viewport texture composite (`root.get_viewport().get_texture().get_image()`). They are not recordings of the September 23 editor pass. See [CAPTURE.md](CAPTURE.md). Tip base `2b60ce1`.

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

BayFloor now has six saved unwrapped faces and the rack has 21. Other architecture still includes projected mapping; this pass does not establish Unwrap/Pack/Fit coverage on every painted solid. The flat colour fills establish coverage, not authored wear or texture detail. The wide runtime view shows bay → stair → loft → rack; the doorway is covered by a separate view. This remains an editor modelling sample, not a finished art showcase or playable level.
