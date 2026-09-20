# PRS-40 level brief: Signal Relay Annex

**Audience:** QA (run) · Design (capture moments) · CoS (kick + report) · Eng (fixes)
**Authors:** Product with QA
**Date:** 2026-09-20 (ACST)
**Linear:** [PRS-40](https://linear.app/joshsteele/issue/PRS-40)
**Related:** [PRS-38](https://linear.app/joshsteele/issue/PRS-38) paint dock · [PRS-39](https://linear.app/joshsteele/issue/PRS-39) Promote chrome
**Status:** Product-locked 2026-09-20. Dual use: QA audit path and later tutorial clips (same build). Ready for CoS kick after PRS-38 + PRS-39 clear.

Canonical copy: this file in the repo (`docs/briefs/prs-40-level-brief.md`). Also attached on Linear PRS-40.

## Goal

Build one small real level on bleeding the way an author would. `scripts/slab-verify` green is required but not enough. File every real product failure as a Bug with How to try it and media before calling the audit Done.

Care bar (Joshua via CoS): How to try it stays honest. Do not mark docs figures Done when they show broken chrome.

Tutorial fodder (Joshua via CoS): same build is later tutorial clips. One path. Not a second authored level. During the audit, note clip moments below. Design captures after Bugs clear. Do not film until chrome Bugs are fixed.

## Level: Signal Relay Annex

One enclosed annex. About 8 to 12 solids. Fresh `Node3D` scene or Signal Foundry if free. Not a full map. Not a second tutorial set piece.

### Pass when the annex exists

1. Floor, walls, ceiling, one doorway, one raised platform or stair.
2. One prop solid with Extrude, Inset, Bevel, and one Loop cut.
3. Soft Select once on a vertex or edge ring so neighbors visibly follow falloff.
4. Face Isolate once (PRS-33 on bleeding). Solids|Faces. Esc exits Faces without clearing Soft Select. Other solids stay.
5. UV Unwrap + Pack + Fit on at least one solid (PRS-29 Pack on bleeding). Pack is not Unwrap. Overflow refuse if triggered.
6. Paint on one face: Albedo stroke, brief Roughness and Emission, Flatten that commits (overlay present). Dock fully visible beside the canvas.
7. Export a solid as Wavefront OBJ (optional second: FBX). File lands. Solid unchanged after export.
8. Import that OBJ (or any closed External). External badge on. Vertex/Edge/Face off.
9. Promote once. Hidden on SlabSolid (PRS-39). Present only for one External. No ellipsis once PRS-39 lands. Success unlocks V/E/F, or refuse leaves External intact.
10. Save scene, reopen, solids still editable, collision still on.

When the audit ends, the scene has floor, walls, ceiling, doorway, platform/stair, prop, and the promoted solid (or a clear Promote refuse with External intact).

### Must be in

* Create strip, Extrude Apply/Cancel, Inset, Bevel, Loop
* Soft Select with visible neighbor falloff (not toggle-only)
* Face Isolate (Faces path) + Soft Select coexistence + Esc
* UV: Unwrap, Pack (distinct), Fit frames only
* Paint: channels, Flatten, dock not under canvas
* Export OBJ, Import Mesh, External badge, Promote External-only
* Save / reopen editable
* Live visual check of docks (occlusion / cut controls = Bug)

### Must be out (this pass)

* Full PowerHouse / playable map
* Keybind profile remapping deep dive
* Weld/Collapse as a required step (optional if natural)
* New topology tools not claimed shipped
* glTF, overlapping CSG, UV sculpt
* Docs figure recapture (Design after Eng fixes)
* Re-running every Phase C smoke in isolation
* Filming tutorials during the audit (note moments only)
* A second tutorial-only level

### Tools that must be touched

| Step | Tool / chrome | Skip only if |
| --- | --- | --- |
| Create | Object Create strip | never |
| Topo | Extrude Apply, Inset, Bevel, Loop | never |
| Soft Select | On, radius, move with falloff | never |
| Face Isolate | Solids\|Faces chrome | never (on bleeding) |
| UV | Unwrap, Pack, Fit | never (Pack on bleeding) |
| Paint | Paint workspace, channels, Flatten | never |
| Share | Export OBJ, Import Mesh, Promote | never |
| Persist | Save + reopen | never |

Do not skip a tool that claims to ship. Prefer a short refuse with a Bug over a silent skip.

## Clip moments (same build; note during audit; Design films later)

| Beat | Stem candidate | What to show |
| --- | --- | --- |
| 1 | `annex-01-create` | Floor + walls from Create strip |
| 2 | `annex-02-topo` | Doorway / Extrude Apply / Bevel or Loop |
| 3 | `annex-03-soft-select` | Soft Select falloff on the prop |
| 4 | `annex-04-face-isolate` | Face Isolate Faces, Esc keeps Soft Select |
| 5 | `annex-05-uv-pack` | Unwrap then Pack (show they differ), Fit |
| 6 | `annex-06-paint` | Paint + Flatten commit, dock fully visible |
| 7 | `annex-07-export` | Export OBJ + honest format |
| 8 | `annex-08-external-promote` | Import, badge, Promote External-only |

Product locks titles/captions after the audit report (PRS-37 style). Clips do not block the audit.

Design capture plan: stills during audit; film after Bugs clear. Clip stems `annex-01`…`annex-08` above.

## Pass criteria (QA owns)

Audit PASS only when all of:

1. Level steps 1–10 complete without a workaround that hides a Bug.
2. Live chrome: no dock occlusion, cut controls, or wrong visibility on Create / Soft Select / Isolate / UV / Paint / Object Export-Promote. Paint dock fully visible (PRS-38 fixed, or filed again if still broken).
3. Promote absent unless exactly one External is selected; label has no ellipsis after PRS-39 (or filed again if still wrong).
4. Soft Select falloff is visible in the edit (not toggle-only). Pack is not Unwrap. Face Isolate Esc does not clear Soft Select.
5. Export non-destructive. External tools stay disabled until Promote succeeds.
6. Save → reopen → editable + collision on for built solids.
7. Every real failure already has a Linear Bug with How to try it + media (screenshot/clip when chrome).
8. Full `scripts/slab-verify` EXIT=0 on the same tip used for the build. Green alone does not pass.

Audit FAIL (or partial) if any required step blocks, chrome is broken, or a known fail lacks a Bug. Partial reports list which steps passed and Bug links for the rest.

Evidence: attach GATE.md, scene notes, clip-moment list, Bug ids, and slab-verify log on the Linear PRS-40 comment (or a linked gist/PR). Do not rely on a box-only folder.

## Bug filing rule (QA owns)

* Bug: wrong shipped behavior; layout/chrome (occlusion, cut controls, false affordance, wrong visibility); refuse that should succeed; success that should refuse; Undo/save/reopen break; docs figure that shows broken chrome as Done.
* Improvement: harness debt, missing or weak smoke, nicer copy, later breadth, optional polish that is not encoding a product bug.
* File as you go. How to try it required. Prefer screenshot or clip when product chrome is involved (blob links). No silent batch notes.
* Do not re-open PRS-38 / PRS-39 if already fixed on the tip under test. Repro and file a new Bug only if the fail still reproduces.
* Do not close the audit while known blockers lack Linear Bugs.
* Product vs harness split stays sharp in every report.

## Preconditions (CoS kick)

Do not start until CoS names this cycle clear enough, including at least:

* Docs remaining chrome (PRS-31 / #35), landed @ `959f754`
* Promote chrome hide (PRS-39)
* Paint dock fix (PRS-38)
* Any other V1/roadmap items CoS lists

If CoS kicks with known open Bugs, the level still runs. Those Bugs stay open until fixed. The audit does not paper over them.

## Report back to CoS

Short note only:

* Tip SHA under test
* Level completed: yes / partial (which steps)
* Passed
* Failed (with Bug links)
* Clip moments noted (path worth filming: yes/no + list)
* `scripts/slab-verify` EXIT

No merge authority from QA.

## Owners

* Product: this brief, what "small real level" means, later tutorial title/caption lock
* QA: execute, evidence on Linear PRS-40, Bugs, CoS report
* Design: chrome consult + capture moments on this same build
* Eng: fix filed Bugs
* CoS: kick when clear; receive report

## Notes

Rank: after current roadmap clears. Level name is Signal Relay Annex (Product CLAIM over earlier Maintenance Bay shelf draft). QA co-signed pass criteria and Bug rule folded in 2026-09-20.
