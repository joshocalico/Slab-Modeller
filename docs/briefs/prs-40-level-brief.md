# PRS-40 level brief: Signal Relay Annex (craft bar)

**Audience:** QA (run) · Design (massing + surfaces + capture) · CoS (kick + report) · Eng (fixes)
**Authors:** Product with Design (massing/surfaces) and QA (pass criteria)
**Date:** 2026-09-21 (ACST)
**Linear:** [PRS-40](https://linear.app/joshsteele/issue/PRS-40)
**Related:** [PRS-38](https://linear.app/joshsteele/issue/PRS-38) paint dock · [PRS-39](https://linear.app/joshsteele/issue/PRS-39) Promote chrome
**Status:** Product+Design locked 2026-09-21. Craft bar raised after Joshua rejected PR #39. Texture + full V1 coverage included. Hold QA until CoS re-kicks.

**Source of record:** this file in the repo (`docs/briefs/prs-40-level-brief.md` on `bleeding`). Also on Linear PRS-40. Box `/workspace` copies are mirrors only.

## Why this revision

Joshua rejected the Annex on PR #39 as not a true level. CoS agrees: thin slabs, no place. He also asked for texture (not bare grey) and for the rebuild to test the whole shipped V1 product while authoring the place. This brief raises place craft, surface craft, and coverage. Do not merge #39 as Done for PRS-40.

## Goal

Build one small authored interior on bleeding the way a level author would, and use that build as a full product audit of major shipped V1 surfaces. `scripts/slab-verify` green is required but not enough. File every real product failure as a Bug with How to try it and media before calling the audit Done.

Care bar: How to try it stays honest. Do not mark docs figures Done when they show broken chrome.

Tutorial fodder: same build is later tutorial clips. One path. Not a second authored level. Note clip moments during the audit. Design films after Bugs clear.

## Craft bar (Done when)

All of these must hold. Solid count may go past 12 if craft needs it. Stop optimizing for an 8–12 solid budget.

### Place

1. Enclosed volume with a ceiling that closes the room. Not open sky over floating plates.
2. Entrance or doorway with wall thickness. Opening about 1.0 m wide by 2.1 m tall. Jambs and wall depth at least 0.25 m. Not a hole in a wafer.
3. Clear circulation from entrance to the raised area. Floors thick enough to stand on (about 0.15–0.25 m). No floating thin plates.
4. Stairs or stepped solid that climb to a platform you can stand on. Platform height about 1.0–1.25 m. Treads deep enough for a player-ish footfall.
5. Walkable scale. Outer shell about 8×6×3.5 m (W×D×H) unless Design locks different dims.
6. Relay rack prop that reads as equipment. Tall cabinet massing about 0.6×0.4×1.8 m (or Design-locked alternate). Extrude, Inset, Bevel, Loop, plus Soft Select on a bezel or panel. Not a random 1.2 m cube.
7. Two readable zones: entry bay and raised relay loft, connected by the stairs.

Fail place craft if the scene looks like a tool demo: paper-thin walls, missing ceiling, wafer stairs, or a cube labeled as the relay.

### Texture

8. Floor, walls, ceiling, and the relay prop are not left default grey. Each gets intentional albedo (paint or materials) so the annex reads as a finished place in a still.
9. Roughness and/or Emission used where it helps the place read (at least one non-albedo channel on the rack or loft wall).
10. annex-06 paint beat shows surface work on the level in frame (rack or architectural face with real strokes / Flatten commit). Not a single dab on a blank white canvas with no place context.
11. UV Unwrap + Pack + Fit precede paint on painted solids so islands are honest.

### Full V1 coverage (test the product while building the place)

Building the Annex is a full product audit. Exercise every major shipped V1 surface while authoring the place. Do not run a thin create→topo→paint strip and call it Done.

Cover at least (use where craft needs them; invent nothing that is not on bleeding):

* Create strip: Box plus at least one other shape the space needs (Stair and/or Cylinder/Arch/Plane as craft requires).
* Object ops that fit the place: Mirror and/or Array if useful; boolean Subtract or Union if a doorway or bay needs it. Op Card Apply/Cancel where those ops use it.
* Vertex / Edge / Face topo: Extrude, Inset, Bevel, Loop, plus Connect or Dissolve if used naturally.
* Soft Select with visible falloff.
* Solid Isolate and Face Isolate (Faces path). Esc exits Faces without clearing Soft Select.
* UV workspace: Unwrap, Pack (distinct from Unwrap), Fit, and element select (Vert/Edge/Face) if shipped.
* Paint: Albedo, Roughness, Emission, layers if shipped, Flatten that commits. Dock fully visible.
* Export: OBJ at minimum. Also STL and/or FBX if on bleeding (honest filters).
* External import + Promote (External-only chrome).
* Save / reopen editable with collision on.

If a shipped major surface cannot be hit honestly in this level, name it in the QA report as a coverage gap. Do not fake coverage.

## Level: Signal Relay Annex

One enclosed annex. Fresh `Node3D` scene or Signal Foundry if free. Not a full map. Not a second tutorial set piece.

### Pass when the annex exists

1. Outer shell with floor, walls, and ceiling. Wall thickness at least 0.25 m. Ceiling closes the volume. Surfaces not default grey.
2. Doorway entrance with thickness. Readable from outside and inside.
3. Entry bay floor + raised loft platform with stairs you can climb and stand on.
4. Create strip used for Box and at least one other needed shape (e.g. Stair).
5. At least one Object op that fits (Mirror, Array, or boolean) with honest Apply/Cancel if Op Card applies.
6. Relay rack with Extrude, Inset, Bevel, Loop, Soft Select falloff. Connect/Dissolve if natural.
7. Solid Isolate once and Face Isolate once.
8. UV Unwrap + Pack + Fit (+ element select if shipped) on painted solids.
9. Paint with intentional albedo on architecture and prop; at least one other channel; Flatten commits. Dock visible.
10. Export OBJ; also STL or FBX if on tip. Solid unchanged after export.
11. Import External. Badge on. V/E/F off. Promote External-only. Success unlocks V/E/F or refuse leaves External intact.
12. Save, reopen, editable, collision on.

### Must be in / out

Must be in: craft bar place + texture + full V1 coverage above; live dock checks; stills annex-01…08 with the textured place in frame.

Must be out: greybox tool demos; bare grey slabs; thin floating plates; full PowerHouse map; keybind deep dive; Weld as required; filming finished tutorials during the audit; a second tutorial-only level; optimizing solid count under craft needs; fake tool hits.

### Tools that must be touched

| Area | Must hit | Skip only if |
| --- | --- | --- |
| Create | Box + ≥1 other needed shape | never |
| Object | Mirror and/or Array and/or boolean as craft needs; Op Card honest | never leave all unused |
| Topo | Extrude, Inset, Bevel, Loop; Connect/Dissolve if natural | never |
| Soft Select | On, radius, falloff visible | never |
| Isolate | Solid Isolate + Face Isolate | never |
| UV | Unwrap, Pack, Fit; element select if shipped | never |
| Paint | Albedo + ≥1 other channel; Flatten commit; dock visible | never |
| Share | Export OBJ (+ STL/FBX if on tip); Import; Promote | never |
| Persist | Save + reopen | never |

## Clip moments (same build)

| Beat | Stem | What to show |
| --- | --- | --- |
| 1 | `annex-01-create` | Shell + thick doorway; non-grey start if materials already applied |
| 2 | `annex-02-topo` | Stairs / loft / Extrude Apply; Object op if used here |
| 3 | `annex-03-soft-select` | Soft Select falloff on the relay rack |
| 4 | `annex-04-face-isolate` | Face Isolate; Solid Isolate may share beat |
| 5 | `annex-05-uv-pack` | Unwrap then Pack, Fit, element strip if shipped |
| 6 | `annex-06-paint` | Textured place in frame; Flatten commit; dock visible |
| 7 | `annex-07-export` | Export OBJ (+ second format if on tip) |
| 8 | `annex-08-external-promote` | Import, badge, Promote External-only |

Product locks titles/captions after the rebuild audit report. Design capture plan follows these stems. Stills must show the textured place, not chrome-only crops.

## Pass criteria (QA owns)

Audit PASS only when all of:

1. Place craft bar met. Scene reads as a place on a still without a caption.
2. Texture craft bar met. Not default grey. annex-06 shows intentional surface work on the level.
3. Full V1 coverage met, or every miss listed as a named coverage gap in the CoS report.
4. Level steps complete without a workaround that hides a Bug.
5. Live chrome honest (paint dock, Promote External-only, Op Card, Isolate Esc).
6. Soft Select falloff visible. Pack is not Unwrap.
7. Export non-destructive. External tools disabled until Promote succeeds.
8. Save → reopen → editable + collision on.
9. Every real failure has a Linear Bug with How to try it + media.
10. `scripts/slab-verify` EXIT=0 on the same tip. Green alone does not pass.

Evidence on Linear PRS-40 (or linked PR): GATE.md, craft stills (place + texture), coverage checklist, clip-moment list, Bug ids, slab-verify log. No box-only SoR.

## Bug filing rule (QA owns)

* Bug: wrong shipped behavior; layout/chrome; bad refuse/success; Undo/save/reopen break; docs figure showing broken chrome as Done.
* Improvement: harness debt, weak smoke, copy, later breadth.
* File as you go. How to try it + media when chrome. No silent batch notes.
* Do not re-open PRS-38 / PRS-39 if tip is fixed. New Bug only if still broken.
* Do not close the audit while known blockers lack Bugs.

## Preconditions (CoS re-kick)

Hold rebuild until CoS re-kicks after this brief is Product+Design locked on bleeding. PRS-38 / PRS-39 stay Done.

## Report back to CoS

* Tip SHA
* Craft bar place: pass / fail
* Texture: pass / fail
* Coverage: pass / gaps named
* Level steps: yes / partial
* Bugs filed
* Clip moments noted
* `scripts/slab-verify` EXIT

No merge authority from QA. Do not call PRS-40 Done on a greybox or bare-grey annex.

## Owners

* Product: this brief, craft + coverage bar, later tutorial title/caption lock
* Design: massing CLAIM, surface notes, capture stills with textured place in frame
* QA: execute rebuild, evidence on Linear, Bugs, CoS report
* Eng: fix filed Bugs
* CoS: re-kick when brief locked; receive report

## Notes

Rank: rebuild after Joshua reject of PR #39. Prior greybox brief superseded. Design CLAIMED massing (entrance → entry bay → stair/platform → relay loft) and surface intent (floor / walls+ceiling / loft deck / rack painted or materialled). Capture stems annex-01…08 unchanged.
