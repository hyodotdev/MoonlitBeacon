# Moonlit Beacon player-care site

Small static privacy/support/terms site for Moonlit Beacon 4.0.0. No
framework, no dependencies, no JavaScript in the pages, no external fonts,
no forms, no tracking. A dependency-free Node generator renders every route
from locale content modules plus the live product catalog and the in-game
Terms CSV.

## Routes

Five locales (`en`, `ko`, `ja`, `zh-Hans`, `zh-Hant`), each with privacy,
support, and terms pages, plus English x-default and chooser routes:

- `/` — language chooser (English)
- `/privacy`, `/support`, `/terms` — full English policy/support/terms (x-default)
- `/{locale}/` — locale chooser
- `/{locale}/privacy`, `/{locale}/support`, `/{locale}/terms` — the 15 localized pages
- `/404.html` — hosting not-found page

Every clean route ships as both `ROUTE.html` and `ROUTE/index.html` with
identical bytes, so Firebase Hosting `cleanUrls` and plain static servers
serve the same content.

Every page nav also links the course/reference at `/MoonlitBeacon/` with a
localized label (`Course & Docs`, `강좌·문서`, `講座・ドキュメント`,
`课程与文档`, `課程與文件`). The docs navbar and footer link back to the
English privacy and support pages at the custom origin. The care-only checker
below resolves every local link except this one docs mount prefix;
`hosting:check` resolves those targets against the real docs build, so no
link goes unverified.

## Commands (run from the repo root)

```bash
pnpm player-care:build   # render dist/ (reads notes/release/store-localizations.csv)
pnpm player-care:check   # rebuild to a temp dir, verify routes/content/links
pnpm test:player-care    # node --test regression suite (builds fresh, never mutates dist/)
```

`dist/` is committed so the director inspects exactly the bytes that ship at
the site root. Rebuild after any content or CSV change; `--check` fails on
stale output.

## Combined hosting site

The public deploy serves these care pages at the origin root plus the course
and reference under `/MoonlitBeacon/` from one Firebase Hosting site:

- `/…` — the care routes above, unchanged
- `/MoonlitBeacon/` — docs home
- `/MoonlitBeacon/course` — course guide
- `/MoonlitBeacon/course/chapter-01` — Lesson 1
- `/MoonlitBeacon/docs/intro` — reference entry

```bash
pnpm hosting:build   # fresh care dist + fresh docs build, then compose apps/player-care/hosting-dist
pnpm hosting:check   # exact parity, link health, NUL/notes/secrets/symlink scan, config scope
pnpm test:hosting    # node --test composition/checker regressions (temp dirs only)
```

`apps/player-care/hosting-dist/` is generated and gitignored via the
app-local `.gitignore` (alongside `.firebase/`); composition copies bytes
only, with no rewriting and no timestamps. `hosting:build` refuses a stale
care `dist/` and a missing docs build. `hosting:check` verifies all 49 care
files and all 26 docs pages plus assets, resolves every local href/src
(extensionless docs routes included), requires the real care `404.html`
with no catch-all rewrite, and pins the hosting config to site
`moonlitbeacon-778ee` and the generated directory while the root
`firebase.json` stays Firestore-only. The config check also requires
`public` to stay inside the Firebase project directory (the folder holding
`firebase.hosting.json`); the CLI refuses anything outside it before upload.

## Content sources

- Privacy copy: `notes/release/privacy-four-zero-draft.md` statements S1–S8.
  Audit notes in that draft are NOT published as player copy.
- Product inventory: `notes/release/store-localizations.csv` display names
  and descriptions at build time (7 permanent + 3 coin packs, grants 1/5/10).
- Purchase handling: `notes/release/iap-store-setup.md` privacy baseline.
- Publisher/support: `notes/release/store-page.md`
  (Hyo Dev, copyright 2026 Hyo Jang, `hyo@hyo.dev`).
- Terms: `apps/game/localization/gate_entry.csv` rows `gate.terms.title`
  and `gate.terms.p1`–`p8`, read at build time with the existing CSV
  parser and published verbatim (escaped) on `/terms` and
  `/{locale}/terms`. Only the surrounding labels are localized site copy;
  the agreement itself is never duplicated or edited here.

## Deploy (director only)

Hosting-only deployment of the combined site; this repo never deploys. From
the repo root, after inspecting `dist/` and the composed output:

```bash
pnpm hosting:build
pnpm hosting:check
cd apps/player-care && firebase deploy --only hosting --config firebase.hosting.json --project moonlitbeacon-778ee
```

`firebase.hosting.json` sets `site: moonlitbeacon-778ee` (the existing
default site), `public: hosting-dist`, `cleanUrls`, and no rewrites,
functions, or other services. The command deploys hosting only; Firestore
rules and the native auth callback stay untouched. Release history, short
form: the director's inspected privacy/support care-only release went
live first and was verified over ordinary HTTPS on all 18 routes; a
later combined attempt with `public: ../../builds/hosting` was refused
by the Firebase CLI before upload ("outside of project directory"),
uploaded nothing, and left that care-only release live, so the combined
output now lives inside `apps/player-care/` where the deploy config
accepts it; then the director ran the exact command above and the
combined docs/Terms release completed
(Firebase CLI: 191 files, upload complete, version finalized, release
complete, Deploy complete, exit 0). The director then fetched every one
of the 191 files over ordinary HTTPS at the custom origin and compared
its bytes with the reviewed generated output: all HTTP 200 and
identical. The director also checked 28 clean routes (root, x-default
and five-language care pages, docs home/course/Lesson 1/reference):
HTTP 200, exact bytes, canonical custom origin, no NUL; missing route
HTTP 404; a browser followed the live course link to the docs home.
Local proof, director-supplied under `builds/verify/`:
`release4-final-combined-hosting-deploy-retry.log`,
`release4-final-combined-hosting-live-proof.json`,
`release4-final-firebase-site.jpg`. Nothing in this repo deploys. No
tokens or credentials live here; the director runs the existing
authenticated CLI. Website publication only: this record makes no claim
about the native 4.0.0 store submissions; native version 4.0.0 is not
claimed submitted, approved, or live. The care-only `firebase.json`
(`public: dist`) plus `.firebaserc` remain for inspection and for the
exact-dist check; they are not the deploy config. The public origin is the
custom domain `https://moonlitbeacon.hyo.dev`, connected to Hosting with
server-specified DNS outside this repo; the default site URL and native
auth callback stay as configured. Deploys write a generated hash cache
under `apps/player-care/.firebase/`; the app `.gitignore` keeps it and
`hosting-dist/` out of Git so generated output and repeat deploys never
dirty the tree.
