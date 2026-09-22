import Image from "next/image";
import { Figure } from "@/components/Figure";
import { EditLink } from "@/components/EditLink";
import { SiteMark } from "@/components/SiteMark";
import Link from "next/link";

export default function Home() {
  return (
    <main id="main-content" className="home">
      <header className="home-header"><SiteMark /><nav aria-label="Main"><Link href="/guide">The guide</Link><Link href="/engineering">Engineering</Link></nav></header>
      <section className="home-hero">
        <div>
          <p className="eyebrow">The Slab manual · Godot 4.7</p>
          <h1>Block out levels<br />inside Godot.</h1>
          <p className="hero-intro">Create closed solids, edit faces, and paint materials directly in the Godot 3D editor.</p>
          <div className="home-actions"><Link className="primary-link" href="/guide/tutorials/block-out-a-room">Block out a room <span aria-hidden="true">↗</span></Link><Link href="/guide/install">Install Slab →</Link></div>
        </div>
        <div className="hero-mesh"><span className="eyebrow">01 / Inset → move → room</span><Figure eager src="/img/solid-room.png" alt="An open-top room with thick walls, viewed from above." caption="Inset the top. Move the inner cap down. Stop before the floor." /></div>
      </section>
      <div className="home-strip"><span>One solid. Faces you can pull.</span><span><kbd>1</kbd> Object <kbd>2</kbd> Vertex <kbd>3</kbd> Edge <kbd>4</kbd> Face</span></div>
      <section className="home-workflows" aria-labelledby="workflows-title">
        <div className="section-heading"><div><p className="eyebrow">Start with a volume</p><h2 id="workflows-title">A room. A surface. A roof.</h2></div><Link href="/guide">All pages →</Link></div>
        <div className="workflow-grid">
          <Link className="workflow" href="/guide/tutorials/block-out-a-room"><Image width={1280} height={720} sizes="(max-width: 800px) 100vw, 360px" src="/img/solid-door.png" alt="A hollow room with a doorway cut through its wall." /><div><span className="eyebrow">01 / Shape</span><h3>Block out a room <span aria-hidden="true">↗</span></h3><p>Inset a box. Lower the floor. Subtract a door through the wall.</p></div></Link>
          <Link className="workflow" href="/guide/tutorials/texture-a-room"><Image width={1280} height={720} sizes="(max-width: 800px) 100vw, 360px" src="/img/solid-textured.png" alt="A room with different materials on its floor and walls." /><div><span className="eyebrow">02 / Surface</span><h3>Texture a room <span aria-hidden="true">↗</span></h3><p>Two materials on one solid. Set the repeats. Turn a wall texture.</p></div></Link>
          <Link className="workflow" href="/guide/tutorials/build-a-house"><Image width={1280} height={720} sizes="(max-width: 800px) 100vw, 360px" src="/img/house-04.png" alt="A Slab house made with an arch roof and a box." /><div><span className="eyebrow">03 / Combine</span><h3>Build a house <span aria-hidden="true">↗</span></h3><p>An Arch roof, a box, and Union. Cut a doorway and add three materials.</p></div></Link>
        </div>
      </section>
      <section className="home-principles"><div><p className="eyebrow">Work on the solid</p><h2>The click stays<br />in the editor.</h2></div><div>
        <h3>Select in the view</h3><p>Keys 1 to 4 switch Object, Vertex, Edge, and Face mode. Click selects and the Move gizmo translates. In Face mode, Shift-drag extrudes; in Edge mode, Shift-drag bevels.</p>
        <h3>Edit on the solid</h3><p>Extrude, Inset, Bevel, and Loop Cut are in the Slab bottom panel. Open UV to assign materials and place UVs, or Paint to edit texture pixels. Geometry edits, UV changes, and paint strokes support undo.</p>
        <h3>Stay watertight</h3><p>A wall is a thin closed box. Subtract punches a cavity when the cutter sits inside, or a doorway when it crosses a wall. A refused edit leaves the solid as it was.</p><Link href="/guide/explanation/closed-solids">Why closed solids →</Link>
      </div></section>
      <footer className="home-footer"><p>A key or a button? <Link href="/guide/reference/keys-and-modes">Keys and modes</Link> · <Link href="/guide/reference/panel">The Slab panel</Link></p><p>Papers and mesh notes live in <Link href="/engineering">Engineering</Link>, off the guide.</p><EditLink /></footer>
    </main>
  );
}
