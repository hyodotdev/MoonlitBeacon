# Player-care publication note (4.0.0)

Short deploy handoff for the new privacy/support site. Nothing here is
published; the director deploys only after inspection. Publication is not
verified; do not treat these URLs as live until the director confirms TLS.

## Target

- Public origin `https://moonlitbeacon.hyo.dev` (custom domain registered
  in Firebase Hosting with server-specified DNS; DNS done outside this repo).
- Deploy target stays the existing default site `moonlitbeacon-778ee`
  (`firebase.json` `site` + `.firebaserc` default project). Zero existing
  hosting releases, so the first deploy overwrites nothing.
- Default site URL and native auth callback remain as configured; they are
  not public site URLs and are never printed in player copy.
- Hosting-only: `public: dist`, `cleanUrls`, nothing else. No rewrites,
  functions, or other services.
- Game contact settings point at the custom origin via the contact contract
  (`configure-store-contact.mjs` dry-run then apply):
  `https://moonlitbeacon.hyo.dev/{locale}/privacy|support` in `project.godot`.
- Current contact instructions in `notes/release/store-page.md` record the
  same custom-origin URLs. No ChatGPT origin remains in active game, site,
  or store-contact copy.

## URLs to verify after deploy

- `https://moonlitbeacon.hyo.dev/{en,ko,ja,zh-Hans,zh-Hant}/privacy` and
  `/…/support` (10 pages)
- `…/privacy` and `…/support` (English x-default, full bodies)
- `…/`, `…/{locale}/` (choosers), `…/404.html`

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
  `hyo@hyo.dev`) and its GitHub Issues bug-report link. Terms stay in
  `apps/game/localization/gate_entry.csv`, referenced only.

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

## Deploy (director only, from `apps/player-care/`)

```bash
pnpm player-care:check
firebase use moonlitbeacon-778ee
firebase deploy --only hosting
```

Then open all 10 localized URLs plus `/privacy` and `/support` over the
custom origin, confirm live TLS/HTTP, and confirm Settings ›
Privacy/Support in the game open them per locale before store metadata
relies on them.

## Deliberately not done

- No deploy, no network calls, no DNS writes, no credentials.
- Historical evidence URLs, fixture URLs, native callback URLs, and
  Firebase project identifiers are unchanged.
- No Terms, auth, IAP, save, gameplay, asset, course-hosting, or version
  change.
