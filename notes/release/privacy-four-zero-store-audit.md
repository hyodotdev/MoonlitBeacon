# 4.0.0 store privacy declaration audit (source-backed inventory)

Status: **audit only, not a submission**. Nothing here claims the release is
ready, the declarations are submitted, or any store/console step is done.
Every recommendation cites production source; each row separates what the
source proves (fact) from the proposed store category (interpretation).
Unresolved evidence is named, never filled in.

Scope: the final account/cloud-save release (guest + configured Google/Apple
sign-in, cloud saves, Hall board, IAP verification). The legacy global ladder
and optional gameplay analytics are covered only to show they stay off in the
submit configuration.

Companion reading: `notes/release/privacy-four-zero-draft.md` (site-text
delta, draft only) and `apps/player-care/content/en.mjs` (published 4.0.0
policy wording). This file is the store-form inventory; it does not change
either of them.

## How to read this file

- **Fact** = what production code, config-read logic, rules, or repo notes
  prove. Cited as `path:line`.
- **Proposed** = the suggested store-form answer derived from the fact. The
  director makes the exact UI choice and verifies it.
- **Open** = evidence this copy cannot supply (provider-rendered sheets,
  server-side retention, staged export values, device branches). Listed in
  each row and again in §7.

Official references below were reviewed by the director, not fetched here
(this copy has no network). They are the authority for every Open item:

- https://firebase.google.com/docs/android/play-data-disclosure
- https://firebase.google.com/docs/ios/app-store-data-collection
- https://firebase.google.com/support/privacy
- https://support.google.com/googleplay/android-developer/answer/10787469
- https://support.google.com/googleplay/android-developer/answer/13327111
- https://developer.apple.com/app-store/app-privacy-details/

## 0. Shipped data-flow map (facts)

Direct network endpoints in game source (the only hosts game code calls):

| Endpoint | Caller | What travels |
| --- | --- | --- |
| `https://firestore.googleapis.com/v1` | `cloud_transport.gd:187-195`, `analytics.gd` via `firebase_config.gd:53-62`, legacy `global_ladder.gd:205` | Authenticated profile/reservation/checkpoint/Hall documents; optional analytics events (disabled, §5); legacy scores (disabled, §5) |
| `https://kit.openiap.dev/v1/purchase/verify` | `iapkit_http_transport.gd:9` via `godot_iap_backend.gd:221` | Store kind, expected product id, Apple JWS or Google purchase token (`godot_iap_backend.gd:210-217`) |
| Firebase Auth + provider endpoints | Native SDKs only (no URL in game source) | Anonymous registration, Google/Apple/Play Games credential exchange, ID-token mint (see SDK list) |

No other `https://` call target exists in `apps/game/scripts`
(verified by grep; the only other match is the `https://` prefix guard in
`ui/external_links.gd:93-95` for outbound site links). Game code sets no
`User-Agent` header: `cloud_http_sender.gd:49-53` sends caller headers
as-is, and callers supply only content type, accept, and authorization
(`cloud_transport.gd:131-135`; analytics sends content type only).
Whatever user agent the engine stack attaches is outside game source (Open).

Native SDKs actually included (direct dependencies only):

| Platform | Direct identity/auth deps | Not a direct dep |
| --- | --- | --- |
| Android | `play-services-games-v2:20.1.2`, `firebase-auth:24.0.0`, `credentials:1.3.0`, `credentials-play-services-auth:1.3.0`, `googleid:1.1.1`, `kotlinx-coroutines-android:1.10.1` (`android/build.gradle.tmpl:53-65`) | No Analytics, Crashlytics, Installations, or ads artifact |
| iOS | `FirebaseAuth 11.0.0`, `GoogleSignIn 7.1.0` (`ios/Podfile.tmpl:18-19`); system `AuthenticationServices` for the Apple sheet (`MoonlitIdentityIos.mm:39`) | Same: no Analytics, Crashlytics, Installations, or ads artifact |

Fact: no Firebase Analytics, Crashlytics, Installations/Device-ID, or
advertising SDK is declared anywhere in the identity addon, `project.godot`,
or the pinned build list. Do not infer one from Firebase branding (Open:
transitive closure of `firebase-auth` is decided from the official Firebase
disclosure docs, not from this repo).

Export-config read logic (verified, not guessed):

- `apps/game/firebase.cfg` is **absent** from this copy (confirmed by `ls`).
  `firebase_config.gd:17-43` returns all-false/empty defaults when the file
  is missing, and `configured_for_analytics()` additionally requires
  `enabled + ingestion_hardened + key` (`firebase_config.gd:46-50`).
- `apps/game/moonlit_identity.cfg` is **absent** from this copy. When it is
  missing, every staged value reads empty (`moonlit_identity.gd:676-699`),
  Firebase gates refuse guests and providers (`moonlit_identity.gd:154-168`),
  and each provider gates on its own keys independently
  (`moonlit_identity.gd:399-456`). Google needs `server_client_id`
  (Android) or `ios_client_id` (iOS); Apple needs its per-platform enabled
  flag; Play Games additionally needs `play_app_id`
  (`moonlit_identity.gd:185-206`) and a stamped manifest `APP_ID` that the
  native side checks fail-closed (`MoonlitIdentityPlugin.kt:646-658`).
- Staging writes that file only for the duration of an export and removes it
  afterwards (`scripts/lib/player-identity-build.mjs`, header comment and
  `installIdentityConfig`/`cleanIdentityConfig`). The actual staged values
  for the final exports (Google + Apple configured, Play Games unconfigured)
  live in director-held environment, not in this copy (Open: director
  inspects the staged file at export; see §7).

## 1. Google Play Data safety (proposed answers)

Prior submit baseline (what the old declaration says): purchase history and
diagnostics collected, optional, not shared, not ephemeral; purposes App
functionality, Analytics, Fraud prevention/security/compliance; encryption in
transit Yes (`notes/release/iap-store-setup.md:42-66`). Verification flow is
unchanged since (`privacy-four-zero-draft.md` S8), so rows 6-7 below carry
that baseline forward; rows 1-5 are new for 4.0.0 accounts/saves/Hall.

Director-observed Play draft (not this file's proposal): name, email, and
User IDs saved with App functionality + Account Management; Other Actions
saved with App functionality; saved for review. The Proposed columns below
are independent recommendations; per-row notes say where they match that
observed draft.

Account question first: the app **does** create accounts in configured
builds. Guest entry automatically starts anonymous Firebase registration
(`production_host.gd:371-380` → native `signInAnonymously`, `MoonlitIdentityPlugin.kt:268`
/ `MoonlitIdentityIos.mm:567`), and Google/Apple buttons offer OAuth where
staged (`production_host.gd:299-328`, `moonlit_identity.gd:185-206`).
Proposed account-type answers: OAuth (Google, Apple) + Other (anonymous
guest). Play Games is not offered: its readiness key is unstaged and both
the GDScript gate and the native manifest check refuse it (cited in §0).

| # | Data type (Play) | Proposed collected? | Required / optional | Purposes (proposed) | Shared? | Source fact |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Personal info > User IDs (Firebase UID; `MB-` player ID) | Yes | Required | App functionality, Account Management | No (service providers only, §6) | Fact: UID minted by anonymous/provider sign-in (natives, §0); `MB-` + 32 hex minted pre-play (`player_account.gd:433-436`); UID sent in profile/reservation/checkpoint documents (`cloud_identity.gd:67-89`, `cloud_checkpoint.gd:73-83`); public ID sent in profile/reservation/Hall (`cloud_schema.gd:32-44`). Registration runs automatically on guest entry with no opt-out toggle (§4). Proposed Account Management follows the account use in source: UID authenticates and owns the private records, linking keeps the same UID with no second registration (`cloud_identity.gd:208-216`), and sign-out/sign-back-in rotates then restores the same ID and saves (`player_account.gd:304-313` rotation, `adopt_canonical_id` restore per `privacy-four-zero-draft.md` S3), consistent with the director's reading of official Firebase disclosure purposes. Matches the director-observed Play draft purposes for User IDs. |
| 2 | Personal info > Email address | Yes, Google path; Apple path Open | Optional | App functionality, Account Management | No (service providers only) | Fact: game code adds no Google scopes and never reads/stores/logs email (`MoonlitIdentityPlugin.kt:69-77`, `MoonlitIdentityIos.mm:30-37`, `identity_adapter.gd:30-31`); Google SDK authenticates under its own default `openid/email/profile` scopes (same headers). Provider sign-in is optional: guest play, store, restore, and resume all work without it (`app-store-release.mjs:748-757`, `production_host.gd:355-381`). Proposed Account Management covers the account-authentication/recovery use where the sheet grants email (`privacy-four-zero-draft.md` S2: Firebase and the chosen provider process identifiers and consent-gated profile fields to authenticate and recover the account), consistent with the director's reading of official Firebase disclosure purposes. Matches the director-observed Play draft purposes for email. Open: which fields the shipped consent sheet actually grants; Apple provider-default scope behavior on both platforms (game requests none: `MoonlitIdentityIos.mm:783`, `MoonlitIdentityPlugin.kt:459-462`). |
| 3 | Personal info > Name | Same as row 2 | Optional | App functionality, Account Management | No (service providers only) | Fact: same scope evidence as row 2; game-side display-name handling is zero: grep over `scripts/net|cloud|iap|analytics` finds only never-log/never-store comments plus the unrelated hero `display_name` in `production_host.gd:283-284`; natives never read profile fields (`MoonlitIdentityIos.mm:647-648,829,840`). Proposed Account Management same basis as row 2 (authentication/recovery use where granted, per `privacy-four-zero-draft.md` S2 and the director's reading of official Firebase disclosure purposes). Matches the director-observed Play draft purposes for name. Open: same sheet/scope verification as row 2. |
| 4 | Photos and videos | Not collected (game); provider-side Open | n/a | n/a | n/a | Fact: no photo-URL or photo-byte handling exists in game or bridge code — no `getPhotoUrl`/`photoUrl`/photo reference in GDScript or either native file (verified by grep; only comment at `MoonlitIdentityIos.mm:829` saying the fields are never touched, and the GDScript scrub list at `moonlit_identity.gd:633-634`). Distinguish: the game neither downloads a profile URL nor uploads photo bytes. Open: whether provider/Firebase server-side profile storage counts — official provider docs decide. |
| 5 | App activity > Other actions (checkpoint progress; Hall hero/score/cycles/version) | Yes | Required | App functionality | No; Hall rows are user-visible by design (see note) | Fact: sealed checkpoints queue and upload automatically (`cloud_coordinator.gd:854-878`, catch-up `823-852`); payload is pure gameplay state validated by `journey.gd:388-457` with purchase/ledger keys rejected (`cloud_schema.gd:182-195`); Hall row carries only ID/hero/score/cycles/release/stamp (`cloud_hall.gd:85-99`), reads are public by rule while writes are owner-only and monotonic (`firestore.cloud.addition.rules`, `mb_hall_v1` block). Matches the director-observed Play draft purpose for Other Actions (App functionality). Note: public Hall display is in-app public content, not third-party sharing; declare per the official sharing definition (§6). |
| 6 | Financial info > Purchase history | Yes (carry forward) | Optional | App functionality, Analytics, Fraud prevention/security/compliance (carry forward) | No | Fact: only purchasers/restorers send anything: store + expected product + JWS/token per verification (`godot_iap_backend.gd:192-222`); keys/tokens never in logs/errors (`iapkit_http_transport.gd:3-7`, `iap_store.gd:260`). Prior purposes at `iap-store-setup.md:55-58`. |
| 7 | App info and performance > Diagnostics (validation record: txn/order ids, store responses, result, processing duration, request IP) | Yes (carry forward) | Optional | Same as row 6 (carry forward) | No | Fact: what the app sends is row 6; what the server retains is documented secondhand in `iap-store-setup.md:44-50` and `en.mjs:129-131` (verify against IAPKit docs at submit, Open). Game's own analytics stays disabled (§5) and ships no crash reporter (§0 SDK list), so no other diagnostics row is proposed. |
| 8 | Device or other IDs | Not collected (game) | n/a | n/a | n/a | Fact: analytics header forbids advertising/device IDs and the event allow-list cannot carry them (`analytics.gd:3-8,44-68`); no ad-ID/device-ID API in either native file; no Installations dep (§0). Open: Firebase-internal identifiers per official Firebase disclosure docs. |
| 9 | Location | Not collected (game) | n/a | n/a | n/a | Fact: no location API, no IP/coordinate field in any payload (§0 endpoints, `cloud_schema.gd` field lists). Open: IP-inferred location is a service-side question under the official Play guidance; request IP reaches Firestore/IAPKit servers as with any HTTPS call. |
| 10 | Crash logs | Not collected (game) | n/a | n/a | n/a | Fact: no crash-reporting SDK (§0) and no crash upload path in game source. Open: Firebase Auth's own error/diagnostic traffic per official Firebase docs. |

Encryption in transit: propose **Yes**. Fact: both game-called endpoints are
`https://` constants (`firebase_config.gd:14`, `cloud_schema.gd:12`,
`iapkit_http_transport.gd:9`); Android export sets internet permission with
no custom permissions (`export_presets.cfg:60-61,165-166`). SDK-side TLS is
provider behavior (Open only in the sense that game source cannot show it).

Ephemeral: sign-in tokens are the one transient credential: native hands the
ID token only to its own `moonlitGetIdToken` answer
(`MoonlitIdentityPlugin.kt:792-833`, `MoonlitIdentityIos.mm:1012-1060`),
it rides one in-memory re-emit (`native_identity_adapter.gd:215-223`,
`player_account.gd:502-520` with a never-written comment), is held only in
host memory (`production_host.gd:515-522,1596-1600`), and travels only as a
request Bearer [REDACTED] never written to results (`cloud_transport.gd:126-136`).
No Play data type maps to tokens directly; mention only if the form asks.

## 2. Apple App Privacy (proposed labels)

Director-observed Apple state (not a proposal): types are being prepared,
not yet published. Nothing below claims a saved Apple draft selection.

Official-definition basis (director-read at
https://developer.apple.com/app-store/app-privacy-details/): Product
Interaction explicitly includes saved place in a game; Gameplay Content
explicitly includes saved games. Rows 3 and 8 therefore label the same
retained functional saves under the two matching Apple types; neither row
is an analytics toggle.

| # | Data type (Apple) | Proposed collected? | Linked? | Tracking? | Purposes (proposed) | Source fact |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Contact Info > Email Address | Yes, Google path; Apple path Open | Yes | No | App Functionality | Same scope facts as Play row 2. Linked because the address authenticates the Firebase account that owns the private records. Open: shipped-sheet grant + Apple defaults. |
| 2 | Contact Info > Name | Same as row 1 | Yes | No | App Functionality | Same facts as Play row 3. |
| 3 | User Content > Gameplay Content (checkpoint saves; Hall rows) | Yes | Yes | No | App Functionality | Same upload facts as Play row 5. Retained per the director-read official definition (Gameplay Content explicitly includes saved games). Linked: checkpoint documents are keyed by UID and readable only by the owning account (`firestore.cloud.addition.rules`, `mb_checkpoints_v1` block); Hall rows are keyed by the public ID bound to that account. |
| 4 | Identifiers > User ID (Firebase UID; `MB-` player ID) | Yes | Yes | No | App Functionality | Same identity facts as Play row 1. On-device bindings store only the UID hash (`player_account.gd:124-132`); backend rows carry the raw UID privately (`cloud_schema.gd:32-44` + owner-only rules). |
| 5 | Identifiers > Device ID | Not collected | n/a | n/a | n/a | Same facts as Play row 8. |
| 6 | Purchases > Purchase History | Yes (carry forward) | Yes | No | App Functionality, Analytics (carry forward) | Same send facts as Play row 6; prior purposes at `iap-store-setup.md:52-54`. |
| 7 | Diagnostics > Performance Data + Other Diagnostic Data (IAPKit validation record) | Yes (carry forward) | Yes | No | App Functionality, Analytics (carry forward) | Same retention facts as Play row 7 (secondhand; verify against IAPKit docs). No game crash reporter (Play row 10 facts). |
| 8 | Usage Data > Product Interaction (retained cloud checkpoint/place/progress; NOT optional analytics events) | Yes | Yes | No | App Functionality | Fact (functional, collected): sealed checkpoints queue and upload automatically (`cloud_coordinator.gd:854-878`, catch-up `823-852`); stored document carries `uid, revision, payload, schema, updated_at` (`cloud_schema.gd:38-40`, `cloud_checkpoint.gd:73-83`); payload is validated gameplay place/progress state (`journey.gd:388-457`: cycle, zone_index, route, run_seed, hero_path, relic_stacks, level, kills, kill_score, survived, lit_count, guardian_meetings, places_seen, settled_score, gate_direction, saved_at_unix, journey/checkpoint ids) with purchase/ledger keys rejected (`cloud_schema.gd:182-195`); rows are keyed by UID and readable only by the owning account (`firestore.cloud.addition.rules`, `mb_checkpoints_v1` block). Official mapping (director-read at https://developer.apple.com/app-store/app-privacy-details/): Product Interaction explicitly includes saved place in a game, so this retained checkpoint/place/progress data is proposed Yes/linked/not tracking/App Functionality. Separate fact (analytics, NOT collected): optional gameplay analytics stays export-disabled in this submit — `firebase.cfg` absent, `configured()` false, consent UI never shown, `enabled()` false, send path closed (§5 item 1). That disabled toggle does not suppress this functional label; a later analytics-enabled build would add analytics events alongside it, not replace it. |
| 9 | Photos or Videos; Precise/Coarse Location | Not collected | n/a | n/a | n/a | Photos: Play row 4 facts (zero photo handling). Location: Play row 9 facts. |

Tracking (Apple definition): propose **No** for every row. Fact: no
advertising identifier, no cross-app data combination, no analytics/tracking
SDK in the binary (§0); the app's marketing switch is "Ads: None"
(`store-page.md` shared table). The IAPKit server-side project-statistics
event is processor telemetry that excludes token, transaction id, and IP
per `en.mjs:129-131` (secondhand; verify against IAPKit docs) — flag it to
the director rather than treating it as app-collected tracking data.

## 3. Required-vs-optional trace (guest auto-registration to upload)

This is the chain behind every Required answer above. All steps are
automatic in a configured build; none has an in-app opt-out.

1. Entry taps guest: `begin_guest()` calls `sign_in_guest()` whenever the
   bridge reports supported (`production_host.gd:371-380`). The `local_only`
   escape skips registration only when leaving a held error screen
   (`production_host.gd:349-370`; sole `true` caller at
   `production_entry.gd:335-341`) — first selection always attempts it.
2. Guest sign-in mints an anonymous Firebase UID natively
   (`MoonlitIdentityPlugin.kt:256-282`, `MoonlitIdentityIos.mm:552-584`).
3. The live cloud session configures the coordinator with UID, durable
   guest `MB-` id, in-memory token supplier, and sender
   (`production_host.gd:1129-1184`).
4. Reservation commits the profile + reservation pair immediately in the
   background (`cloud_coordinator.gd:767-800` →
   `cloud_identity.gd:217-266`); linking later keeps the same UID so no
   second registration occurs (`cloud_identity.gd:208-216`).
5. Existing local progress uploads without a new seal
   (`cloud_coordinator.gd:823-852`); every later sealed checkpoint queues
   and flushes automatically (`cloud_coordinator.gd:854-878`).
6. The account's best Hall row submits automatically after adoption
   (`production_host.gd:1240-1255` → `_submit_best`,
   `production_host.gd:1584-1594` → `cloud_coordinator.gd:492`).

Failure softness (why Required is still honest): when background sign-up
fails or the build is unconfigured, play continues locally
(`production_host.gd:343-381`, `privacy-four-zero-draft.md` S7). But in a
configured build the attempt and all uploads are the default with no
player-facing switch, so Required (Play) / collected-and-linked (Apple) is
the reasoned proposal. Provider sign-in (Google/Apple) is the genuinely
Optional branch: core play, store, restore, and resume complete as guest
(`app-store-release.mjs:744-757`).

## 4. Deletion route and reviewer access

In-app deletion (facts):

- Entry: the account panel's delete request reaches
  `production_entry.gd:585-599` (`_on_account_delete`) and calls
  `host.delete_current_account()`.
- Order is fixed: owned cloud rows acknowledge deletion first (Hall,
  checkpoint, reservation, profile in one atomic commit,
  `cloud_account.gd:28-64`), then the native Auth user deletes
  (`production_host.gd:814-852`), then the local UID binding is forgotten
  (`player_account.gd:364-374`), the deleted account's journey slot files
  are removed (`production_host.gd:1806-1817`), and a fresh guest ID
  starts (`player_account.gd:304-313`).
- Residuals that stay on device: other accounts' slots and bindings,
  Vault/IAP/local-ladder/settings/analytics files (separate files the
  deletion path never touches).
- Deleted-slot wording concern (resolved by Brief 161; historical evidence
  preserved): the pre-161 policy line "local saves … stay until you
  reinstall" (old `en.mjs:102`) read absolute while code removes the
  deleted account's own journey slot files
  (`production_host.gd:1806-1817`, called after cloud/native deletion at
  `production_host.gd:814-845`). Brief 161 replaced it with the current
  `en.mjs:102` in this copy: deleting the cloud account removes its cloud
  records and sign-in, its local journey save files, and its on-device
  account binding, while other accounts' local saves and separate files
  (purchases, Vault, settings) remain. The director built, deployed, and
  verified every hosted file per the Brief 162 standing. This audit claims
  no further deletion edge and no native end-to-end proof: iOS Apple
  re-confirm device proof and real-purchase testing stay Open (see §7).
  No file is changed here.
- iOS Apple-linked deletion re-runs the Apple sheet for a fresh
  revocation code by design (`player_account.gd:384-407`,
  `MoonlitIdentityIos.mm:1109-1146`) — device proof pending, see §7.

Web/email deletion (facts):

- Deletion URL `https://moonlitbeacon.hyo.dev/privacy#deletion` matches the
  published policy's `deletion` section id (`en.mjs:94-107`).
- Email route `hyo@hyo.dev` with player-ID matching, and purchase-record
  requests forwarded to the verification processor
  (`en.mjs:104-105,141-145`; processor forwarding also in
  `iap-store-setup.md:68-71`).

Reviewer access (facts):

- Guest path needs no credentials: title → Tap to start → Continue as
  guest → permanent player ID → New expedition / Resume; store, Restore
  purchases, and resume complete as guest
  (`app-store-release.mjs:744-757`, `four-zero-review-entry.md`).
- Google/Apple sign-in is optional for review and for purchases; no
  developer demo account exists. The obsolete "no app account" review line
  was already replaced (`four-zero-review-entry.md`).

## 5. Three-way separation: game analytics vs IAPKit statistics vs Firebase diagnostics

1. **Game optional analytics — disabled in this submit.** Fact chain:
   `firebase.cfg` absent (§0) → `FirebaseConfig.read()` all-default
   (`firebase_config.gd:17-43`) → `Analytics.configured()` false
   (`analytics.gd:202-207`) → consent prompt never opens and Settings
   toggle hidden (`analytics_consent_panel.gd:84-88,143-145`,
   `settings_panel.gd:112-118,137-139`) → `enabled()` false
   (`analytics.gd:210-212`) → `track()` and `_try_flush()` closed
   (`analytics.gd:306-307,730-731`); a stored GRANTED is revoked when
   config is absent (`analytics.gd:223-245`). Default consent is UNKNOWN,
   which does not collect (`settings.gd:30-41`). If a later build enables
   it, payloads carry ephemeral session/run ids, app version, platform,
   locale, and allow-listed gameplay properties only
   (`analytics.gd:44-68,327-340`) — no player names, product ids, tokens,
   or device ids by construction (`analytics.gd:3-8`). The legacy global
   ladder (which would submit player-entered names,
   `global_ladder.gd:117-120`) is gated on the same absent file and stays
   quietly off (`global_ladder.gd:60-67`). This disabled-analytics finding
   does not suppress the functional Apple Product Interaction label: Apple
   row 8 now reports retained cloud checkpoint/place/progress data as
   collected, with analytics events as a separate, currently absent
   category (see §2).
2. **IAPKit verification/service statistics — active for purchasers.**
   Fact: per purchase the app sends store + expected product + JWS/token
   (§0 table). Server retention (transaction/order ids, store responses,
   request IP, result, processing duration; project-first-verification
   stat; Mixpanel/Convex sub-processing) is documented secondhand in
   `iap-store-setup.md:44-50` and `en.mjs:129-131`, not observable in
   game source — verify against IAPKit's own docs at submit (Open).
   This traffic is separate from game analytics (different host, different
   trigger, no shared identifiers: verification bodies carry no UID,
   `MB-` id, or analytics session).
3. **Firebase's own diagnostics — SDK-side, not game code.** Fact: game
   source contains no Firebase diagnostics call; the SDK inventory is §0.
   Collection details (UID handling, security IP/user-agent, transitive
   SDK components) come from the official Firebase disclosure docs
   (Open), following the director's official-source reading, not from
   this repo.

## 6. Sharing note (Play) / third-party note (Apple)

- Data leaves the device to: (a) Firebase/Firestore backend under the
  game's own project (`cloud_schema.gd:10-12`, `PROJECT_ID
  moonlitbeacon-778ee`); (b) Firebase Auth + Google/Apple provider
  endpoints via the native SDKs; (c) IAPKit verification for purchases.
- Proposed Play sharing answer: **No** for every row — recipients are the
  backend and processors that carry out the stated purposes, which the
  official Play guidance may exempt from sharing; Hall rows are public
  in-app content, not a third-party transfer. The director confirms each
  recipient against the official sharing definition; do not treat this
  proposal as the submitted answer.
- IAPKit's Mixpanel/Convex legs are server-to-server from the processor,
  never app-called (§0 endpoint table) — name them in the policy (already
  done at `en.mjs:129-131`), and let the director decide the form
  treatment from the official definitions.

## 7. Open evidence and unproven branches (do not claim as done)

1. Staged export values: `moonlit_identity.cfg` contents (Google server /
   iOS client ids, Apple flags, Firebase keys; Play Games app id absent)
   and `firebase.cfg` absence in the submit binary. Neither file exists in
   this copy (§0); the director inspects them at export.
2. Shipped consent sheets: which profile fields Google's sheet actually
   grants under default scopes, and Apple provider-default scope behavior
   on Android and iOS. Game adds no Google scopes and requests no Apple
   scopes (cited in rows 2-3), but the rendered sheet is provider-side.
3. iOS Apple delete/re-confirm branch: designed in code
   (`MoonlitIdentityIos.mm:1109-1146`), no device proof
   (`four-zero-copy-review.md` remaining gates).
4. Actual store purchases on the final build: current evidence is
   guest/Google cache restore only (same note). Do not claim purchase
   testing passed.
5. Apple Services ID/key setup for the Android Apple flow (same note).
6. Deployed Firestore ruleset readback: deployment/ownership proof held,
   independent readback still appropriate (same note).
7. IAPKit retention/statistic/sub-processor details beyond the repo's
   secondhand notes (Open in rows 6-7, §5).
8. Firebase Auth/SDK collection specifics (UID/security IP/user-agent,
   transitive components), IP-inferred location treatment, and
   service-provider sharing exemptions: decided from the official
   references listed at the top, not from this repo.
9. The 4.0.0 store upload and review submission themselves (limited
   observed progress; internal testing and public production/review kept
   separate): the director committed Play internal track 4.0.0 versionCode
   17 with five listings and 90 new screenshots, and a read-only live
   audit observed internal artifact 17 published. Play production remains
   3.0.0 versionCode 16. App Store review still has 3.0.0 build 11; no
   final App Store 4.0.0 assets or build are claimed here. 4.0.0 native
   IAP testing, PR/main merge, and both-store final review remain
   unfinished (`four-zero-copy-review.md` remaining gates).
10. Deleted-slot policy wording (was §4 cross-check): resolved by the
    Brief 161 source change (see §4); historical concern preserved there.
    No wording is changed here. All other deletion edges and native
    end-to-end proof stay Open via items 3-4 above; nothing here claims
    they passed.

## 8. What the director verifies at submit

- Staged `moonlit_identity.cfg` and `firebase.cfg` presence/contents in
  the export; Play Games still unstaged.
- Google/Apple consent sheets on-device against rows 2-3 (email/name).
- IAPKit docs against rows 6-7 retention/statistic claims.
- Official Play/Apple definitions against every Required/optional,
  linked/unlinked, sharing, and tracking proposal above.
- Apple rows 3 + 8 dual label (Gameplay Content retained, Product
  Interaction functional) against the official Apple definitions and the
  checkpoint field/upload citations; analytics-off (§5) stays a separate
  category.
- Play rows 1-3 Account Management + App functionality against source
  account use and official Firebase disclosure purposes, kept distinct
  from the director-observed saved draft noted in §1.
- Deployed Firestore rules against `firestore.cloud.addition.rules`.
- iPad Apple delete/re-confirm and a real purchase on the final build
  before any claim about them.

## 9. 4.0.1 update: adventurer names, lesson bit, attendance, Hall alias (version-scoped)

Everything in §0–§8 stays as the 4.0.0 historical record; nothing above
was edited for this update. This section scopes what 4.0.1 adds. It is
audit only, like the rest of the file: the director verifies the remote
form.

New documents (facts, all under the same `moonlitbeacon-778ee` project
and the same two game-called endpoints from §0 — no new host, no new
SDK, no analytics change):

- `mb_adventurers_v1/{publicId}`: one row per named account —
  `public_id, uid, name_key, display, intro_complete, schema,
  created_at, updated_at` (`cloud_schema.gd:18,52-55`). `display` is
  the 2–12 character handle the player typed
  (`cloud_schema.gd:144-173`); `intro_complete` records the finished
  lodge lesson.
- `mb_names_v1/{nameKey}`: one row per claimed handle —
  `name_key, display, public_id, schema, created_at`
  (`cloud_schema.gd:19,56-58`). Creation is first-writer-wins
  (`firestore.cloud.addition.rules:357-370`, `!exists` guard); handles
  cannot be renamed or moved (`game.md` account section).
- `mb_attendance_v1/{publicId}`: one row per account —
  `public_id, uid, install_id, last_claim_at, schema, prev_claim_at,
  prev_install_id` (`cloud_schema.gd:20,59-66`). The only timestamp is
  server-set (`last_claim_at == request.time` in the rules); one grant
  of two coins per rolling twelve hours, enforced by server time
  (`cloud_schema.gd:73-78`, `cloud_attendance.gd:1-30`).
  `install_id` is 16 device-minted random bytes kept in the Vault
  (`vault.gd:1348-1362`), an app-generated receipt binding, not a
  device or advertising identifier.
- Hall alias: Hall rows may now carry `display`, the owner's verified
  adventurer name bound server-side to the claimed name pair
  (`cloud_schema.gd:48-51`; rules bind at
  `firestore.cloud.addition.rules:228-229`). Legacy and unnamed rows
  render without one. The Hall stays one row per public ID; no other
  Hall field changed.

Required online naming vs the local-only failure escape (facts):

- Required path: a cloud-linked account whose Vault cache holds no
  verified handle (or no acknowledged lesson bit) must visit the gate
  lodge before the Arena (`production_host.gd:812-830`,
  `needs_lodge_lesson`, which requires BOTH). There Lumi greets the
  hero, the account claims one handle through the atomic service, the
  player walks and dashes on the open floor, and the account-owned
  lesson seals before departure (`gate_lodge.gd:1-20`). The name form
  offers confirmation and retry only — a Confirm button
  (`gate_lodge.gd:353-357`) plus the register/taken/offline/retry
  strings (`gate_entry.csv:111-116`) — with no unnamed opt-out
  control. A successful online first entry therefore requires a
  unique nickname BEFORE movement practice and departure. Claiming
  needs a connection (`gate_entry.csv:116`,
  `gate.lodge.name_offline`); the verified handle is cached per
  account only from server-acknowledged states (`vault.gd:1244-1295`),
  and the lesson touches no saved run and spends no coins (`game.md`
  lodge bullet). A returning named account that stopped midway
  through practice still visits the lodge, because the lesson bit is
  unset (`production_host.gd:812-830`).
- Failure escape (not ordinary optional collection):
  `begin_guest(true)` skips registration only when leaving a held
  error screen (`production_host.gd:408-422`, sole `true` caller at
  `production_entry.gd:335-341`, same as §3). A local-only guest has
  no claim to settle, never enters the lodge (`gate_lodge.gd:11-12`),
  and plays unnamed. That escape exists for error/unconfigured
  builds; in a configured build every online account passes the
  required naming above, so the escape does not make name collection
  optional for all users. Per the official Play guidance, optional
  requires all users to be able to opt in/out or provide the data
  optionally, while primary functionality requiring a type must
  declare it required (director-read at
  https://support.google.com/googleplay/android-developer/answer/10787469).

Deletion (facts): the account-deletion commit is now seven steps —
Hall, name claim, adventurer, checkpoint, attendance, reservation,
and profile together, atomically, before the native Auth user
deletes (`cloud_account.gd:1-30,33-75`); unnamed accounts commit the
five legacy steps unchanged. §4's four-step list is the 4.0.0 record
and stays untouched above.

Reminders (facts): attendance reminders are local-only. One
per-install controller schedules from the server-confirmed deadline;
a notification never grants coins by itself, and the schedule retires
on disable, sign-out, account switch, or deletion
(`attendance_reminders.gd:1-25`). No reminder payload leaves the
device; no new data type.

Director-saved Play correction (remote fact, not this copy's proposal):

- The director read the actual Play form: User IDs already required;
  Name previously optional; email optional; Name/User IDs purposes
  App functionality and Account management, collected, non-ephemeral,
  not shared. The adventurer `display` handle is a nickname, and
  nicknames are Play Name under the official definitions (same
  director-read guidance URL as above).
- Because online naming is required (see the required path above),
  the director saved Name as required for the coming review. The
  preview shows Name/User IDs without Optional and email with
  Optional; the console says the change is saved and ready in
  Publishing overview. It has NOT yet been sent for review, and
  nothing here claims review is complete or published.
- The public Hall alias is in-app public content under the same
  sharing note as §6, not a new sharing recipient; no new Play
  data-type row beyond the Name correction is proposed.

Apple (no declaration edit made): Apple currently declares Name,
Email Address, User ID, Gameplay Content, and Product Interaction,
linked to identity for App Functionality. The nickname/handle fits
the existing identifier declaration (director-read at
https://developer.apple.com/app-store/app-privacy-details/).
Tracking stays No for the new rows for the same §2 reasons (no ad
identifier, no cross-app combination).

Attendance rows add no new personal-data type beyond the
already-declared IDs: timestamps plus the app-generated install
binding above. Naming is required; attendance is part of the
signed-in account; the local-only failure escape and disabled
reminders collect nothing.

Open (added by this update, besides §7): the director sends the
saved Name-required Play change for review and confirms the
Required treatment on the 4.0.1 (Android 20 / iOS 15) binaries; no
twelve-hour delivery, no permission tap, and no purchase is claimed
from this copy.
