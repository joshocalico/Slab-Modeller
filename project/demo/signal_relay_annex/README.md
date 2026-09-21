# Signal Relay Annex (v3.1 surface pass)

Editor-authored Slab level for [PRS-40](https://linear.app/joshsteele/issue/PRS-40). This tree is the **brief v3.1 surface rebuild** against bleeding `@2b60ce1` (high-contrast palette + full UV island fills). It supersedes the weak / incomplete paint on tip `6cf335bc` / [PR #44](https://github.com/joshocalico/slab-modeller/pull/44) without squashing that PR as Done. **Not Done** for PRS-40 — do not merge as Annex Done.

## How to try it

1. Open `project/` in Godot 4.7 with the Slab plugin enabled.
2. Open `signal_relay_annex.tscn`.
3. Use the Slab bottom panel to select and edit the solids.

Brief: [docs/briefs/prs-40-level-brief.md](../../../docs/briefs/prs-40-level-brief.md).

## v3.1 surface

Thumbnail-readable high-contrast palette with flood-filled UV islands (then Flatten):

- Bay floor: cool blue-grey
- Walls: warm ochre
- Ceiling: charcoal
- Loft deck: warm grit / rust (not the bay)
- Door jamb: dark trim
- Rack body: near-black + Roughness
- Bezel: saturated amber + Emission

Fill floors after flood (brush ≥40% island diameter): bay / loft / rack / wall / ceil / jamb / bezel all **1.0**. Sparse dabs avoided.

Place massing is unchanged from the v3 stranger-test rebuild: shell ~10×8×4; enclosed bay (~4 m); loft over the back half; thick doorway threshold; pier + half-wall; wall stair bay↔loft; rack on a plinth in the back niche; crate / cable / light / rail props.

## Solids

Thirty-three `SlabSolid` nodes under `SignalRelayAnnex`:

- Threshold: `ExteriorPad`, `Stoop`, `DoorLintel`, `DoorJambL`, `DoorJambR`, `DoorSill`
- Shell: `BayFloor`, `WallN`, `WallE`, `WallW`, `WallS_L`, `WallS_R`, `Ceiling`
- Bay massing: `BayPier`, `BayHalfWall`
- Loft: `LoftDeck`, `LoftSupportE`, `LoftSupportW`, `LoftBeam`, `LoftRail`, `LoftRailCap`
- Climb: `AnnexStair`, `StairRail`, `StairRailPost`
- Rack: `RackPlinth`, `RelayRack`, `RackNicheL`, `RackNicheR`
- Props: `Crate`, `CableRun`, `CableDrop`, `OverheadLight`, `LoftPlaque`, `LoftPlaqueR`

## Capture

Audit stills use **SubViewport + Camera3D.make_current** and a viewport texture composite (`root.get_viewport().get_texture().get_image()`). **Never** `DisplayServer.screen_get_image`. See [CAPTURE.md](CAPTURE.md). Tip base `2b60ce1`.

- `media/annex-01-create.png` — entrance / threshold look-into; cool bay, ochre walls, charcoal ceil
- `media/annex-02-topo.png` — enclosed bay + loft; rack topo; cool floor vs warm loft
- `media/annex-03-soft-select.png` — Soft Select falloff on the rack
- `media/annex-04-face-isolate.png` — Face Isolate; Soft Select preserved
- `media/annex-05-uv-pack.png` — Unwrap then Pack + Fit
- `media/annex-06-paint.png` — loft + rack strip; Flatten; dock visible; filled amber bezel atlas
- `media/annex-07-export.png` — OBJ (+ STL on disk)
- `media/annex-08-external-promote.png` — doorway → bay → stair → loft; Promote chrome

## Coverage gaps (named)

`export_fbx`, `uv_element_select`. Promote External→Solid succeeded on this tip (PRS-41 fix at `8ece671`).
