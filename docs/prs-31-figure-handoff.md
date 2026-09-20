# PRS-31 figure handoff (Create strip + Op Card)

## Destination (same paths → MDX keeps working)

- `website/public/img/panel-object.png` — Object **Create strip** (Box + Width/Height/Depth + Create)
- `website/public/img/panel-preview.png` — Face **Extrude Op Card** (Distance, Cancel | yellow Apply)
- `website/public/img/panel.png` — same Op Card crop (hero alt already describes Extrude)

## Staged on the shared box (CoS / Design)

```
/workspace/slab-ux/prs-31-docs/panel-object.png   # 844×353  sha256:9c3db0bcf9db…
/workspace/slab-ux/prs-31-docs/panel-preview.png  # 844×300  sha256:acd1030689b1…
/workspace/slab-ux/prs-31-docs/panel.png          # 844×300  (same bytes as preview)
/workspace/slab-ux/prs-31-docs/*.png.b64
/workspace/slab-ux/prs-31-docs/FIGURES.md
```

```bash
cp /workspace/slab-ux/prs-31-docs/panel-{object,preview,}.png website/public/img/
git add website/public/img/panel-{object,preview,}.png
git commit -m "docs(PRS-31): Create strip + Op Card figure binaries"
git push
```

GitHub MCP from this agent cannot land binary PNGs (UTF-8 mangling). Text capture script is on the branch.

## Capture

`project/tests/design_prs31_chrome_capture.gd`  
`DISPLAY=:5 scripts/godot --editor --path project --quit-after 120 --script res://tests/design_prs31_chrome_capture.gd`  
Tip `d414024` · failures=0 · panel `get_global_rect()` crop

## Still open

Export · External · Soft Select · UV+Pack (`panel-material-uv.png`) · Paint · Promote refresh-if-drifted
