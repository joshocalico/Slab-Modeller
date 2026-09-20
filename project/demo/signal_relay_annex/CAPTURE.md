# Capture note (PRS-40 craft)

Utilitarian stills use SubViewport (own_world_3d) + Camera3D.make_current aimed at annex centroid,
with SlabPanel in the same Window layout. Composite via `root.get_viewport().get_texture().get_image()`.

**Forbidden:** `DisplayServer.screen_get_image`.

Driver: `spot/annex_craft_rebuild.gd` → `res://tests/annex_craft_rebuild.gd`.
