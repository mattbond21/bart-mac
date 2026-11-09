# Landing page handoff

The landing page lives on the `landing-page` branch, in `site/`. `main` doesn't have it yet. The page will be hosted on Vercel at a domain that hasn't been bought yet.

## Files

| Path | What it is |
| --- | --- |
| `site/index.html` | The whole page: HTML, inline CSS, and a small script for the copy button. No build step, no dependencies. |
| `site/vercel.json` | Turns on clean URLs and caches `/images/*` for a day. |
| `site/images/popover.png` | Menu bar window screenshot, cropped to 836×926 so no desktop shows around it. |
| `site/images/widget-*.png` | Small, medium, large and large-dark widget screenshots. |
| `site/images/app-icon.png` | App icon, used for the header and favicon. |

The images are copies. The README still uses the originals in `docs/images/`, so a retaken screenshot needs copying to both places.

## Run it locally

```sh
git fetch && git switch landing-page
cd site && python3 -m http.server 4173
```

Open http://127.0.0.1:4173 and refresh after each edit. The Python server ignores `vercel.json`, which doesn't matter for this page. To match Vercel exactly, run `npx vercel dev` in `site/` instead (needs a Vercel login and a linked project).

The page follows the system light or dark setting, and the two look quite different. Check both before committing.

## Design direction

The page should look like Bart itself, not like a template. The first version was a dark, Flighty-inspired page that read as AI-generated, so it was rebuilt with the `emil-unslop-design` pass.

Keep doing:

- **Look like the app.** Light paper background (`#f5f4f0`), a dark version that follows the system setting, and the app's rounded system font (`ui-rounded`). No web fonts.
- **Use only the app's status colors.** Late red and on-time green, as in `Sources/Bart/TrainStyle.swift`. There's no brand accent color, on purpose.
- **Repeat the route line.** Every section label is drawn like the app's route line, e.g. `Home ——— WHAT IT SHOWS ——— Work`: a 2px rounded rule between two labels.
- **Show real screenshots,** sized unevenly, not invented graphics.
- **Write plainly and honestly.** Features are a plain list, including a "What it won't do" item about transfers.

Don't bring back:

- Dark glowing gradients, frosted sticky headers, or a background behind the hero.
- A small label with a green "live" dot above the headline.
- Two-tone headlines with a dimmed second line.
- Matching feature cards with blue uppercase labels and made-up graphics.
- Fake live data, such as train times built from the visitor's clock.
- Scroll-triggered fades, carousels, or hover effects on things you can't click.

## Deploying on Vercel

1. In Vercel, import `mattbond21/bart-mac`.
2. Set **Root Directory** to `site`, set the framework preset to **Other**, and leave the build command empty.
3. Choose the production branch: merge `landing-page` into `main` first, or point production at `landing-page` for now.
4. Once the domain is bought, add it under **Project → Settings → Domains** and set the DNS records Vercel shows.

Every push then gets a preview URL, which is handy for checking on a phone.

## To do

Once the domain is bought:

- [ ] Change `og:image` to a full URL (`https://<domain>/images/...`). Link previews in Slack, iMessage and X don't load relative paths.
- [ ] Add `<link rel="canonical" href="https://<domain>/">`.
- [ ] Make a proper 1200×630 share image. The cropped popover screenshot is standing in for it now.

Smaller follow-ups:

- [ ] Decide whether to keep the shadow on the hero screenshot. It's the heaviest effect left on the page.
- [ ] Update the download links if releases move off GitHub. All three point to `github.com/mattbond21/bart-mac/releases/latest`.
- [ ] If Bart gets notarized, remove install step 3 (the `xattr` command and Open Anyway).
- [ ] Open a pull request to merge `landing-page` into `main` when it's ready, and delete this file then.
