# Moonlit Beacon player-care site

Small static privacy/support site for Moonlit Beacon 4.0.0. No framework, no
dependencies, no JavaScript in the pages, no external fonts, no forms, no
tracking. A dependency-free Node generator renders every route from
locale content modules plus the live product catalog.

## Routes

Five locales (`en`, `ko`, `ja`, `zh-Hans`, `zh-Hant`), each with privacy and
support pages, plus English x-default and chooser routes:

- `/` — language chooser (English)
- `/privacy`, `/support` — full English policy/support (x-default)
- `/{locale}/` — locale chooser
- `/{locale}/privacy`, `/{locale}/support` — the 10 localized pages
- `/404.html` — hosting not-found page

Every clean route ships as both `ROUTE.html` and `ROUTE/index.html` with
identical bytes, so Firebase Hosting `cleanUrls` and plain static servers
serve the same content.

## Commands (run from the repo root)

```bash
pnpm player-care:build   # render dist/ (reads notes/release/store-localizations.csv)
pnpm player-care:check   # rebuild to a temp dir, verify routes/content/links
pnpm test:player-care    # node --test regression suite (builds fresh, never mutates dist/)
```

`dist/` is committed so the director deploys exactly the inspected bytes.
Rebuild after any content or CSV change; `--check` fails on stale output.

## Content sources

- Privacy copy: `notes/release/privacy-four-zero-draft.md` statements S1–S8.
  Audit notes in that draft are NOT published as player copy.
- Product inventory: `notes/release/store-localizations.csv` display names
  and descriptions at build time (7 permanent + 3 coin packs, grants 1/5/10).
- Purchase handling: `notes/release/iap-store-setup.md` privacy baseline.
- Publisher/support: `notes/release/store-page.md`
  (Hyo Dev, copyright 2026 Hyo Jang, `hyo@hyo.dev`).
- In-app Terms stay in `apps/game/localization/gate_entry.csv` and are only
  referenced, never duplicated or edited here.

## Deploy (director only)

Hosting-only configuration for the existing default site; this repo never
deploys. From this directory, after inspecting `dist/`:

```bash
firebase use moonlitbeacon-778ee
firebase deploy --only hosting
```

`firebase.json` sets `site: moonlitbeacon-778ee` (the existing default site),
`public: dist`, `cleanUrls`, and no rewrites, functions, or other services.
`.firebaserc` pins the default project only. There are zero existing hosting
releases, so the first deploy overwrites nothing. No credentials live here.
The public origin is the custom domain `https://moonlitbeacon.hyo.dev`,
connected to Hosting with server-specified DNS outside this repo; the
default site URL and native auth callback stay as configured.
