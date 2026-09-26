<p align="center">
  <img src="SlabLogo.svg" alt="Slab" width="128" height="128" />
</p>

# Slab

In-engine modelling software for Godot. Half-edge solids, direct manipulation, real geometry.

Slab is a Godot 4.7 editor plugin for modelling closed solids, editing UVs, and painting textures. Geometry lives in a GDExtension (`SlabSolid`, `SlabSocket`, `SlabModule`). The editor tools use GDScript.

## How to use it

For a prebuilt installation, follow [Install Slab](website/app/guide/install/page.mdx) to download `slab-addon.zip`, extract it beside `project.godot`, restart Godot, and enable Slab under **Project Settings → Plugins**. The ZIP includes editor and export libraries for Windows x64, Linux x64, and macOS Intel/Apple Silicon. Until a release is published, download the `slab-addon` artifact from a successful **Build drop-in addon** run in [GitHub Actions](https://github.com/joshocalico/slab-modeller/actions).

For a source checkout, [build the extension](#build) before opening `project/` in Godot 4.7. The Slab bottom panel contains the modelling tools. The full manual is the Next.js app in `website/`:

```bash
cd website
npm install
npm run dev
```

**Create a solid.** In Object mode, choose a shape such as Box, Cylinder, or Stair in the Create strip. Set its dimensions and click **Create**. Click in the 3D view or press Enter to place the preview.

**Selection modes.** Press 1–4 to switch between Object, Vertex, Edge, and Face modes. Click to select; Shift-click to add.

| Key | Action |
|---|---|
| 1 / 2 / 3 / 4 | Object / Vertex / Edge / Face mode |
| W | Move gizmo (translate selection) |
| E | Extrude selected faces |
| I | Inset |
| B | Bevel selected edges |
| L | Insert edge loop |

To extrude, enter **Face** mode, select a face, then press **E** or click **Extrude**. Drag the Slab operation handle or edit its amount, then press **Enter** to apply. Press **Escape** to cancel. Positive amounts extend outward. For a recessed room, inset first, then extrude inward without passing through the opposite wall.

Shift-drag directly on a face to extrude, or directly on an edge to bevel. Start on the geometry, away from Godot's move/rotate/scale gizmo. Shift-dragging that gizmo is not the Slab extrusion gesture.

**Soft Select.** In element modes, enable Soft Select to apply falloff influence to neighboring geometry during transforms. Set radius and falloff curve in the panel.

**Isolate.** One control with Solids | Faces. Solids hides other solids. Faces hides unselected faces on the active solid and leaves other solids in the scene. Escape exits Face isolation without clearing Soft Select.

**UV and Paint.** Click **UV** in the header to assign materials, unwrap faces, and adjust UV placement. Click **Paint** to paint texture pixels.

**Import & Export.** Import external meshes (OBJ, STL) to reference alongside your solids. Export your models via the Export action.

Open modules stay legal because a wall is a thin closed box, not a one-sided sheet. A one-off door is a Subtract through the wall. A `SlabSocket` on a `SlabModule` is a named opening — it marks a connection point without cutting the mesh.

Subtracting a solid wholly inside another creates a closed cavity. Boolean operations commit only when the result passes solid validation.

## Tutorials

Short silent clips of the editor. Files live in `website/public/videos/v1/` (also mirrored under `docs/videos/v1/`).

1. [Create a solid](website/public/videos/v1/v1-01-create-solid.mp4)
2. [Extrude, inset, bevel, and loop](website/public/videos/v1/v1-02-extrude-inset-bevel-loop.mp4)
3. [Soft Select](website/public/videos/v1/v1-03-soft-select.mp4)
4. [UV unwrap and Fit](website/public/videos/v1/v1-04-uv-unwrap-fit.mp4)
5. [Paint texture pixels](website/public/videos/v1/v1-05-surface-paint.mp4)
6. [Export a mesh](website/public/videos/v1/v1-06-export-mesh.mp4)
7. [Import an External mesh](website/public/videos/v1/v1-07-import-external.mp4)

The same list is on the [guide](website/app/guide/page.mdx) under Learn by making.

## Build

The [build workflow](.github/workflows/build-addon.yml) builds and tests debug and release libraries on all three desktop platforms. Each successful run produces a `slab-addon` artifact containing the installable ZIP and its SHA-256 checksum. See [Publish an addon build](docs/publish-addon.md) for release steps.

```bash
git submodule update --init --recursive
scons target=template_debug
scripts/slab-verify
```
