<p align="center">
  <img src="SlabLogo.svg" alt="Slab" width="128" height="128" />
</p>

# Slab

In-engine modelling software for Godot. Half-edge solids, direct manipulation, real geometry.

Slab is a Godot 4.7 editor plugin that brings UMX-class half-edge modelling directly into the engine. Model, UV, paint, and share — without leaving the editor. Geometry lives in a GDExtension (`SlabSolid`, `SlabSocket`, `SlabModule`). Tools are GDScript so the workflow can evolve without a recompile.

## How to use it

Open `project/` in Godot 4.7. The Slab bottom panel is the editor. The full manual is the Next.js app in `website/`:

```bash
cd website
npm install
npm run dev
```

**Create a solid.** In Object mode, use the Create strip: pick a shape (Box, Cylinder, Prism, etc.), set Width/Height/Depth, then click **Create**.

**Selection modes.** Press 1–4 to switch between Object, Vertex, Edge, and Face modes. Click to select; Shift-click to add.

| Key | Action |
|---|---|
| 1 / 2 / 3 / 4 | Object / Vertex / Edge / Face mode |
| W | Move gizmo (translate selection) |
| E | Extrude selected faces |
| I | Inset |
| B | Bevel selected edges |
| L | Insert edge loop |

Shift-drag a face to extrude. Shift-drag an edge to bevel.

**Soft Select.** In element modes, enable Soft Select to apply falloff influence to neighboring geometry during transforms. Set radius and falloff curve in the panel.

**Surface Paint.** Open the Surface Paint section for materials and UVs. UV scale, offset, and rotation live on the same panel. Every edit goes through undo.

**Import & Export.** Import external meshes (OBJ, STL) to reference alongside your solids. Export your models via the Export action.

Open modules stay legal because a wall is a thin closed box, not a one-sided sheet. A one-off door is a Subtract through the wall. A `SlabSocket` on a `SlabModule` is a named opening — it marks a connection point without cutting the mesh.

Boolean subtract of a solid wholly inside another punches a watertight cavity. Overlapping clip is refused until it can stay watertight.

## Tutorials

Short silent clips of shipping chrome (PRS-37). Files live in `website/public/videos/v1/` (also mirrored under `docs/videos/v1/`).

1. [Create a solid](website/public/videos/v1/v1-01-create-solid.mp4)
2. [Extrude, inset, bevel, and loop](website/public/videos/v1/v1-02-extrude-inset-bevel-loop.mp4)
3. [Soft Select](website/public/videos/v1/v1-03-soft-select.mp4)
4. [UV unwrap and Fit](website/public/videos/v1/v1-04-uv-unwrap-fit.mp4)
5. [Surface Paint](website/public/videos/v1/v1-05-surface-paint.mp4)
6. [Export a mesh](website/public/videos/v1/v1-06-export-mesh.mp4)
7. [Import an External mesh](website/public/videos/v1/v1-07-import-external.mp4)

The same list is on the [guide](website/app/guide/page.mdx) under Learn by making.

## Build

```bash
git submodule update --init --recursive
scons target=template_debug
scripts/slab-verify
```
