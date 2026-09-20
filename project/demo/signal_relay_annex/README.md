# Signal Relay Annex

Editor-authored Slab level for [PRS-40](https://linear.app/joshsteele/issue/PRS-40). This tree is the **craft rebuild** (place + texture + Design-locked palette). It replaces the rejected PR #39 greybox cubes. **Not Done** for PRS-40.

## How to open

1. Open `project/` in Godot 4.7 with the Slab plugin enabled.
2. Open `signal_relay_annex.tscn`.
3. Use the Slab bottom panel to select and edit the solids.

## Craft rebuild

Audited on bleeding tip `ecda207` (Design-locked surface palette after `7d1560a`). Brief: [docs/briefs/prs-40-level-brief.md](../../../docs/briefs/prs-40-level-brief.md).

Place: enclosed shell (~8×6×3.5), 0.3 m walls, boolean doorway, 0.2 m bay floor, loft stand ~1.1 m, `make_stair` (non-Box), topo'd relay rack (Bevel → Extrude → Inset → Loop → Connect + Soft Select).

Texture: Design-locked palette — bay cool plate, loft warm grit, walls mid plaster, ceiling darker soffit, rack dark chassis + Roughness, bezel accent + Emission.

## Solids

Eleven `SlabSolid` nodes:

- `BayFloor`
- `WallN`, `WallS`, `WallE`, `WallW`
- `Ceiling`
- `LoftDeck`
- `AnnexStair`
- `RelayRack`
- `LoftPlaque`, `LoftPlaqueR` (Mirror)

`annex_rack_export.obj` is the Wavefront export of `RelayRack`.

## Capture

Audit stills use **SubViewport + Camera3D.make_current** and a viewport texture composite (`root.get_viewport().get_texture().get_image()`). **Never** `DisplayServer.screen_get_image`. See [CAPTURE.md](CAPTURE.md).

- `media/annex-01-create.png`
- `media/annex-02-topo.png`
- `media/annex-03-soft-select.png`
- `media/annex-04-face-isolate.png`
- `media/annex-05-uv-pack.png`
- `media/annex-06-paint.png`
- `media/annex-07-export.png`
- `media/annex-08-external-promote.png`

## Known gap — PRS-41

[PRS-41](https://linear.app/joshsteele/issue/PRS-41): OBJ export of the topo'd `RelayRack` imports as an open mesh; Promote refuses (`mesh is open`). Chrome (External badge, Promote External-only) is honest. External is left intact.

## Tutorial clip stems

Same build, later capture (`annex-01`…`annex-08`):

| Stem | Beat |
| --- | --- |
| `annex-01-create` | Shell + boolean doorway; Design palette start; Stair present |
| `annex-02-topo` | Rack topo + Mirror plaques; Extrude Op Card; Connect |
| `annex-03-soft-select` | Soft Select falloff on the rack |
| `annex-04-face-isolate` | Face Isolate; Solid Isolate also hit |
| `annex-05-uv-pack` | Unwrap then Pack (distinct) + Fit |
| `annex-06-paint` | Place in frame; Flatten; dock visible; Albedo+Roughness+Emission |
| `annex-07-export` | Export OBJ (+ STL on disk) |
| `annex-08-external-promote` | Import External badge; Promote External-only; open-mesh refuse |
