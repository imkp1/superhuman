# superhuman website

Static landing page for the superhuman harness. One self-contained `index.html` plus two image assets — no build step, no dependencies.

Implemented from the Claude Design project "Superhuman Landing - Options" (option 1a, Orbit): the hero is a live demo window where one unattended run — issue-selector → repo-profiler → planner → builder → scorer — converges to **Merged** around the mascot, on a 16-second loop.

## Preview locally

```bash
open website/index.html
# or, to serve it:
python3 -m http.server 8000 --directory website
```

## Deploy

### Vercel

The repo root ships a `vercel.json` that publishes this `website/` folder with no
build step — just import the repo into Vercel and deploy (leave every setting at
its default). Or from the CLI:

```bash
vercel        # preview deploy
vercel --prod # production deploy
```

### Any static host

Any static host works. For GitHub Pages:

1. Settings → Pages → Deploy from a branch.
2. Copy the folder contents to `docs/` and select `main` + `/docs`, or publish the folder directly:

```bash
git subtree push --prefix website origin gh-pages
```

## Assets

- `assets/mascot-scene.png` — transparent cutout of the mascot at its desk (hero centerpiece)
- `assets/mascot.png` — square face crop on cream (nav avatar / OG image)

Both are crops of the source character art (`ChatGPT Image Jul 5, 2026, 05_43_27 PM.png`). Fonts load from Google Fonts (Instrument Sans, IBM Plex Mono); everything else is local.
