# PRS-31 remaining chrome figures — CoS handoff

Branch: `josh/prs-31-remaining-chrome` → bleeding  
Linear: [PRS-31](https://linear.app/joshsteele/issue/PRS-31)  
PR: https://github.com/joshocalico/slab-modeller/pull/35

## Ship

Soft Select · Export · External · `panel-material-uv` · capture script.

## Hold — restore bleeding paint binary before squash

```bash
git checkout bleeding -- website/public/img/panel-pixel-paint.png
git commit -m "docs(PRS-31): drop occluded panel-pixel-paint from #35"
git push
```

Paint dock occlusion is a separate Eng product PR. Design recaptures after.

## Out of scope

Face Isolation (PRS-33) · Create/Op Card (#33) · Promote 01–03 · `panel-surface-paint.png`
