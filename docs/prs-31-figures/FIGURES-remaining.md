# PRS-31 docs figures — remaining chrome (follow-up)

**Tip base:** bleeding after PR #33 merge (`c98fee0`) · **Captured:** 2026-09-20 ~21:25 ACST · **Display:** `:5` Godot 4.7.2  
**Branch / PR:** `josh/prs-31-remaining-chrome` → bleeding (not PR #33)

**Capture script:** `project/tests/design_prs31_chrome_capture.gd`  
`DISPLAY=:5 scripts/godot --editor --path project --quit-after 300 --script res://tests/design_prs31_chrome_capture.gd`

## Ship these (CoS binary land)

| File | Size | SHA256 (12) | What | MDX |
| --- | --- | --- | --- | --- |
| `panel-export.png` | 1280×719 | `4be7794d677e` | Object dock with **Export…** visible. Filters verified OBJ/STL/FBX (EditorFileDialog is outside viewport compositor — dock chrome is the honest still). | `guide/how-to/prepare-a-solid-for-runtime` |
| `panel-external.png` | 844×353 | `da3aad69c2dc` | External badge `box (External mesh)`, disabled V/E/F, **Promote to Slab Solid…** enabled, Export/Import available | `guide/how-to/promote-an-external-mesh` (live chrome beside promote-01) |
| `panel-soft-select.png` | 844×300 | `62fe97233ae1` | Vertex mode, Soft Select on, Radius 2.5, Falloff Smooth | `guide/how-to/select-in-the-view` |
| `panel-material-uv.png` | 844×300 | `602c46536b0b` | UV workspace Mapping: **Unwrap \| Pack** + canvas **Fit UV** (Pack gap fix) | `guide/reference/panel` |
| `panel-pixel-paint.png` | 923×336 | `3ee5b2493782` | Paint workspace gold + brush column (Color / Radius / Opacity) on MaintenanceBayRoof | `guide/how-to/paint-texture-pixels` |

## Optional / already on bleeding

| File | Notes |
| --- | --- |
| `pack-02-overflow-refuse.png` | Already on bleeding from PRS-29; staged copy for convenience. |
| `promote-01/02/03.png` | **Skipped** — chrome not drifted vs phase-c mocks on bleeding. |
| `panel-surface-paint.png` | **Skipped refresh** — would duplicate UV Mapping crop; keep bleeding asset. |

## Staged paths

- Binaries + b64: `/workspace/slab-ux/prs-31-docs/`
- Repo destination: `website/public/img/<same-name>`
- MCP cannot push PNG binaries — CoS copies from the box.

## CoS one-liner

```bash
cp /workspace/slab-ux/prs-31-docs/panel-{export,external,soft-select,material-uv,pixel-paint}.png website/public/img/
git add website/public/img/panel-{export,external,soft-select,material-uv,pixel-paint}.png
git commit -m "docs(PRS-31): remaining chrome figure binaries"
git push
```

## Out of scope

Face Isolation (PRS-33) teach copy · Canva brand board · Create strip / Op Card (PR #33)
