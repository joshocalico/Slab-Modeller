# Slab guide

Next.js app for the Slab manual. Markdown pages live under `app/guide`. The home page is a React landing you can restyle or replace.

```bash
cd website
npm install
npm run dev
```

Open http://localhost:3000. `npm run build` writes a static tree to `out/`.

Regenerate screenshots from the repo root with `scripts/slab-docs-capture`. That run needs a windowed Godot, not `--headless`. The kernel test `emit_winds_clockwise_against_the_outward_normal` fails if emit winding flips again.

