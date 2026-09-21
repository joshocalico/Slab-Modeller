# PRS-40 level brief: Signal Relay Annex (v3 place bar)

**Audience:** QA (run) · Design (massing + mood + capture) · CoS (kick + report) · Eng (fixes)
**Authors:** Product with Design (massing/mood) and QA (pass criteria)
**Date:** 2026-09-21 (ACST)
**Linear:** [PRS-40](https://linear.app/joshsteele/issue/PRS-40)
**Related:** [PRS-38](https://linear.app/joshsteele/issue/PRS-38) · [PRS-39](https://linear.app/joshsteele/issue/PRS-39)
**Status:** Product+Design locked 2026-09-21 (v3). Joshua rejected tip `a2463c71`. Place readability is the gate. Hold QA until CoS re-kicks after this brief lands on bleeding.

**Source of record:** this file in the repo (`docs/briefs/prs-40-level-brief.md` on `bleeding`). Box `/workspace` copies are mirrors only.

## Why v3

Joshua rejected craft rebuild tip `a2463c71` ("still not a true level"). Thickness, palette, and tool coverage were necessary but not enough. Stills still read as a slab collage / tool demo. Do not merge that tip as Done for PRS-40.

## Goal

Author a small interior that a stranger recognizes as a room from a wide still, with no caption. Circulation readable in one frame: doorway → bay → climb → rack in the room. Use that build as a full product audit of major shipped V1 surfaces. `scripts/slab-verify` green is required but not enough.

Care bar: How to try it stays honest. Do not mark docs figures Done when they show broken chrome.

Tutorial fodder: same build later. One path. Note clip moments. Design films after Bugs clear.

## Craft bar (Done when)

All must hold. Solid and prop count rise as craft needs. No budget that kills place.

### Place readability (gate)

A wide still must sell "Signal Relay Annex" without text. Fail if it looks like floating plates, a T-junction of slabs, or a tool demo.

Design composition CLAIM (2026-09-21):

1. Shell ≥8×6×3.5 m (W×D×H). Grow if rooms need air. Default rack ~0.6×0.4×1.8 m unless rewritten.
2. Bay ~4 m deep; loft over the back half. At least one interior pier or half-wall so it is not a single empty box.
3. Doorway as threshold. Thick opening about 1.0×2.1 m, jambs ≥0.25 m. Exterior face, then a clear look-into the bay. Interior continues past the threshold.
4. Stair along a wall, attached bay floor ↔ loft deck. Create Stair preferred. Visible treads/risers. Climbable in frame. Optional handrail. Not a wafer ramp or floating island.
5. Loft as a room. Half-wall or rail. At least 0.8 m clear stand space in front of the rack. Rack against a wall or niche, not on a trophy pad.
6. Rack as furniture in the loft. Plinth + bezel topo + Soft Select. Reads as equipment in the room, not a free-floating cube.
7. Circulation clear in wide stills: doorway → bay → climb → rack in the room. annex-01 / annex-02 / annex-06 must show that path.
8. At least two supporting props (crate, cable run, rail, light massing) so the room is not empty architecture. More solids OK.

Product accepts Design CLAIM dims and spatial moves above.

### Mood / materials

9. Palette CLAIM stands: bay cool worn plate; loft warm grit (distinct); walls mid plaster; ceiling darker soffit; rack dark chassis + Roughness; bezel accent + Emission on one indicator face.
10. Mood: exterior cool vs interior spill; bay worn; loft cleaner; rack dark with Emission indicator. Value contrast sells atmosphere. "Slightly tinted grey" fails.
11. annex-06: rack + loft in frame, Flatten commit, dock visible, mood readable.
12. UV Unwrap + Pack + Fit before paint on painted solids.

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
3. Mood/materials sell the annex.
4. Full V1 coverage met or gaps named.
5. Tool path + save/reopen honest.
6. Clip moments annex-01…08 noted with place in frame.

## Must be out

* Slab collage / floating plates / T-junction demos / trophy-pad rack
* Empty single box with a cube called a rack
* Bare grey or mood failure
* Thin tool-path strips that ignore place
* Merging rejected tips as Done
* Fake coverage

## Clip moments

Same stems annex-01…08. Every still shows the place. annex-01 must read as an entrance into a room. annex-06 shows rack+loft, not a dab on a blank canvas.

## Pass criteria (QA owns)

PASS only when:

1. Place readability gate met.
2. Mood/materials met.
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
* Mood: pass / fail
* Coverage: pass / gaps
* Bugs / clip moments / slab-verify EXIT

## Owners

* Product: this brief, place readability gate
* Design: massing + mood CLAIM, capture stills that sell the place
* QA: rebuild, evidence, Bugs, CoS report
* Eng: fix Bugs
* CoS: re-kick after brief lock

## Notes

v3 supersedes v2 place language. Design CLAIMED composition: shell ≥8×6×3.5 (grow for air), bay ~4 m, ≥1 pier/half-wall, thick doorway with look-into, stair along wall attached bay↔loft (Create Stair preferred, optional handrail), loft half-wall/rail with ≥0.8 m clear in front of rack, rack against wall/niche on plinth, ≥2 supporting props. Mood (exterior cool vs interior spill; bay worn; loft cleaner; rack Emission) and palette CLAIM stand. Full V1 coverage while authoring. Capture stems annex-01…08 unchanged.
