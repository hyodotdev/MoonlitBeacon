# Player-care publication note (4.0.0)

Short deploy handoff for the combined public site: the privacy/support/terms
pages plus the course/reference under `/MoonlitBeacon/` from one Hosting
deploy. Nothing here is published by the implementer; the director deploys
only after inspection. The director has deployed the inspected
privacy/support care-only release and verified all 18 routes over ordinary
HTTPS. The final combined docs/Terms release remains director-operated and
pending; do not treat its URLs as live until the director confirms. No
deploy was performed from this repo copy.

## Target

- Public origin `https://moonlitbeacon.hyo.dev` (custom domain registered
  in Firebase Hosting with server-specified DNS; DNS done outside this repo).
- Deploy target stays the existing default site `moonlitbeacon-778ee`
  (`firebase.hosting.json` `site`, `--project moonlitbeacon-778ee`). One
  prior hosting release exists (the director's verified care-only
  privacy/support deploy); the combined deploy adds the course/reference
  and Terms without touching Firestore.
- Default site URL and native auth callback remain as configured; they are
  not public site URLs and are never printed in player copy.
- Hosting-only: `public: hosting-dist` (generated combined output at
  `apps/player-care/hosting-dist/`: 49 inspected care files at the root,
  the 142-file docs build with 26 pages under `MoonlitBeacon/`),
  `cleanUrls`, nothing else. No rewrites, functions, or other services;
  the real care `404.html` serves missing pages. The root `firebase.json`
  stays Firestore-only. `public` stays inside the Firebase project
  directory (the folder holding `firebase.hosting.json`); the CLI refuses
  anything outside it before upload.
- Docusaurus canonical `url` is the custom origin with `baseUrl`
  `/MoonlitBeacon/` unchanged, so the GitHub Pages mirror keeps working.
  Care nav links `/MoonlitBeacon/` with five localized labels; the docs
  navbar/footer link back to `/en/privacy`, `/en/support`, and
  `/en/terms`.
- Game contact settings point at the custom origin via the contact contract
  (`configure-store-contact.mjs` dry-run then apply):
  `https://moonlitbeacon.hyo.dev/{locale}/privacy|support` in `project.godot`.
- Current contact instructions in `notes/release/store-page.md` record the
  same custom-origin URLs. No ChatGPT origin remains in active game, site,
  or store-contact copy.

## URLs to verify after deploy

- `https://moonlitbeacon.hyo.dev/{en,ko,ja,zh-Hans,zh-Hant}/privacy`,
  `/…/support`, and `/…/terms` (15 pages)
- `…/privacy`, `…/support`, and `…/terms` (English x-default, full bodies)
- `…/`, `…/{locale}/` (choosers), `…/404.html`
- `…/MoonlitBeacon/` (docs home), `…/MoonlitBeacon/course` (course guide),
  `…/MoonlitBeacon/course/chapter-01` (Lesson 1),
  `…/MoonlitBeacon/docs/intro` (reference entry)

## Copy sources (section by section)

- Privacy sections 1–8: `privacy-four-zero-draft.md` statements S1–S8
  (sign-in, processing scope, player ID, cloud saves, Hall, deletion,
  guest/offline, analytics-off). Draft audit notes are not published;
  no retention deadline is stated anywhere.
- Retention: account, checkpoint, and Hall records have no configured
  automatic expiry and remain until account deletion (no TTL configured in
  source; see draft audit item 2 for why no deadline is promised).
- Sign-out vs deletion vs device files: sign-out ends the SDK session and
  the live cloud link and deletes nothing (`player_account.gd` sign-out
  path); cloud deletion removes Hall, checkpoint, reservation, profile,
  then the sign-in (`cloud_account.gd` plan); on-device bindings and saves
  stay until reinstall or storage clear (`_clear_cloud_binding` is
  in-memory only).
- Native sessions: gameplay save files contain no sign-in tokens; the game
  holds tokens in memory for its own record access; cross-launch sessions
  persist under Firebase/provider SDK and OS storage (native plugin
  session handling; game code adds no scopes and stores no profile/token
  itself).
- Privacy purchases: `iap-store-setup.md` privacy baseline (IAPKit
  receipt/token verification; validation/order/IP/result/timing retained
  for restoration, refunds, fraud, statistics, legal duties; no card or
  store-password data to app/developer) plus the already-published
  processor disclosure below (purposes, statistics event scope, policy
  links).
- Support requests: matched through the player ID; deletion requests over
  purchase records are forwarded to the purchase-verification processor
  (same baseline's deletion-request passage). No invented duration or
  processor policy URL.
- Support products: `store-localizations.csv` at build time — 7 permanent
  (Supporter, 5 heroes, Lantern Colors) + 3 coin packs granting exactly
  1, 5, 10. Permanent means store-account restore, never irrevocable
  ownership after a refund. No legacy bundle sale, no consumable claim.
- Publisher/support: `store-page.md` (Hyo Dev, copyright 2026 Hyo Jang,
  `hyo@hyo.dev`) and its GitHub Issues bug-report link.
- Terms: `apps/game/localization/gate_entry.csv` rows `gate.terms.title`
  and `gate.terms.p1`–`p8`, read at build time with the existing CSV
  parser and published verbatim (escaped) on `/terms` and
  `/{locale}/terms`. Only the surrounding labels are localized site copy;
  the agreement itself is unchanged and never duplicated in site files.

## Published processor/support disclosure (preserved, not new)

Source: the existing owned player-care site's English privacy page, read
by the director on 2026-10-04 with all three destination pages verified:

- `https://moonlit-beacon-support.hyodev.chatgpt.site/en/privacy`

That old origin stays only as this citation. It is not linked from any
player page, game setting, or store instruction.

Preserved facts now mirrored on all five privacy pages (purchases §9,
support requests §10):

- IAPKit verifies store/product with Apple JWS or Google purchase token.
- Its validation record may retain transaction/order IDs, store response,
  request IP, result, and processing duration, serving entitlement
  grants/restores/revocations, refunds, fraud/duplicates, diagnosis, and
  service statistics.
- IAPKit may send a project-first-valid-receipt event and store kind to
  Mixpanel; the event excludes purchase token, transaction ID, and IP.
  Convex is the infrastructure provider. Exact policy links (player pages
  link all three):
  `https://kit.openiap.dev/privacy-policy`,
  `https://www.convex.dev/legal/privacy`,
  `https://mixpanel.com/legal/privacy-policy/`
- Emailing support processes the supplied email, message, and chosen
  attachments with the email service provider; kept only while needed for
  the request and legal duties; minimum order detail only, never a full
  receipt or credentials.
- Providers retain validation records as necessary for
  restoration/refunds/fraud/statistics/accounting/legal obligations with
  no uniform expiry; legally required records can remain and
  processor-held requests can be relayed.
- Processing may occur outside the player's country (no country list or
  legal basis invented).

## Deploy (director only, from the repo root)

```bash
pnpm hosting:build
pnpm hosting:check
cd apps/player-care && firebase deploy --only hosting --config firebase.hosting.json --project moonlitbeacon-778ee
```

The build step renders a fresh care `dist/`, a fresh docs build, and the
combined `apps/player-care/hosting-dist/`; the check step verifies exact
parity (49 care + 142 docs files), all local links, no
NUL/notes/secrets/symlinks, the real `404.html`, and the narrow
hosting-only config, including the in-project `public` boundary. To
confirm a boundary by hand, delete or flip one byte under
`apps/player-care/hosting-dist/`, watch `hosting:check` fail, then re-run
`pnpm hosting:build` to restore (composition is deterministic: same
inputs, same bytes).

An earlier combined attempt with `public: ../../builds/hosting` was
refused by the Firebase CLI before upload ("outside of project
directory"); that refusal left the verified care-only site live and
uploaded nothing. The final combined docs/Terms release remains
director-operated and pending; nothing in this repo deploys or claims
final live success.

Then open all 15 localized URLs plus `/privacy`, `/support`, and `/terms`,
the docs home, course guide, and Lesson 1 over the custom origin, confirm
live TLS/HTTP, and confirm Settings › Privacy/Support in the game open them
per locale before store metadata relies on them.

## Deliberately not done

- No deploy, no network calls, no DNS writes, no credentials.
- Historical evidence URLs, fixture URLs, native callback URLs, and
  Firebase project identifiers are unchanged.
- No change to the Terms agreement text itself, and no auth, IAP, save,
  gameplay, asset, course-content, or version change. Only
  `docusaurus.config.ts` origin/navbar/footer (now with the Terms link)
  changed on the docs side; lesson and reference prose are untouched.
