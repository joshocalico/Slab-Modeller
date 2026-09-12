# Slab guide

Next.js app for the Slab manual. Markdown pages live under `app/guide`. Engineering notes live under `app/engineering`. The home page is a React landing.

```bash
cd website
npm install
npm run dev
```

Open http://localhost:3000. `npm run build` writes a static tree to `out/`.

Copy `.env.example` to `.env` if you want **Edit on GitHub** links. `NEXT_PUBLIC_GITHUB_REPO` is `owner/repo`. Leave it empty to hide the links.

Regenerate screenshots from the repo root with `scripts/slab-docs-capture`. That run needs a windowed Godot, not `--headless`. The kernel test `emit_winds_clockwise_against_the_outward_normal` fails if emit winding flips again.

The manual uses the existing charcoal and gold palette. `globals.css` owns the shared reading layout; `Figure` gives images full-size links and videos posters. The navigation lives in `lib/nav.ts`. Section links use the heading IDs rendered by `mdx-components.tsx`, so copied anchors also work on a fresh load.

Keep each page in one documentation mode: tutorial, how-to, reference, or explanation. Write the click, the result, and the limit. Check tool names and ranges against the addon before changing instructions.

Before shipping, run `npm run lint` and `npm run build`. Check the home page, a tutorial, and the panel reference at desktop and phone widths. Exercise both mobile contents menus, an in-page link, and a full-size figure. Keep `pnpm-lock.yaml` and `pnpm-workspace.yaml` out of commits.
