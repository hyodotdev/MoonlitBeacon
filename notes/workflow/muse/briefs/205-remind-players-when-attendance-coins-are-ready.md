# Brief 205: Remind players when attendance coins are ready

## The ask
“코인은 그리고 반나절마다 출석하면 2코인씩 주고 반나절마다 알림을 보내면좋아 지금 출석하면 코인 받는다고. 그리고 알림은 설정에서 안받게 할 수도 있게 해야하고”

Add real Android and iOS local attendance reminders and a persistent settings control, based on the reviewed attendance service.

## Why, and what good feels like
After an acknowledged attendance reward, a player who enables reminders is told when another two coins are ready: “지금 출석하면 2코인을 받을 수 있어요.” The reminder repeats roughly every twelve hours while away and resets after the next successful attendance. Turning it off in Settings stops all pending/delivered attendance reminders. Notifications never grant coins, interrupt first-login naming or require the game to remain running.

## Where things stand
- Continue the same isolated copy after the defeat/name/attendance/lodge integration. Preserve all preceding invariants and registered regressions.
- The attendance host view exposes server-confirmed next eligibility and the same canonical account. Use that single authority; do not create another reward timer.
- Native plugin sources already exist in `addons/moonlit-identity/android/` and `addons/moonlit-identity/ios/`, with GDScript adapter, export hooks and Node build contracts. They currently implement identity only; adding a clearly separate reminder API is acceptable, but do not change provider-auth or IAP behavior.
- `scripts/gameplay/settings.gd` and `scripts/ui/settings_panel.gd` persist and display locale/audio/reduced-motion preferences using the game's skin. Add a useful readable reminder control without generic default Godot visuals.
- `Settings` already has a durable analytics-revocation sentinel for failed preference saves; reuse the proven pattern with a separate reminder sentinel, without tying the two preferences together. `SettingsPanel._redraw()` currently returns early when Analytics is unconfigured. Reminder rendering/actions must work independently of analytics availability and consent; register that production panel case too.
- The director compiled both existing native identity targets successfully
  with the cached toolchains before reminder work. Inspection of the real
  pinned Godot Android AAR confirms these plugin hooks:
  `onMainRequestPermissionsResult(int, String[], int[])`, `onMainPause()`,
  `onMainStop()`, `onMainStart()`, `onMainResume()` and `onMainDestroy()`.
  Use their actual signatures for permission/lifecycle handling. The
  director also pinned hashes for all 18 existing debug/release SDK
  privacy resources for the final preservation check; they are inputs,
  not the new app-owned privacy declaration.

## Do
- Implement Android local notification permission/status, a dedicated localized attendance channel, a safe immutable launch PendingIntent, and a battery-conscious inexact twelve-hour alarm/receiver that survives normal app exit and reboot. Check the persisted opt-out and OS permission/channel state again at delivery. Do not request special exact-alarm privileges or keep a foreground service alive.
- Give the Android notification a proper monochrome small beacon icon derived from this game's existing emblem; do not use a generic system warning/info icon or the full-color launcher bitmap as a small icon. Preserve native notification accessibility and the existing launcher branding.
- Implement iOS UserNotifications permission/status, localized local requests starting at the confirmed next-eligible time and recurring at twelve-hour intervals. Link the needed system framework through the existing plugin export pipeline. Only cancel this app's attendance identifiers, never unrelated requests. Avoid accumulating pending requests or shifting eligibility on every title refresh.
- If the iOS implementation adds `NSUserDefaults` for app-only reminder preferences or scheduling metadata, include the app's own required-reason privacy declaration (`NSPrivacyAccessedAPICategoryUserDefaults`, `CA92.1`) in an actual exported `PrivacyInfo.xcprivacy` resource. Do not rely on or rewrite the existing Firebase/Google SDK manifests. Preserve those SDK bundles byte-identical and register staging/export tests proving this new app declaration reaches the final iOS app resources. The director will inspect the built app's privacy resources, not only the source template. If another persistence approach is chosen, document the real accessed API and its declaration requirements.
- Handle enabling reminders halfway through a cooldown correctly: the first remaining delay and the twelve-hour repeat period are different values. Do not put a short remaining delay in a repeating `UNTimeIntervalNotificationTrigger` and thereby repeat every few minutes/hours forever. Prove the actual native pending triggers maintain the requested twelve-hour cadence; document any bounded scheduling horizon honestly. A locale/status refresh must not postpone the first deadline.
- Expose bounded asynchronous bridge results and platform status honestly. Unsupported desktop remains playable with no fake “scheduled” success. Native callbacks must respect lifecycle/account changes, not dereference a dead controller or interfere with authentication callbacks.
- Add a persistent Settings reminder switch and localized status for enabled/off/OS-denied/unsupported/error. An explicit “출석 알림 받기” affordance on the first unobtrusive reward receipt may request OS permission; skip leaves play available. Do not automatically stack an OS prompt over login, IME, Lumi dialogue or combat. Denial is not enabled; repeated launches do not nag. If OS access was denied, an explicit settings action may open the app's notification settings. Disabling cancels immediately and stays off across save failure/restart; do not let an old setting re-enable delivery.
- Keep one active account's reminder per install, with safe retirement on sign-out/switch/deletion and rescheduling after a genuine new reward, enabled preference or locale change. A cold notification launch opens the ordinary title/account route; an existing background game may resume its living session safely. Preserve a living save and never auto-start a fresh expedition. The notification action does not claim or spend coins itself.
- Reminders are for a player who is away. Suppress attendance sound/banner delivery while the game is genuinely foregrounded, including naming, guide dialogue and combat; keep the future cadence without granting coins. Use actual native lifecycle/presentation state with a registered delivery case, without interfering with auth lifecycle callbacks.
- Add focused registered GDScript tests, native/export contract tests and a bounded isolated native QA harness that can schedule a short upcoming reminder without changing the production twelve-hour rule or touching a real player's wallet. Update the player guide, plugin API note and privacy/support source in five languages to explain local reminders and opt-out accurately.

## Do not
No FCM/APNs backend, push tokens, new service accounts, dependencies, analytics messaging, exact-alarm permission, provider SDK changes, purchase changes, store submission, screenshots/gallery updates, version bumps, network, deployment or git operations. The director builds both native targets and verifies real device behavior.

## Acceptance
- Source/build contracts prove notification permissions, receiver/component configuration, safe launch intents, native method registration, iOS framework/request handling and preservation of auth/IAP exports. Director native compile must succeed; source text alone is not a native build pass.
- Tests cover initially unknown permission, granted/denied/dismissed permission, off→on→off, offline cached deadline, locale change, reschedule, restart, OS revocation, failed settings save, stale callbacks and account deletion. No alert before the known eligibility time; a late OS-delivered alert never grants an early or duplicate reward.
- Settings fits all five languages at 808×360 and iPad 4:3 with readable status and tappable controls. Turning reminders off actually cancels rather than merely changing a label. Existing controls and original title remain usable.
- Supply a director-run native QA path to verify a short notification, its real launch action, and subsequent cancellation on an isolated Android test account. iOS real pending-request diagnostics and compile must be observable; report any physical-device interaction still needed honestly rather than claiming simulator success.
- Include the existing lodge's native naming flow in the director-run
  entry QA path. The director's actual 808×360 desktop name-form image
  currently places the field at roughly y136–184 and registration action
  at y229–275; desktop has no native keyboard, so that image is not an IME
  pass. Make keyboard visibility/height and real field/action bounds
  observable without logging the chosen name or any provider personal
  data. The name form must remain readable, finishable and retryable on
  Android and the taller iPad when the OS keyboard appears, including
  invalid/taken/offline responses. Preserve native composition and do not
  rely on a human needing clipboard or debug calls. If this integration
  needs a bounded keyboard-aware layout adjustment, reuse the game's skin
  and actual viewport transform; do not alter the original login chooser.
- Run affected registered and build/static/locale/docs checks. If sandbox editor-settings blocks the full old game suite, report that block and stop it; the director runs the cumulative full suite once.
- Preserve true exit statuses and complete diagnostics. Use a 45-second timeout for small Godot checks, do not hide parse/settings errors behind `tail` or `grep`, and do not repeat a sandbox-blocked command; report it for the director's normal environment.

## Primary references
- Android permission and denial behavior: https://developer.android.com/develop/ui/compose/notifications/notification-permission .
- Android inexact scheduling and Doze restrictions: https://developer.android.com/develop/background-work/services/alarms .
- iOS permission: https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications .
- iOS local interval triggers: https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger .
- Apple required-reason manifest guidance and app-only UserDefaults example: https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest and https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api .

## How the director will judge
Read delivery-time guards and cancellation behavior independently. Run the service/settings/bridge/export regressions, compile Android and iOS, inspect the final manifests/frameworks, and exercise a short reminder and opt-out on an isolated Android account. Inspect iOS pending-request evidence without claiming unperformed physical touches. Check the actual UI and unchanged saved journey on notification entry.
