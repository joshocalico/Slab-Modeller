import Link from "next/link";
import { Figure } from "@/components/Figure";

export default function Home() {
  return (
    <main className="mx-auto max-w-5xl px-6 py-16">
      <p className="mb-6 text-sm font-semibold tracking-[0.14em] text-slab-gold uppercase">
        Slab
      </p>
      <h1 className="max-w-3xl text-4xl font-semibold tracking-tight text-slab-ink sm:text-5xl">
        Block out levels inside Godot.
      </h1>
      <p className="mt-5 max-w-2xl text-lg text-slab-muted">
        Slab is an editor plugin for Godot 4.7. You click a face in the 3D view
        and pull. Geometry is a half-edge solid, not a one-sided sheet.
      </p>
      <div className="mt-8 flex flex-wrap gap-4">
        <Link
          className="bg-slab-gold px-4 py-2 font-medium text-slab-bg no-underline hover:no-underline"
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
        caption="Inset the top, then drag the inner face down. Walls and a floor. No roof."
      />
      <section className="mt-16 grid gap-8 sm:grid-cols-3">
        <div>
          <h2 className="text-lg font-semibold">Select in the view</h2>
          <p className="mt-2 text-slab-muted">
            Keys 1 to 4 switch object, vertex, edge, and face mode. Click
            selects. Drag past six pixels moves the selection.
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
    </main>
  );
}
