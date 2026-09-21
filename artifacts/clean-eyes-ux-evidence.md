# Design clean-eyes UX evidence (no verdict)

Read-only gather for Design’s PASS/HOLD on [bleeding→main PR #47](https://github.com/joshocalico/slab-modeller/pull/47).

**Tip:** [`16422939edafeb2fb9cfba85321921d0fae164f3`](https://github.com/joshocalico/slab-modeller/commit/16422939edafeb2fb9cfba85321921d0fae164f3) (`bleeding`)  
**Message:** `demo: Signal Relay Annex v3.1 surface pass (PRS-40)`  
**Method:** source + committed stills + MDX grep. **Godot was not run.** `GODOT` unset; `scripts/godot` only looks for `/Applications/Godot.app` and exits 127. No stranger-test recapture from this box.

Blob paths below are at that SHA. Severity is a guess for Design, not a verdict.

---

## 1. Chrome code honesty

### Promote — hide unless one External; no ellipsis

**Guess: code matches the lock. Shipped docs figures do not.**

- Label constant has no dots: `PROMOTE_LABEL := "Promote to Slab Solid"`  
  [`project/addons/slab/slab_actions.gd:12`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_actions.gd#L12)
- Visibility is Object + exactly one External, not “disabled but present”:

```338:349:project/addons/slab/slab_actions.gd
func promote_visible() -> bool:
	if _selection.mode != SlabSelection.Mode.OBJECT:
		return false
	return _selection.has_only_external_meshes() and _selection.count() == 1


func _row_visible_in_mode(row: Dictionary, mode: int) -> bool:
	if not row["modes"].has(mode):
		return false
	if str(row.get("id", "")) == "promote_to_solid":
		return promote_visible()
	return true
```

- Command catalog uses that label ([L1040](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_actions.gd#L1040)). Import/Export keep `...`.
- Smokes lock hide + no ellipsis: [`project/tests/promote_smoke.gd:37-82`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/tests/promote_smoke.gd#L37) (empty / SlabSolid / two Externals → button absent; one External → `Promote to Slab Solid`, enabled).
- Committed annex stills agree with code, not with older docs crops:
  - [`project/demo/signal_relay_annex/media/annex-08-external-promote.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-08-external-promote.png) — one External (`ImportedRack`); Promote **without** dots; V/E/F off.
  - [`…/annex-01-create.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-01-create.png), [`…/annex-07-export.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-07-export.png) — SlabSolid(s) selected; Promote **absent**.

How-to copy is already honest ([`website/app/guide/how-to/promote-an-external-mesh/page.mdx:7`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/promote-an-external-mesh/page.mdx#L7): “appears only when… hidden for a SlabSolid”). The **figures on that page** are not. See §4.

### Paint dock — left column not under the canvas (PRS-38)

**Guess: layout code + recaptured figure look Done. Did not click it live.**

- Split is inspector then canvas; comment names the old overflow:

```1312:1325:project/addons/slab/slab_panel.gd
	var split := HBoxContainer.new()
	split.name = "PaintWorkspaceSplit"
	...
	inspector_scroll.custom_minimum_size.x = _scaled(UV_DOCK_MIN_WIDTH)
	...
	# Size the dock to its fields. SHOW_NEVER let Flatten / brush overflow under the canvas.
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
```

- Dock width grows to Flatten / Color / Radius / Opacity + gutter: [`_paint_left_dock_width` L409–423](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_panel.gd#L409), applied at [L426–433](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_panel.gd#L426) and again in workspace refresh (~L2097).
- Constants: `PAINT_DOCK_MIN_WIDTH := 220`, `PAINT_DOCK_GUTTER := 8` ([L29–31](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_panel.gd#L29)).
- Smokes: [`project/tests/chrome_smoke.gd`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/tests/chrome_smoke.gd) ~L471–610, `_expect_paint_dock_clear_of_canvas` ~L1373.
- Recapture landed in `3d07f23` (`docs: Paint dock figure + Promote label`): [`website/public/img/panel-pixel-paint.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-pixel-paint.png) **852×336**. Flatten, brush color bar, Radius 8, Opacity 1.0 sit **left of** a teal canvas. Not the occluded pre-hold crop cited in [PRS-38](https://linear.app/joshsteele/issue/PRS-38) (`2e005dec…/panel-pixel-paint.png`).
- Annex paint still: [`…/annex-06-paint.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-06-paint.png) — same dock pattern, Flatten + Color/Radius/Opacity complete, canvas is filled amber/black blocks.

Unknown: window-resize / UV↔Paint flicker. Not exercised here.

### Create strip + Op Card (Extrude / Inset / Bevel)

**Guess: present in code and in live annex / Op Card crops. No annex still of an *active* Op Card.**

- Create strip: [`_build_create_strip` L1172–1190](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_panel.gd#L1172) (`CreateStrip` / `CreateChips` / `CreateFields` / `CreateShape`). Visible only in Object and not painting: [L787–793](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_panel.gd#L787).
- Op Card: [`_operation_controls` L178–266](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_panel.gd#L178) — `OpCardTitle`, `OpCardSettings`, `OpCardCancel` / `OpCardApply`. Shown when an op session is active and paint is not ([L320–323](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_panel.gd#L320)). Title from `OP_SESSION_TITLES: ["Extrude", "Inset", "Bevel"]` ([`slab_actions.gd:151`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_actions.gd#L151)).
- Commands exist: Extrude / Inset / Bevel rows at [`slab_actions.gd:1046, 1053–1054`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_actions.gd#L1046).
- Stills: annex-01/07 show the Create strip. annex-02/03 show **Bevel / Extrude / Inset** as idle Face/Edge commands. [`website/public/img/panel.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel.png) (identical bytes to `panel-preview.png`, 844×300) is an Extrude Op Card: title, Distance 0.5 m, Cancel | yellow Apply.

### Soft Select · Isolate Solids | Faces

**Guess: live chrome and docs language match. One older Soft Select crop is missing the segmented Isolate.**

- Isolate is one labeled control with **Solids** | **Faces**: [`slab_selection_controls.gd:41–59`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_selection_controls.gd#L41). Soft Select label is `"Soft Select"` ([L63](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_selection_controls.gd#L63)); Radius / Falloff (Smooth, Linear) when allowed ([L70–100](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_selection_controls.gd#L70)). Face-isolate tooltip: Escape exits without clearing Soft Select ([L160](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_selection_controls.gd#L160)).
- Smokes assert those strings: [`chrome_smoke.gd:97–103, 153–154`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/tests/chrome_smoke.gd#L97).
- Annex-01/03/04 show **Isolate · Solids | Faces · Soft Select**. annex-03: Soft Select on, Radius 1.2, Smooth. annex-04: Faces segment gold; status “Face isolation on — Esc exits”; Soft Select still on.

### Mode clarity — Object / Vertex / Edge / Face vs UV vs Paint

**Guess: header is two workspaces (`UV`, `Paint`), not one “Surface Paint” button. Docs still say Surface Paint.**

| Live label | Where |
| --- | --- |
| Object · Vertex · Edge · Face | `MODE_LABELS` [`slab_selection.gd:309–314`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_selection.gd#L309); header strip [`slab_mode_strip.gd:8–27, 1043–1045`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_mode_strip.gd#L8) |
| **UV** | `_uv_toggle.text = "UV"` [`slab_panel.gd:1048–1049`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_panel.gd#L1048) |
| **Paint** | `_paint_toggle.text = "Paint"` [L1060–1061](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_panel.gd#L1060) |
| UV Vert / UV Edge / UV Face | `UV_MODE_LABELS` [`slab_selection.gd:41–45`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_selection.gd#L41); annex-05 |
| Material / UV · Pixel | paint tool buttons [`slab_panel.gd:1466–1467`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_panel.gd#L1466) |

`Surface Paint` does **not** appear in `project/addons/slab/`. It is still the website’s name for the workspace (see §2). Annex stills show `UV` | `Paint` as two header toggles; Paint gold in annex-06, UV gold in annex-05.

---

## 2. Docs vs live copy

### Grep hits Design asked about

| Pattern | Live? | Where at tip | Guess |
| --- | --- | --- | --- |
| `Promote to Slab Solid…` (ellipsis) | **No** — code/tests/annex-08 have no dots | [`website/app/guide/reference/panel/page.mdx:82, 96`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/reference/panel/page.mdx#L82); [`explanation/closed-solids/page.mdx:9`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/explanation/closed-solids/page.mdx#L9); [`reference/nodes-and-output/page.mdx:20, 24`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/reference/nodes-and-output/page.mdx#L20) | **block-main** if settle means “manual matches the dock.” How-to body is already correct. |
| Stale “disabled” Promote | Code **hides** the row. Disabled-reason string still exists for a run with no External (`"Select an External mesh to promote."`, [`slab_actions.gd:360`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/addons/slab/slab_actions.gd#L360)) | Panel ref L82: “**Promote to Slab Solid…** needs one External mesh” (sounds like a present, gated command). How-to L7 says hidden. How-to alts still say “Promote … enabled” on [`panel-external.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-external.png) | **block-main** paired with the stale crops in §4 |
| Paint dock occlusion language | How-to updated. Reference + old handoffs not | How-to [`paint-texture-pixels/page.mdx:29, 37`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/paint-texture-pixels/page.mdx#L29): “dock stays beside the canvas… no scroll to uncover them.” Panel ref [L156](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/reference/panel/page.mdx#L156): “Scroll the control column to reach lower settings when the dock is compact.” [`docs/prs-31-figures/FIGURES-remaining.md:19`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/docs/prs-31-figures/FIGURES-remaining.md#L19) still Holds `panel-pixel-paint.png` as occluded | **polish-later** (handoff rot) unless Design treats the panel-ref sentence as live |
| Old chrome in figures | Yes — see §4 | `panel-object`, `panel-export`, `panel-external`, `promote-01…03`, `panel-soft-select` | **block-main** for Promote-on-SlabSolid + ellipsis crops used as Done how-to figures |

`Surface Paint` (one gold header button) is still the guide’s name: [`guide/page.mdx:38`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/page.mdx#L38); panel ref [L7, L146–158](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/reference/panel/page.mdx#L146) (“The gold **Surface Paint** button…”); how-tos paint L15, unwrap L11, select L31/109; tutorials texture-a-room / build-a-house. Live header is **UV** and **Paint**. **Guess: polish-later** unless first-use copy is a settle gate.

### How-to coverage vs code

| Job | Page | vs code | Notes |
| --- | --- | --- | --- |
| Create | [`how-to/create-a-solid`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/create-a-solid/page.mdx) | Matches Create strip + Box fields | Figure [`panel-object.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-object.png) shows **Promote… on a SlabSolid** |
| Soft Select | [`how-to/select-in-the-view`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/select-in-the-view/page.mdx) L11–16 | Label/Radius/Falloff match | [`panel-soft-select.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-soft-select.png) is Vertex + Soft Select 2.5 Smooth; Isolate is a **single** button (no Solids \| Faces) |
| Isolate | same page L81–97 | Copy matches Solids \| Faces + Esc | Figures `isolate-01…03` are **Phase C wireframes** (page says so). Live recapture is annex-04, not in the how-to |
| UV Pack / Fit | [`how-to/unwrap-uvs`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/unwrap-uvs/page.mdx) | Unwrap / Pack / Fit UV match | Opens “**Surface Paint**… Material / UV”. Live: click **UV**. `pack-01` / `panel-material-uv` look like current UV chrome |
| Paint | [`how-to/paint-texture-pixels`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/paint-texture-pixels/page.mdx) | Dock copy matches PRS-38 | Step 3: “Click **Surface Paint**” then Pixel. Live: **Paint**. Figure looks Done |
| Export | [`how-to/prepare-a-solid-for-runtime`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/prepare-a-solid-for-runtime/page.mdx) | `Export...` matches | [`panel-export.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-export.png) is a full editor shot with **Promote to Slab Solid…** on Box2 |
| External / Promote | [`how-to/promote-an-external-mesh`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/promote-an-external-mesh/page.mdx) | Body matches hide + no dots | Idle/success/refuse figures are PRS-28 **wireframes** with `Promote to Solid…`. “Live tip” `panel-external.png` still has dots |
| Extrude / Inset / Bevel | [`pull-a-wall`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/pull-a-wall/page.mdx), [`edit-face-regions`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/edit-face-regions/page.mdx), [`round-beveled-edges`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/round-beveled-edges/page.mdx), [`change-topology`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/app/guide/how-to/change-topology/page.mdx) (clip) | Op Card + keys match | No annex still of an open Op Card |

Leftover unused crop: [`website/public/img/panel-surface-paint.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-surface-paint.png) (106 KB, older). No MDX reference. Handoff called it a UV duplicate.

---

## 3. Annex demo

**Did not open Godot.** Judged from committed stills + `.tscn` node/material list + README/CAPTURE.

### What’s in the tree

- Scene: [`project/demo/signal_relay_annex/signal_relay_annex.tscn`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/signal_relay_annex.tscn) (~77 MB; embedded images). Root `SignalRelayAnnex` + **33 `SlabSolid`** names matching README (threshold, shell, bay, loft, stair, rack, props). **No `SlabExternalMesh` in the saved scene.** `ImportedRack` exists only in annex-08 (capture session).
- README: [`project/demo/signal_relay_annex/README.md`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/README.md) — “v3.1 surface pass”; **“Not Done for PRS-40 — do not merge as Annex Done.”**
- Stills annex-01…08 all present, **1400×960**:

| Stem | File |
| --- | --- |
| 01 create | [`media/annex-01-create.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-01-create.png) |
| 02 topo | [`media/annex-02-topo.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-02-topo.png) |
| 03 soft-select | [`media/annex-03-soft-select.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-03-soft-select.png) |
| 04 face-isolate | [`media/annex-04-face-isolate.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-04-face-isolate.png) |
| 05 uv-pack | [`media/annex-05-uv-pack.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-05-uv-pack.png) |
| 06 paint | [`media/annex-06-paint.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-06-paint.png) |
| 07 export | [`media/annex-07-export.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-07-export.png) |
| 08 promote | [`media/annex-08-external-promote.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/media/annex-08-external-promote.png) |

### Place readability (from stills, no caption)

- **01 / 08:** dark jamb as a frame; look-into a room; cool floor; ochre walls; stair mass on the right; loft band + rack in the depth. Reads as door → bay, not a T of plates.
- **02 / 07:** enclosed bay, loft as a raised deck (warm/white vs cool floor), dark rack as furniture in the back, pier/half-wall. Stair is weaker in 02 (cropped).
- **06:** loft rail + rack strip in the 3D pane; canvas is **flooded** amber / black, not grey + dabs.

Circulation **stair as climbable in one wide frame** is clearest in 01/08 (side steps). 02/06 sell loft + rack more than the climb. Design owns whether that is enough for the stranger test.

### Surface / mood

Stills are high-contrast filled surfaces: cool blue-grey floor, warm ochre walls, dark jamb/trim, charcoal/dark soffit, loft not the same as the bay, rack near-black, bezel saturated amber. annex-06 atlas is block fills after Flatten (`Flatten · v3.1 flood fill` in the chrome).

Scene materials (first 330 lines of the `.tscn`) include albedo `(0.18, 0.22, 0.28)`, ochre `(0.48, 0.36, 0.22)` / `(0.42, 0.32, 0.22)`, near-black `(0.14, 0.16, 0.12)`, cream `(0.92, 0.86, 0.62)`, plus amber emission `(1, 0.72, 0.12)` × several slots and roughness textures. That matches the v3.1 palette claim. **Did not measure UV fill %.**

### README / media gaps named in the brief

From README L54–56 and [PRS-40 brief](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/docs/briefs/prs-40-level-brief.md):

| Named / implied gap | Evidence |
| --- | --- |
| `export_fbx` | README. annex-07 shows Object + `Export…`, no FBX dialog |
| `uv_element_select` | README. annex-05 **does** show UV Vert / Edge / Face on the canvas — coverage claim vs still may disagree; Design/QA call |
| Soft Select **visible falloff** | annex-03 is chrome-on; mesh does not obviously deform |
| Face Isolate **visible hide** | annex-04 chrome-on; hide is not obvious from this camera |
| Active Op Card | not in annex-01…08 |
| External persisted | not in `.tscn`; only annex-08 |
| Capture driver | [`CAPTURE.md`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/project/demo/signal_relay_annex/CAPTURE.md) names `spot/annex_craft_rebuild.gd` and `project/tests/annex_craft_rebuild.gd`. **Neither file is in the tree** |

---

## 4. Figures — Done chrome vs bug evidence

| File | Size | What it looks like |
| --- | --- | --- |
| [`website/public/img/panel-pixel-paint.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-pixel-paint.png) | 852×336, 37 KB, recapture `3d07f23` | **Done chrome.** Dock left, canvas right, Flatten + brush complete. Header is `UV` \| `Paint` (Paint gold). |
| [`website/public/img/panel-external.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-external.png) | 844×353, 56 KB | **Stale live crop.** External selected, V/E/F off, Create strip — but label is **`Promote to Slab Solid…`**. How-to calls this the live tip. |
| [`website/public/img/panel-object.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-object.png) | 844×353, 53 KB | **Bug-shaped Done figure.** Create strip is current; **Promote… sits on Box2** (a SlabSolid). Contradicts PRS-39 + annex-01/07. |
| [`website/public/img/panel-export.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-export.png) | 844×? full editor, 223 KB | Same stale Promote-on-SlabSolid, with dots. Used as the Export how-to figure. |
| [`promote-01-idle.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/promote-01-idle.png) · [`promote-02-success.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/promote-02-success.png) · [`promote-03-refuse.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/promote-03-refuse.png) | 1200×720 RGB, ~30 KB | **Wireframes**, not Godot. Banner “Slab Modeller — Dock”, PRS-28. Promote always present with dots; V/E/F as letter chips. Teaching, not shipping chrome. |
| [`panel.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel.png) / `panel-preview.png` | 844×300, **identical** 23570 B | **Done Op Card** (Extrude). |
| [`panel-soft-select.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-soft-select.png) | 844×300, 31 KB | Soft Select chrome is fine; **Isolate is not Solids \| Faces**. |
| [`isolate-01…03`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/isolate-01-solid-vs-face.png) | wireframes | Docs already mark these as Phase C stand-ins. |
| [`panel-material-uv.png`](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/website/public/img/panel-material-uv.png) | live UV crop | Looks like current UV dock (Unwrap / Pack / Fit UV / UV Vert·Edge·Face). |

PRS-40 care bar ([brief L20](https://github.com/joshocalico/slab-modeller/blob/16422939edafeb2fb9cfba85321921d0fae164f3/docs/briefs/prs-40-level-brief.md#L20)): “Do not mark docs figures Done when they show broken chrome.” The Create / Export / External how-to figures still do.

---

## Unknowns (not verified live)

1. **Godot 4.7 editor was not launched.** No click, no hover tooltip, no resize, no Promote success/refuse, no Soft Select mesh falloff, no Face Isolate hide from another camera.
2. **`scripts/slab-verify` not run** on this box (no Godot).
3. **UV fill %** and stranger-test from a *new* camera — stills only.
4. Whether **annex-05 UV element strip** counts as closing the README `uv_element_select` gap.
5. Whether **FBX** is in the Export dialog (no dialog still).
6. **Native plugin binary** is gitignored (`project/addons/slab/bin/`). Even with Godot, this snapshot may not have been able to instance `SlabSolid`.
7. Linear PRS-38 / PRS-39 are **Done** in tracker; this gather does not re-open them. It only notes leftover **docs figures** vs that Done chrome.

---

## Design-owned (no PASS/HOLD here)

Code at this tip implements PRS-38/39 as specified. The mismatch that still photographs is **website figures + some reference copy** (Promote ellipsis / Promote on a SlabSolid / “Surface Paint” / compact-dock scroll). Annex stills 01/06/08 are the honest live chrome for Create / Paint dock / Promote. README already says the annex is **not** Done for PRS-40.
