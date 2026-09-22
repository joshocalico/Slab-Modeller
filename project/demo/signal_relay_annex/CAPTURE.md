# Capture

SubViewport + `Camera3D.make_current` + root `viewport.get_texture().get_image()` composite.

**Never** `DisplayServer.screen_get_image`.

Brief v3.1 surface: high-contrast palette + full UV island fills. Tip base `2b60ce13e2871f9448b41500587ca3ddff82a74f`.

The original capture driver was not retained in this checkout. The media files are historical evidence of that pass; this file does not provide a reproducible capture command.
