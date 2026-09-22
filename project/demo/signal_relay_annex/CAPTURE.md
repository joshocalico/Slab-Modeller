# Capture

## September 23 native pass

`annex-09` through `annex-13` are uncomposited Godot window captures made during native editor use. `annex-13` shows the running scene after an editor restart. Select `Camera3D` or `EntranceCamera` and enable **Preview** to reproduce their viewpoints; playing the scene uses `Camera3D`.

## Historical pass

SubViewport + `Camera3D.make_current` + root `viewport.get_texture().get_image()` composite.

**Never** `DisplayServer.screen_get_image`.

Brief v3.1 surface: high-contrast palette + full UV island fills. Tip base `2b60ce13e2871f9448b41500587ca3ddff82a74f`.

The original capture driver was not retained in this checkout. The media files are historical evidence of that pass; this file does not provide a reproducible capture command.
