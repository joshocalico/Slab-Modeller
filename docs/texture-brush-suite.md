# Object auto unwrap and texture brushes

Worklog, 26 September 2026.

The current changes add **Auto Unwrap Object** in Object mode and UV Mapping. It unwraps and packs all faces while retaining mode and selection. Existing seams and pins constrain the atlas; pin conflicts and atlas overflow refuse without modifying geometry.

The texture brush menu now exposes Paint, Erase, Airbrush, Blur, Smudge, Clone, Stamp, Fill, Gradient, and Eyedropper. Controls include airbrush flow, spacing as a fraction of diameter, fill tolerance, gradient end color, and built-in or PNG stamps. Sampling and clone-source selection bypass painting history. Blur, Smudge, and Clone read the visible composite and write to the active layer.

The two existing how-to pages document these workflows. Focused tests passed: 75 auto-unwrap checks, 42 brush raster checks, and the brush controller workflow smoke. The controller tests cover pixel changes, masks, source isolation, stationary airbrush, and exact Undo/Redo/cancel restoration.

Native Godot acceptance covered whole-object selection, safe atlas-overflow refusal, successful packed unwrap, Make Unique, drawing, Gradient, Smudge, Clone source picking, and Undo. The Object toolbar now exposes Auto Unwrap Object, and Clone has a visible Pick source button as well as Alt-click.

The docs verifier passed with 29 pages, 95 local references, and zero failures. The website production build passed.

The full `scripts/slab-verify` run passed the kernel (190 tests, 6330 checks), brush tests, rendered editor workflows, and gameplay checks. It initially failed two UI gates: the panel inventory needed the new action, and the new controls needed a font declaration and distinct icon. After those corrections, both `panel_smoke` and `chrome_smoke` passed on a focused rerun (43 chrome cases).

Validation commands:

```sh
scripts/slab-docs-verify
cd website
npm run build
```

The recovery scene belongs to the user and must not be included in a checkpoint commit.
