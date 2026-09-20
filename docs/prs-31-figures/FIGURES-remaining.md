# PRS-31 docs figures — remaining chrome (follow-up)

**Tip base:** bleeding after #34 · **Captured:** 2026-09-20 ~21:25 ACST · **Display:** `:5`  
**PR:** https://github.com/joshocalico/slab-modeller/pull/35 (`josh/prs-31-remaining-chrome` → bleeding)

**Capture script:** `project/tests/design_prs31_chrome_capture.gd`

## Ship these

| File | What | MDX |
| --- | --- | --- |
| `panel-export.png` | Object dock Export… | `prepare-a-solid-for-runtime` |
| `panel-external.png` | External badge + disabled V/E/F + Promote | `promote-an-external-mesh` |
| `panel-soft-select.png` | Soft Select on, Radius 2.5, Smooth | `select-in-the-view` |
| `panel-material-uv.png` | Mapping Unwrap\|Pack + Fit UV | `reference/panel` |

## Hold

`panel-pixel-paint.png` — Paint left dock occluded under canvas (Joshua). Keep bleeding's prior figure. Eng layout fix + Design recapture. Brief: `/workspace/slab-ux/paint-dock-occlusion-brief.md`.

## Restore paint binary off this PR (CoS land — MCP mangles PNG)

```bash
git checkout bleeding -- website/public/img/panel-pixel-paint.png
git commit -m "docs(PRS-31): drop occluded panel-pixel-paint from #35"
git push
```

## Skipped

Promote 01–03 (no drift) · `panel-surface-paint.png` (UV duplicate)

## Out of scope

Face Isolation (PRS-33) · Create/Op Card (PR #33) · Paint dock occlusion (separate product PR)
