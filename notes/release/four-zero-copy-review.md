# 4.0.0 copy review note

Short work note for the 4.0.0 account/journey/art copy refresh. Existing
historical notes stay historical; this file separates what source
confirms from what is still pending.

## Round 4 correction (Chinese localization errors)

Two confirmed errors in added Chinese passages were fixed narrowly,
with no behavior-claim or other-language changes:

- Moon gate term: `关门`/`關門` (closing a door) → `月之门`/`月之門`
  in 6 store-page spots (2 description paragraphs, 4 release-note
  bullets) and 2 privacy-draft S3 spots. Matches the baseline
  descriptions' own `月之门`/`月之門` usage.
- Traditional offline sentence: garbled `可以訪客身分享線使用` →
  `基礎玩法與本機紀錄，訪客身分可離線使用` (guest play works
  offline); the online-requirements sentence is unchanged.
- Adjacent typo in the same added passages: `决不`/`決不` → `绝不`/
  `絕不` in both privacy-draft item 2 translations.
- Product CSV cells untouched; all product rows remain byte-identical.

## Round 3 correction (checklist account-data disclosures)

The store-page re-audit items still claimed a 4.0.0 analytics-disabled
submit collects only purchase-verification data and prescribed
not-linked labels. Both items were replaced with an evidence-based
audit covering Firebase sign-in, public player ID, private
account-to-ID ownership, checkpoint saves, Hall entries, and existing
purchase verification. The new items separate collected/processed data
from publicly displayed Hall fields, tie email/profile answers to SDK
scopes plus final native consent/build evidence, record no final label
answers, and keep optional analytics as a separate default-off feature
whose shipped config must be inspected. Final store privacy answers
and public-site publication stay pending until performed by the
director. Product CSV fields, 4.0.0 listing copy, and the corrected
privacy draft were left intact — no direct factual inconsistency with
them was found.

## Round 2 correction (privacy disclosure scope)

The round-1 draft's S2 over-claimed: tokens, UIDs, and profile handling
are not confined to native login calls. The privacy draft was repaired
without touching the accepted listing files:

- S2 replaced in the inventory and all five translations: Firebase and
  the chosen provider process identifiers, sign-in/session credentials,
  and consent-gated profile fields; the game keeps its public ID,
  private account-to-ID link, and checkpoint saves; email/profile never
  appears in public Hall rows.
- Three-way UID/token mapping, each cited: hashed server reference in
  the on-device bindings list only (`player_account.gd`
  `uid_binding_hash()`); raw `uid` in the owner-private backend
  profile/reservation/checkpoint records (`cloud_schema.gd` field
  lists, `cloud_identity.gd`/`cloud_checkpoint.gd` writers, rules
  restrict reads to the owning account); ephemeral in-memory tokens
  from `id_token_ready` to the Bearer header (`native_identity_adapter
  .gd`, `player_account.gd`, `production_host.gd`,
  `cloud_transport.gd`).
- No native-only token claim, no blanket no-logs/no-persistence claim,
  no implication that provider profile data is never processed. Google
  default scopes (`openid/email/profile`) and the provider-documented
  Apple default scope behavior are audit items, as are SDK-side logs
  and session persistence.
- Player-facing text simplified: no payload/schema/atomic-commit/
  best-effort/field-name jargon. Sign-out (fresh guest, old data kept)
  versus signing back in (same provider restores that account's ID
  and saves) is explained without a single-permanent-ID claim.
- Deletion is stated as verified intended behavior (cloud records
  first, sign-in after acknowledgement); the iOS Apple re-confirm
  branch is designed, not device-proven — iPad delete/re-confirm
  proof is pending.
- Analytics is stated as off-unless-enabled (export config plus
  Settings consent), never declared from defaults alone; the final
  export configuration must be inspected before release.
- The rules gate now distinguishes the deployed account/save/Hall
  ruleset (deployment proof already held; independent readback still
  appropriate) from the optional analytics TTL, which is never a
  mandatory TTL on persistent account checkpoints.

## What this round changed

- `notes/release/store-localizations.csv`: five Apple keyword cells only.
  `pixel`/`ドット`/`像素` terms became painted-art terms and
  `offline`/`オフライン`/`离线` terms became cloud terms. All ten
  product IDs, types, names, descriptions, and review notes are
  byte-identical; no hero or coin copy changed.
- `notes/release/store-page.md`: release version 3.0.0 → 4.0.0, itch
  tags `pixel-art` → `painted-art`, keyword tables synced with the CSV,
  account/ladder rows rewritten for guest + configured sign-in and the
  Hall board, five full descriptions refreshed for painted art,
  guest/account entry, checkpoint resume, and the Hall, ten release-note
  blocks rewritten for 4.0.0, and the analytics checklist re-aimed at
  the 4.0.0 submit (still unchecked).
- `notes/release/privacy-four-zero-draft.md` (new): eight-statement
  five-language privacy delta with a source-citation table and audit
  items. Draft for review only; the public site is outside this repo.
- `notes/release/four-zero-copy-review.md` (new): this file.

Short descriptions, subtitles, and promotional text are unchanged: they
make no pixel/offline/account claim, so the full descriptions carry the
new account/save/Hall copy instead.

## Confirmed in source (copy may claim)

- Painted art: `apps/docs/docs/assets/manifest.md` (painted masters,
  4.0.0 world biomes, "where the art moved from pixels to a painting").
- Guest door everywhere incl. offline; Google/Apple/Play Games readiness
  gated per provider: `production_host.gd` `begin_guest()`,
  `providers_for_entry()`; `moonlit_identity.gd` `get_capabilities()`,
  `_ready_providers()`.
- Anonymous auth identity on supported devices: native
  `signInAnonymously` on Android (`MoonlitIdentityPlugin.kt`) and iOS
  (`MoonlitIdentityIos.mm`).
- `google`/`apple` are shared provider identities; `play_games` is the
  distinct Android-only profile, never merged: `identity_adapter.gd`
  header. This build stages no Play Games app ID, so copy names no
  Play Games entry.
- Durable immutable `MB-` ID; linking keeps UID, ID, and checkpoint
  ownership: `player_account.gd`, `cloud_identity.gd`. Sign-out mints
  a fresh guest while old data stays; signing back in with the same
  provider restores that account's ID and saves
  (`adopt_canonical_id()`, `Journey.use_account()`).
- Ephemeral token use beyond native calls: `id_token_ready` re-emit to
  in-memory use and the transport Bearer header; the game writes no
  token into its save files (`native_identity_adapter.gd`,
  `player_account.gd`, `production_host.gd`, `cloud_transport.gd`).
- Raw account reference in owner-private backend records versus hashed
  reference in the on-device bindings list only (`cloud_schema.gd`,
  `cloud_identity.gd`, `cloud_checkpoint.gd`, rules,
  `uid_binding_hash()`).
- One private versioned checkpoint per account, local-first, checked
  downloads, explicit keep-side choice, no purchase data in saves:
  `cloud_checkpoint.gd`, `cloud_coordinator.gd`, `cloud_schema.gd`.
- Hall: one entry per player ID (hero/score/progress/app version/
  stamp), public reads, owned monotonic writes, derived shared ranks:
  `cloud_hall.gd`, `firestore.cloud.addition.rules`.
- Verified cloud-first deletion order; iOS Apple re-confirmation
  designed, device proof pending: `cloud_account.gd`,
  `player_account.gd` `delete_account()`, `production_host.gd`.
- Analytics off unless export config plus Settings consent agree;
  verification flow unchanged: `firebase_config.gd`, `analytics.gd`,
  `iapkit_http_transport.gd`.

## Ambiguities flagged (copy stays conservative)

- itch.io direct APK: whether that build stages identity config (and
  therefore attempts background anonymous registration) is not settled
  from source, so the itch paragraph claims guest play only and drops
  the old "no account" absolute.
- Offline fallback: "core play and local records work offline as a
  guest" is the preserved distinction. Anything needing sign-in, cloud
  saves, the Hall, store, or verification needs a connection.
- Hero product prose and reviewer navigation were left untouched: no
  source-confirmed mismatch, and the Continue Coin review-note contract
  test reads the real CSV.
- SDK-side behavior is not game-code behavior: what provider sheets
  and SDKs process, log, or persist (UID-carrying auth logs,
  session caches, default scope grants) stays an audit item against
  provider documentation, never a game-copy guarantee.

## Remaining release gates (pending, not complete)

- Apple Services ID/key setup for the Android Apple flow.
- iPad terminal authentication tests, including delete/re-confirm
  proof for the Apple re-auth branch.
- Actual store purchases on the final build (current-build evidence is
  guest/Google cache restore only).
- 4.0.0 store upload, review submit, PR, and remote merge: remote
  stores hold 3.0.0 only; nothing has been uploaded or merged.
- Marketing screenshot recapture permission: finished shots still show
  only the local ladder while copy now describes the Hall.
- Independent current-ruleset readback for the deployed
  account/save/Hall rules (deployment and ownership proof already
  held); store-page checklist items stay unchecked. The optional
  analytics TTL is a separate item and never a mandatory TTL on
  persistent account checkpoints, saves, or Hall rows.
- Final export configuration inspection (analytics answers), plus
  store privacy/Data-safety/privacy-label answers re-audited against
  the submit build; privacy draft reviewed before any website edit.

## Follow-up outside this brief

- `scripts/lib/app-store-release.mjs` still generates the App Review
  note "No app account or demo login is required." That line is stale
  for 4.0.0 store builds but scripts are out of scope here; the
  director should schedule a script update, not a copy workaround.
