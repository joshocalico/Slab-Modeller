# Signal Relay Annex (v3 place rebuild)

Editor-authored Slab level for [PRS-40](https://linear.app/joshsteele/issue/PRS-40). This tree is the **brief v3 place rebuild** against bleeding `@436355d` (place readability stranger test). It supersedes rejected collage tip `a2463c71` / [PR #39](https://github.com/joshocalico/slab-modeller/pull/39). **Not Done** for PRS-40 — do not merge as Annex Done.

## How to try it

1. Open `project/` in Godot 4.7 with the Slab plugin enabled.
2. Open `signal_relay_annex.tscn`.
3. Use the Slab bottom panel to select and edit the solids.

Brief: [docs/briefs/prs-40-level-brief.md](../../../docs/briefs/prs-40-level-brief.md).

## v3 place bar

Massing rewritten from empty (min-corner box placement corrected):

- Shell ~10×8×4 with an enclosed bay (~4 m) and loft over the back half
- Thick doorway threshold: jambs ≥0.25, lintel, sill/stoop, look-into the bay
- Pier + half-wall so the bay is a room, not a single empty box
- `make_stair` along WallE, attached bay floor ↔ loft; visible treads
- Loft as a room: supports, beam, rail; rack on a plinth in the back niche
- Props: crate, cable run/drop, overhead light, loft plaques

Mood: cool worn bay plate vs warm loft grit; mid plaster walls; darker soffit; rack dark chassis + Roughness; bezel Emission; exterior cool vs interior warm spill.

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

Audit stills use **SubViewport + Camera3D.make_current** and a viewport texture composite (`root.get_viewport().get_texture().get_image()`). **Never** `DisplayServer.screen_get_image`. See [CAPTURE.md](CAPTURE.md).

- `media/annex-01-create.png` — entrance / threshold look-into
- `media/annex-02-topo.png` — enclosed bay + loft; rack topo
- `media/annex-03-soft-select.png` — Soft Select falloff on the rack
- `media/annex-04-face-isolate.png` — Face Isolate; Soft Select preserved
- `media/annex-05-uv-pack.png` — Unwrap then Pack + Fit
- `media/annex-06-paint.png` — loft + bay; Flatten; dock visible
- `media/annex-07-export.png` — OBJ (+ STL on disk)
- `media/annex-08-external-promote.png` — doorway → bay → stair → loft; Promote chrome

## Coverage gaps (named)

`array`, `export_fbx`, `uv_element_select`. Promote External→Solid succeeded on this tip (PRS-41 fix at `8ece671`).
