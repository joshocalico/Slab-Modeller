# PRS-40 level brief: Signal Relay Annex (v3 place bar)

**Audience:** QA (run) · Design (massing + mood + capture) · CoS (kick + report) · Eng (fixes)
**Authors:** Product with Design (massing/mood) and QA (pass criteria)
**Date:** 2026-09-21 (ACST)
**Linear:** [PRS-40](https://linear.app/joshsteele/issue/PRS-40)
**Related:** [PRS-38](https://linear.app/joshsteele/issue/PRS-38) · [PRS-39](https://linear.app/joshsteele/issue/PRS-39)
**Status:** Shipped demo on bleeding (PRS-40 Done, Annex v3.1 via PR #46). PR #47 holds merge to main until Joshua/Astra. Historical: #44 tip `6cf335bc` was not squashed as Done.

**Source of record:** this file in the repo (`docs/briefs/prs-40-level-brief.md` on `bleeding`). Box `/workspace` copies are mirrors only.

## Why v3.1

Joshua rejected craft rebuild tip `a2463c71` (“still not a true level”). Thickness, palette, and tool coverage were necessary but not enough. Stills still read as a slab collage / tool demo. Do not merge that tip as Done for PRS-40. Tip `6cf335bc` on PR #44 was closer but still rejected for weak / incomplete paint. Do not squash #44 as Done.

## Goal

Author a small interior that a stranger recognizes as a room from a wide still, with no caption. Circulation readable in one frame: doorway → bay → climb → rack in the room. Use that build as a full product audit of major shipped V1 surfaces. `scripts/slab-verify` green is required but not enough.

Care bar: How to try it stays honest. Do not mark docs figures Done when they show broken chrome.

Tutorial fodder: same build later. One path. Note clip moments. Design films after Bugs clear.

## Craft bar (Done when)

All must hold. Solid and prop count rise as craft needs. No budget that kills place.

### Place readability (gate)

A wide still must sell “Signal Relay Annex” without text. Fail if it looks like floating plates, a T-junction of slabs, or a tool demo.

Design composition CLAIM (2026-09-21). Stranger test: caption-free stills must sell door, bay, climbable stair, loft-as-loft, rack-in-room. Fail = collage / floating plates / trophy cube.

1. Shell at least 8×6×3.5 m (grow for air). Bay about 4 m deep. Loft over the back half.
2. At least one pier or half-wall so the bay reads as a room, not an empty box.
3. Doorway as threshold with depth and look-into bay. Opening about 1.0×2.1 m, jambs ≥0.25 m.
4. Stair along a wall, attached bay floor ↔ loft deck. Create Stair preferred. Optional handrail mass. Climbable in frame. Not a wafer ramp.
5. Loft as a room: half-wall or rail; at least 0.8 m clear stand space in front of the rack; rack against wall or niche on a plinth (not a trophy pad).
6. Rack as furniture (~0.6×0.4×1.8 m): plinth + bezel topo + Soft Select. Equipment in the room, not a free-floating cube.
7. At least two supporting props (crate / cable / light box / conduit or similar).
8. Circulation clear in wide stills: outside → door → bay → stair → loft with rack. annex-01 / annex-02 / annex-06 must show that path.

Product accepts this CLAIM.

### Mood / materials (obvious + full UV paint)

8. Design surface CLAIM (2026-09-21). Thumbnail-readable high-contrast palette:
   * Bay floor: cool blue-grey.
   * Walls: warm ochre.
   * Ceiling: charcoal.
   * Loft deck: warm grit/rust (clearly not the bay).
   * Door jamb: dark trim.
   * Rack body: near-black + Roughness.
   * Bezel: saturated amber + Emission indicator.
9. Materials must read at a glance. Subtle tint fails even if hex codes differ.
10. Fully painted UVs. Full island = coverage of UV island area, not touched once. Architecture + rack Unwrap/Pack/Fit, then paint to these Albedo floors:
    * Bay floor / loft deck / rack body ≥90%.
    * Walls / soffit ≥85%.
    * Door jamb ≥80%.
    * Rack bezel ≥95% amber Albedo + Emission blob ~8–16 px, Flatten committed.
    Flood first (brush ≥40% island diameter), then detail. Sparse dabs fail. A 1:1 UV atlas shows filled blocks, not white + dots. Architecture and rack both show filled albedo in wide stills.
11. Mood: exterior cool vs interior spill; bay worn; loft cleaner; rack dark with Emission. Value contrast sells atmosphere.
12. annex-06: loft + rack in frame, dock visible, filled bezel + architecture. Sells painted place at thumbnail without canvas zoom. Dabs fail. Flatten commit required.

### Full V1 coverage

Exercise major shipped V1 surfaces while authoring the place. Named gaps only; never fake hits.

* Create: Box + ≥1 other needed shape (Stair required if stairs are Create Stair).
* Object: Mirror and/or Array and/or boolean as craft needs; Op Card Apply/Cancel where used.
* Topo: Extrude, Inset, Bevel, Loop; Connect/Dissolve if natural.
* Soft Select with visible falloff.
* Solid Isolate + Face Isolate; Esc exits Faces without clearing Soft Select.
* UV: Unwrap, Pack (≠ Unwrap), Fit; element select if shipped.
* Paint: Albedo + ≥1 other channel; layers if shipped; Flatten commits; dock visible.
* Export OBJ (+ STL/FBX if on tip); Import External; Promote External-only.
* Save / reopen editable with collision on.

## Pass when (rebuild checklist)

1. Place readability gate passes on wide stills (stranger test, no caption).
2. Doorway threshold, enclosed bay, climbable stair, loft-as-room, rack-as-furniture all present.
3. Mood/materials sell the annex at a glance (high contrast). Fully painted UVs on painted solids.
4. Full V1 coverage met or gaps named.
5. Tool path + save/reopen honest.
6. Clip moments annex-01…08 noted with place in frame.

## Must be out

* Slab collage / floating plates / T-junction demos / trophy-pad rack
* Empty single box with a cube called a rack
* Bare grey, subtle tint, or single-stroke blank-atlas paint
* Thin tool-path strips that ignore place
* Merging rejected tips as Done
* Fake coverage

## Clip moments

Same stems annex-01…08. Every still shows the place. annex-01 must read as an entrance into a room. annex-06 shows rack+loft, not a dab on a blank canvas.

## Pass criteria (QA owns)

PASS only when:

1. Place readability gate met.
2. Mood/materials met: obvious contrast + fully painted UV islands on architecture and rack.
3. Coverage met or gaps named.
4. Live chrome honest.
5. Bugs filed as you go.
6. `scripts/slab-verify` EXIT=0 on same tip (necessary, not sufficient).

Evidence on Linear: GATE.md, wide place stills, coverage checklist, Bug ids, slab-verify log.

## Bug filing rule (QA owns)

Bug vs Improvement; file as you go with How to try it + media when chrome; no silent batch; do not reopen fixed PRS-38/39 unless still broken.

## Preconditions

Hold until this brief is on bleeding and CoS re-kicks. Do not treat PR #39 / tip `a2463c71` as Done.

## Report back to CoS

* Tip SHA
* Place readability: pass / fail (why, with still)
* Mood / painted UVs: pass / fail
* Coverage: pass / gaps
* Bugs / clip moments / slab-verify EXIT

## Owners

* Product: this brief, place readability gate
* Design: massing + mood CLAIM, capture stills that sell the place
* QA: rebuild, evidence, Bugs, CoS report
* Eng: fix Bugs
* CoS: re-kick after brief lock

## Notes

v3.1 adds obvious texture + full UV paint on top of v3 place language. Design CLAIMED composition (shell≥8×6×3.5, bay~4 m, pier/half-wall, threshold door, wall stair, loft ≥0.8 m clear, rack on plinth in niche, ≥2 props) and mood (exterior cool vs interior spill; bay worn; loft cleaner; rack Emission). Capture stems annex-01…08 unchanged.

Surface addendum: Design CLAIMED thumbnail palette (cool blue-grey bay, warm ochre walls, charcoal ceiling, grit/rust loft, dark jamb, near-black rack, amber Emission bezel) and full-island fill floors (bay/loft/rack ≥90%, walls/soffit ≥85%, jamb ≥80%, bezel ≥95% amber + Emission blob). Flood first, then detail. Do not squash #44 / `6cf335bc` as Done.
