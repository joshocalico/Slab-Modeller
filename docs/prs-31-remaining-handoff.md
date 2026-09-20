# PRS-31 remaining chrome figures — CoS handoff

Branch: `josh/prs-31-remaining-chrome` → bleeding  
Linear: [PRS-31](https://linear.app/joshsteele/issue/PRS-31)  
PR: https://github.com/joshocalico/slab-modeller/pull/35

## CoS binary land (MCP mangles PNGs)

```bash
cp /workspace/slab-ux/prs-31-docs/panel-{export,external,soft-select,material-uv,pixel-paint}.png website/public/img/
cp /workspace/slab-modeller/project/tests/design_prs31_chrome_capture.gd project/tests/
git add website/public/img/panel-{export,external,soft-select,material-uv,pixel-paint}.png \
        project/tests/design_prs31_chrome_capture.gd
git commit -m "docs(PRS-31): remaining chrome figure binaries + capture script"
git push
```

Staged: `/workspace/slab-ux/prs-31-docs/` (+ `.b64`).  
Capture script on box: `/workspace/slab-modeller/project/tests/design_prs31_chrome_capture.gd`.

## Text on this PR

- MDX: Soft Select · Export · External live chrome
- Promote stills skipped (no drift)
- `panel-surface-paint.png` not refreshed (UV duplicate)

## Out of scope

Face Isolation (PRS-33) · Create/Op Card (PR #33)
