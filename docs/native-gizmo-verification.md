# Native gizmo verification

`scripts/slab-native-gizmo-verify` opens dedicated Godot editors and tests native element transforms. The default run renders the editor and records before/after PNGs. `--headless` exercises the same native input handler without images.

The matrix covers Move, Rotate, and Scale with three configurations:

| Pivot | Axes |
| --- | --- |
| Selection centre | World |
| Active element | Object local |
| Custom world point | Selected face |

Each fixture has a 30-degree Y rotation and scale `(1.5, 1, 0.8)`. Each gesture must change mesh data, preserve the node transform, create a `Slab Transform Elements` action, and restore exact mesh bytes through Undo and Redo. Move also checks equal world displacement for every vertex. A separate Escape gesture must restore the original mesh without creating an undo action.

The default runner also opens `MaintenanceBayRoof` in a front view and starts a Move-axis gesture outside the roof geometry. Surface Paint must own the complete press, drag, and release without selecting a face, changing mesh or node data, or creating history. After Paint exits, the same axis gesture must work and remain exactly undoable.

The runner configures the initial editor selection, focuses it through Godot's native F shortcut, and sends mouse events through the viewport's connected `gui_input` signal. Motion events carry the held LEFT button mask. The runner does not call Slab transform callbacks directly. Gesture endpoints must lie inside the viewport. No scene is saved.

The command prints its temporary evidence directory and returns nonzero if a case fails. Each case produces JSON configuration, a log with `NATIVE_CHECK` and `NATIVE_RESULT` records, and rendered PNGs when a display is available. This command remains separate from `scripts/slab-verify` because the default run opens editor windows.

`project/tests/native_gizmo_editor_smoke.gd` also accepts one JSON configuration path after `--`. Its optional fields include `scene`, `node`, `tool` (`W`, `E`, or `R`), `pivot`, `orientation`, `custom_pivot`, `rotation_degrees`, `scale`, and `cancel`. Pivot and orientation indices follow the table order. `axis_index` selects X, Y, or Z by zero-based index, `handle_distance` overrides the projected handle distance, and `front_view` selects Godot's front orthographic view before framing. Set `paint_empty_gesture` to verify Surface Paint ownership at an empty gizmo coordinate and the same gesture after Paint exits. `start` and `end` override native viewport coordinates. `delay`, `step_delay`, and `after_drag_delay` control inspection time. `capture_prefix` sets the PNG prefix. A 90-second watchdog bounds each case.

`project/tests/editor_scene_snapshot.gd` produces deterministic JSON for a saved scene, with an optional node path filter. It reports mesh hashes, vertex positions, topology counts, and node transforms from a detached scene without running scene callbacks.

`scripts/godot --editor --path project --script res://tests/panel_editor_smoke.gd` checks the modelling panel through GUI mouse events. It switches modes, starts an Inset preview, cancels it, applies it, and verifies exact Undo restoration. It writes rendered Object, Face, and preview images to `/tmp/slab-panel-*-after.png` without saving the scene. The chrome suite also checks the wide and narrow dock layouts.
