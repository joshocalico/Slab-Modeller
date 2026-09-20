# PRS-31 docs figures — remaining chrome (follow-up)

**Tip base:** bleeding after PR #33 · **Captured:** 2026-09-20 ~21:25 ACST · **Display:** `:5`  
**PR:** https://github.com/joshocalico/slab-modeller/pull/35 (`josh/prs-31-remaining-chrome` → bleeding)

**Capture script (box → CoS land):** `/workspace/slab-modeller/project/tests/design_prs31_chrome_capture.gd`  
`DISPLAY=:5 scripts/godot --editor --path project --quit-after 300 --script res://tests/design_prs31_chrome_capture.gd`

## Ship these (CoS binary land)

| File | Size | SHA256 (12) | What | MDX |
| --- | --- | --- | --- | --- |
| `panel-export.png` | 1280×719 | `4be7794d677e` | Object dock **Export…** (OBJ/STL/FBX filters verified; dialog outside compositor) | `prepare-a-solid-for-runtime` |
| `panel-external.png` | 844×353 | `da3aad69c2dc` | External badge + disabled V/E/F + Promote | `promote-an-external-mesh` |
| `panel-soft-select.png` | 844×300 | `62fe97233ae1` | Soft Select on, Radius 2.5, Smooth | `select-in-the-view` |
| `panel-material-uv.png` | 844×300 | `602c46536b0b` | Mapping Unwrap\|Pack + Fit UV | `reference/panel` |
| `panel-pixel-paint.png` | 923×336 | `3ee5b2493782` | Paint workspace + brush column | `paint-texture-pixels` |

## Skipped

Promote 01–03 (no drift) · `panel-surface-paint.png` (UV duplicate) · pack-02 (already on bleeding)

## CoS one-liner

```bash
cp /workspace/slab-ux/prs-31-docs/panel-{export,external,soft-select,material-uv,pixel-paint}.png website/public/img/
cp /workspace/slab-modeller/project/tests/design_prs31_chrome_capture.gd project/tests/
git add website/public/img/panel-{export,external,soft-select,material-uv,pixel-paint}.png project/tests/design_prs31_chrome_capture.gd
git commit -m "docs(PRS-31): remaining chrome figure binaries + capture script" && git push
```

## Out of scope

Face Isolation (PRS-33) · Create/Op Card (PR #33)
