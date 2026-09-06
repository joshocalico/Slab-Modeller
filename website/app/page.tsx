import { Figure } from "@/components/Figure";
import { EditLink } from "@/components/EditLink";
import { SiteMark } from "@/components/SiteMark";
import Link from "next/link";

export default function Home() {
  return (
    <main className="mx-auto max-w-5xl px-6 py-16">
      <SiteMark />
      <h1 className="mt-8 max-w-3xl text-4xl font-semibold tracking-tight text-slab-ink sm:text-5xl">
        Block out levels inside Godot.
      </h1>
      <p className="mt-5 max-w-2xl text-lg text-slab-muted">
        Godot CSG is a node tree you inspect. Blender is a round trip. Slab is
        a closed solid you click in the 3D view.
      </p>
      <div className="mt-8 flex flex-wrap gap-4">
        <Link
          className="bg-slab-gold px-4 py-2 font-semibold text-black no-underline hover:no-underline"
          href="/guide/tutorials/block-out-a-room"
        >
          Block out a room
        </Link>
        <Link className="px-4 py-2 text-slab-ink" href="/guide">
          Read the guide
        </Link>
      </div>
      <Figure
        src="/img/solid-room.png"
        alt="A hollow SlabSolid with an open top, inner walls, and a floor."
        caption="Inset the top, then move the inner cap down. Walls and a floor. No roof."
      />
      <section className="mt-16 max-w-2xl space-y-4 text-slab-muted">
        <h2 className="text-lg font-semibold text-slab-ink">
          Why not CSGBox3D
        </h2>
        <p>
          <code>CSGBox3D</code> and <code>CSGCombiner3D</code> boolean at the
          node. You add children. You wait for a mesh. You do not select a
          face and pull it. Union is a node, not an undoable edit. The tree is
          the document.
        </p>
        <p>
          Blender and Unity ProBuilder give you the click. They are not the
          Godot editor. GridMap is tiles. A wall there is a cell, not a
          volume you inset.
        </p>
        <p>
          Slab stores a watertight half-edge mesh on <code>SlabSolid</code>.
          Keys 1 to 4 switch object, vertex, edge, and face. Click selects. The
          Move gizmo translates. Subtract punches a doorway and keeps a closed
          solid. Every edit records undo.
        </p>
      </section>
      <section className="mt-16 grid gap-8 sm:grid-cols-3">
        <div>
          <h2 className="text-lg font-semibold">Select in the view</h2>
          <p className="mt-2 text-slab-muted">
            Keys 1 to 4 switch object, vertex, edge, and face mode. Click
            selects. The Move gizmo translates. Shift-drag extrudes a face or
            bevels an edge.
          </p>
        </div>
        <div>
          <h2 className="text-lg font-semibold">Edit on the solid</h2>
          <p className="mt-2 text-slab-muted">
            Extrude, inset, bevel, and loops live on the Slab bottom panel. Every
            edit records undo.
          </p>
        </div>
        <div>
          <h2 className="text-lg font-semibold">Stay watertight</h2>
          <p className="mt-2 text-slab-muted">
            A wall is a thin closed box. Subtract punches a cavity when the
            cutter sits inside, or a doorway when it crosses a wall.
          </p>
        </div>
      </section>
      <p className="mt-16 text-sm text-slab-muted">
        Papers and mesh notes live in{" "}
        <Link href="/engineering">Engineering</Link>, off the guide.
      </p>
      <EditLink />
    </main>
  );
}
