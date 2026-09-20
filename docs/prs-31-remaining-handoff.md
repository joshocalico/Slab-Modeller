# PRS-31 remaining chrome figures — CoS handoff

Branch: `josh/prs-31-remaining-chrome` → bleeding  
Linear: [PRS-31](https://linear.app/joshsteele/issue/PRS-31)

## CoS binary land (MCP mangles PNGs)

```bash
cp /workspace/slab-ux/prs-31-docs/panel-{export,external,soft-select,material-uv,pixel-paint}.png website/public/img/
git add website/public/img/panel-{export,external,soft-select,material-uv,pixel-paint}.png
git commit -m "docs(PRS-31): remaining chrome figure binaries"
git push
```

Staged with FIGURES.md + `.b64` at `/workspace/slab-ux/prs-31-docs/`.

## Text on this PR

- Extended `project/tests/design_prs31_chrome_capture.gd`
- MDX figure wires + Pack caption on panel Material/UV
- Promote stills skipped (no chrome drift)
- `panel-surface-paint.png` not refreshed (would duplicate UV Mapping)

## Out of scope

Face Isolation teach copy · Create/Op Card (PR #33 merged)
