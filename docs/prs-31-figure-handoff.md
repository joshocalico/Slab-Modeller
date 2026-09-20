# PRS-31 figure handoff (Create strip + Op Card)

Branch expects binaries at:

- `website/public/img/panel-object.png`
- `website/public/img/panel-preview.png`
- `website/public/img/panel.png`

**Staged on the shared box** (CoS / Design with disk access):

- `/workspace/slab-ux/prs-31-docs/panel-object.png` (844×353, Box Create strip)
- `/workspace/slab-ux/prs-31-docs/panel-preview.png` (844×300, Extrude Op Card Cancel|Apply)
- `/workspace/slab-ux/prs-31-docs/panel.png` (same Op Card crop)
- `*.png.b64` beside each for decode-if-needed
- Inventory: `/workspace/slab-ux/prs-31-docs/FIGURES.md`

Capture: `project/tests/design_prs31_chrome_capture.gd` (this PR) · tip `d414024` · DISPLAY=:5 · failures=0

```bash
cp /workspace/slab-ux/prs-31-docs/panel-{object,preview,}.png website/public/img/
# or: base64 -d panel-object.png.b64 > website/public/img/panel-object.png
```
