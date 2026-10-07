# MoonlitIdentity — native player identity bridge

Standalone native sign-in for MoonlitBeacon 4.0.0: ordinary Google sign-in
(`google.com`) on Android (Credential Manager + Google ID) and iOS
(GoogleSignIn SDK), Apple sign-in (`apple.com`) on iOS (native sheet) and
Android (Firebase browser OAuth flow), the optional Play Games v2 gaming
profile (`playgames.google.com`, Android only), and genuine anonymous
Firebase authentication for guests. One Google account uses the same
Firebase provider on either platform; one Apple account likewise. No UI
lives here; the later integration brief reads the capability signals and
receipts documented below.

## Layout

```text
moonlit_identity.gd          GDScript wrapper: the only file the game calls.
                             Bounded async API, per-provider readiness gates,
                             explicit unsupported / not_configured receipts,
                             no token or PII logging.
moonlit_identity_plugin.gd    EditorPlugin: autoload + Android/iOS export hooks.
android_manifest_hook.gd     Stamps the Play Games APP_ID into the exported
                             Android manifest from the staged public config.
ios_export_manifest.gd       Computes the exact iOS export registration:
                             static-entry C++ snippet + hook routing,
                             staged frameworks, privacy bundles, measured
                             system frameworks, linker flags, and the
                             GoogleSignIn callback URL scheme + plist hook
                             routing.
extension_list_composer.gd   One composed extension_list.cfg shared with IAP.
plugin.cfg                   Plugin manifest (name MoonlitIdentity).
android/                     Kotlin Godot plugin source + .gdap manifest.
ios/                         Objective-C++ GDExtension source + descriptor.
```

Compiled outputs (`android/bin/`, `bin/`) are director-built artifacts and are
never in the repo.

## Calls the game makes (all on the `MoonlitIdentity` autoload)

Every call returns a receipt Dictionary at once:

- `{"status": "ok", ...}` — settled now.
- `{"status": "pending", "request_id": "..."}` — exactly one terminal outcome
  follows on `request_completed`, with the same `request_id`.
- `{"status": "conflict", "code": "already_linked_elsewhere", ...}` — the
  provider account belongs to a different player. Ask the user; nothing was
  merged or overwritten.
- `{"status": "cancelled" | "error" | "unsupported" | "not_configured",
  "code": "..."}` — settled with no account change.
- `{"status": "draining", "request_id": "..."}` — only from
  `cancel_request`: a native mutation already began, so the lock stays and
  the terminal outcome still arrives on `request_completed`.

Calls: `get_capabilities`, `sign_in_guest`, `sign_in_provider`,
`link_provider`, `get_session`, `get_id_token`, `sign_out`,
`delete_account`, `cancel_request`. Two bounded deadline windows
(`_timeout_for_method`): the provider sheet calls (`sign_in_provider`,
`link_provider` → `moonlitSignInProvider` / `moonlitLinkProvider`)
arm the 300-second interactive window, because they wait on a human
reading the account/consent chooser; every other call (guest,
session, token, sign-out, delete) keeps the 30-second ordinary
network window. The Apple reauthentication inside `delete_account`
answers to delete's own ordinary deadline; there is no separate
reauthentication call. Tests shorten the windows with
`set_request_timeout_seconds` (blanket override: sets both windows
at once, the setter's historical meaning, each floored at 0.5
seconds) followed by `set_interactive_timeout_seconds` (sheet
calls alone) to re-separate them. Each pending request captures
its window at dispatch, and a draining mutation re-arms that
captured window — never the live globals — up to two extra
windows (`TIMEOUT_EXTRA_WINDOWS`) before the request
force-settles as retryable `request_timeout`
(`pending_timeout_seconds` reads the stored window back).
Answers that arrive after cancel or timeout, and any second terminal for one
id, are dropped. Settled-id bookkeeping is capped at 64 entries; sync session
reads record nothing.

The `id_token` field appears only in answers to `get_id_token`. Use it at
once (an `Authorization` header for Firebase REST), never save or log it.

## Providers and readiness

Provider ids are platform-independent: `google` (`google.com` on both
OSes), `apple` (`apple.com` on both), `play_games`
(`playgames.google.com`, Android only, never merged with `google.com`).
`get_capabilities` lists exactly the ready providers: Firebase for the
platform keeps the bridge usable, and each missing provider key removes
only that provider. A missing Google client id never blocks guest or
Apple play; a missing Apple setup never blocks Google. Full readiness is
an empty `missing` list. Each Apple provider gates on a staged setup
acknowledgement (`[apple] android_enabled`, `[apple] ios_enabled`):
server-side Service ID/key/entitlement material never enters the app,
and the flags only record that the director configured it, so buttons
stay truthful before that setup lands. Google's SDKs authenticate under
their own default account scopes; game code adds no scopes and never
reads or stores profiles.

## Native callback contract

Both natives expose the same eight methods, each taking
`(request_id: String, args_json: String)` and returning a receipt JSON
string, and each emitting terminal outcomes on one signal. Provider
methods dispatch on the `provider` arg and answer `unknown_provider` for
anything outside the platform allowlist.

- Android: engine singleton `MoonlitIdentity`, signal
  `moonlit_identity_event(outcome_json: String)`.
- iOS: GDExtension class `MoonlitIdentityIos`, signal
  `moonlit_identity_event(outcome_json: String)`.

Outcomes carry status, code, request id, and — on a cloud session — `kind`,
`uid`, and `provider` only, with the provider mapped from the Firebase
user's linked provider data. `moonlitCancelRequest(request_id)` answers
`cancelled` while no native mutation began, or `draining` once one did.
A link keeps the Firebase UID; a provider already linked elsewhere
answers `conflict` naming the attempted provider, touching neither
account. The iOS Google OAuth callback returns through the staged URL
scheme into a chaining forwarder that offers the URL to GoogleSignIn and
passes anything else to the delegate's previous implementation.

Firebase initializes from the staged public client config carried in each
call's payload. Without it, calls answer `not_configured` instead of
throwing — for guests as well as providers.

## Attendance reminders (same natives, separate API)

Local notifications only — no Firebase, no provider gating, no cloud.
The game side is `scripts/gameplay/attendance_reminders.gd` (owned by
the production host) plus a Settings row; both natives expose the same
seven methods on the same `(request_id, args_json)` receipt contract:

- `moonlitReminderStatus` — live OS state: `permission`
  (`granted`/`denied`/`unknown`), whether this install asked the OS to
  hold a delivery (persisted intent, never a token probe), and
  (Android) whether this process started from the reminder's launch
  action. `permission` weighs the app-global switch, the 33+ runtime
  grant, and the attendance channel together. Async on iOS (`pending`
  + signal) with a fresh OS read, because `getNotificationSettings`
  is async-only.
- `moonlitReminderRequestPermission` — the OS sheet; `pending`, then one
  terminal outcome with the resulting `permission`. Uses the
  interactive (human) timeout like the provider sheets.
- `moonlitReminderSchedule` — first fire at `eligible_utc_millis`
  (absolute, server-derived) plus the twelve-hour repeat; replaces any
  earlier attendance schedule. Identical inputs skip without shifting
  the repeat anchor, unless the held window runs low (iOS refills 48
  future slots from the same anchor and reports `base_slot` /
  `horizon_end_unix`; Android reports `-1` for its unbounded alarm).
- `moonlitReminderCancel` — cancels the scheduled delivery and dismisses
  a delivered one. Names exactly this app's attendance identifiers.
- `moonlitReminderOpenSettings` — opens the app's OS notification
  settings page.
- `moonlitReminderPending` — trigger facts plus the persisted
  schedule mirror for QA (Android separates intent from token
  existence; iOS reports the held horizon window). Async on iOS
  (`pending` + signal).
- `moonlitReminderDebugSchedule` — QA only: one short (5–600 s)
  non-repeating delivery. Never touches the production twelve-hour
  rule or any wallet.

When the Android activity is between lifecycles every entry point
answers retryable `error` (`no_activity`) instead of guessing: the
game keeps its owned delivery and retries on the next refresh.

Android holds one inexact `RTC_WAKEUP` alarm (`setInexactRepeating`,
no exact-alarm privilege, no foreground service) re-armed after reboot
from a SharedPreferences mirror; delivery re-checks the persisted
opt-out, the runtime permission, the localized channel state, and
whether the game is foregrounded (a fresh resume record or a
foreground-ranked process — a stale record never suppresses alone).
The small icon is a monochrome beacon vector; the channel name ships
in the game's five languages. iOS holds a bounded horizon of 48
non-repeating slot requests at eligibility plus N * 43200 seconds (24
days, under the 64-request OS budget): every delivery is anchored to
eligibility, elapsed slots are skipped rather than burst, identical
refreshes skip while the horizon is live, and a nearly consumed
horizon refills from the same anchor. Cancellation names the whole
horizon plus the legacy one-shot/repeat/debug ids. Foreground
presentation is suppressed through a delegate installed only when
none owns the center; returning none matches the no-delegate default.
Scheduling metadata (account, eligible time, locale) lives in
app-only `NSUserDefaults` keys declared by the app's own
`ios/PrivacyInfo.xcprivacy` (reason CA92.1). Godot 4.7.1 emits its
own app-root manifest, so the export plugin registers no loose copy
(a second same-basename output fails Xcode); instead the owned
export pipeline (`node scripts/ios.mjs`, every export path) merges
this file's UserDefaults declaration into Godot's generated root
manifest and verifies the single registration, while the SDK
bundles keep their untouched manifests. No token, email, name, or
wallet value crosses this API.

## Build commands (director runs these)

```bash
# Preflight first: explains missing public config without printing values.
node scripts/build-player-identity.mjs --dry-run
node scripts/build-player-identity.mjs --check --platform android
node scripts/build-player-identity.mjs --check --platform ios

# Bridge builds (dry-run reports missing deps; without it, compiles from
# pinned official dependencies and verifies the artifacts).
node scripts/build-player-identity.mjs --build-android --dry-run
node scripts/build-player-identity.mjs --build-android --release
node scripts/build-player-identity.mjs --fetch-deps --platform ios
node scripts/build-player-identity.mjs --build-ios --dry-run
node scripts/build-player-identity.mjs --build-ios --release

# Stage the public client identifiers for an export (--install), then remove
# the staged file again afterwards (--clean). Never commit the staged file.
node scripts/build-player-identity.mjs --install
node scripts/build-player-identity.mjs --clean
```

AARs land at `android/MoonlitIdentity.<debug|release>.aar` (next to the
`.gdap`, mirroring godot-iap); iOS static libraries land at
`bin/ios/libmoonlit_identity.<debug|release>.a`, with the variant's
identity frameworks staged at `bin/ios/frameworks/<debug|release>/` and
the SDK privacy bundles at `bin/ios/resources/<debug|release>/`. The
export plugin links the frameworks plus the measured system set and
`-ObjC -lz`, registers the bundles for the app resources, and stamps the
GoogleSignIn callback URL scheme. Pins, provider setup, and the
device-check readiness list live in
`notes/release/player-identity-setup.md`.
