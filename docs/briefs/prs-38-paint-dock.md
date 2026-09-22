# Paint workspace — left dock must not sit under the viewport

**Owner:** Design → Eng · **Product:** Joshua · **Date:** 2026-09-20  
**Evidence:** https://github.com/joshocalico/slab-modeller/blob/2e005dec84b22b321779642ca084905895ae40a8/website/public/img/panel-pixel-paint.png (pre-hold tip; shows occlusion)
**Linear:** [PRS-38](https://linear.app/joshsteele/issue/PRS-38)

## Problem

In Paint workspace the 2D canvas/viewport draws over the left paint dock. Flatten, brush Color / Radius / Opacity, and nearby fields are half-cut. The dock is not usable.

## Done when

1. Paint left dock is fully visible beside the canvas. No overlap. Flatten and brush fields are complete and clickable.
2. UV workspace stays correct (no regression of Mapping / Pack / Fit UV).
3. Modelling dock (Object / Soft Select / Op Card) stays correct.
4. Design recaptures `panel-pixel-paint.png` after Eng lands the fix. Docs how-to keeps the prior bleeding figure until then.

## How to try

1. Open Signal Foundry. Select MaintenanceBayRoof. Face mode. Enter Paint workspace.
2. Confirm Flatten and the brush column (Color, Radius, Opacity) are fully visible to the left of the canvas.
3. Switch UV ↔ Paint a few times. Resize the editor window. Dock and canvas still do not overlap.
4. Exit Paint. Soft Select / Extrude Op Card still lay out as before.

## Notes

- Prefer a layout constraint (canvas starts after dock width), not a wider default window.
- Capture crop must include the full dock; do not crop the occlusion into the docs figure.
- Rank: near-term chrome bug. Docs #35 shipped without the bad paint PNG.

## Out of scope

Paint layers / channels (Should #7 / #7b). Gizmo ownership (Should #5).
