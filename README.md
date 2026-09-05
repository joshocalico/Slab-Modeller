# Slab

In-Godot 3D blockout. Half-edge solids, not AABB boxes.

Godot 4.5+ editor plugin. Geometry is a GDExtension (`SlabSolid`, `SlabSocket`, `SlabModule`). Tools are GDScript so the feel can change without a recompile.

## How to use it

Open `project/` in Godot 4.7. The Slab bottom panel is the editor. The full manual is the Next.js app in `website/`:

```bash
cd website
npm install
npm run dev
```

Create a box from that panel. Then:

| Key | Action |
|---|---|
| 1 / 2 / 3 / 4 | Object / vertex / edge / face mode |
| Click in the 3D view | Select an element. Shift adds. |
| E | Extrude the selected faces |
| I | Inset |
| B | Bevel selected edges |
| L | Insert an edge loop |

UV scale, offset, and rotation (degrees in the panel, radians on the solid) live on the same panel. Every edit goes through undo.

Open modules stay legal because a wall is a thin closed box, not a one-sided sheet. Doors are sockets, not boolean shatter.

Boolean subtract of a solid wholly inside another punches a watertight cavity. Overlapping clip is refused until it can stay watertight.

## Build

```bash
git submodule update --init --recursive
scons target=template_debug
scripts/slab-verify
```
