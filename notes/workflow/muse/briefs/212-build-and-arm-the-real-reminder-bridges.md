# Brief 212: Build and arm the real reminder bridges

## The ask
The user wants real Android/iOS attendance reminders every twelve hours
and a working opt-out. Close director-confirmed runtime/build boundaries
from brief205; preserve the existing reward, name, lodge and auth contracts.

## Confirmed evidence
- The director compiled the actual Android bridge with the cached Gradle
  toolchain. `:MoonlitIdentity:compileDebugKotlin` fails with unresolved
  `R.drawable` at `MoonlitReminderAlarm.kt:165`, followed by the chained
  `setContentTitle` diagnostic. Full raw log is the director artifact
  `gate-native-reminder-android-round13.log`. Verify the owned monochrome
  beacon resource actually reaches the generated Gradle project/AAR;
  source presence alone and regex contracts did not prove this build.
- The director compiled the actual iOS bridge with the cached SCons,
  Godot C++ and existing Firebase Pods. It fails with **18 compiler errors**:
  reminder Objective-C methods report `missing context for method
  declaration`, and the bindings report no visible worker interface for
  `reminderStatus:`, `reminderRequestPermission:`, `reminderSchedule:args:`,
  `reminderCancel:`, `reminderOpenSettings:`, `reminderPending:` and
  `reminderDebugSchedule:args:`. They are currently outside the worker's
  Objective-C implementation/interface context. Full raw log is
  `gate-native-reminder-ios-round13.log`. Preserve auth delegate behavior
  while placing/declaring the methods correctly.
- Actual `AttendanceReminders` + real Settings, injected registered fake
  host/bridge, isolated user files: a server-confirmed eligibility thirty
  seconds away, OS permission granted, explicit user enable. Clean script
  run exits1, **native schedule calls0**, wantedtrue/permissiongranted.
  The `remaining < MIN_FIRST_DELAY_SECONDS(60)` shortcut permanently
  leaves this newly enabled install without a first or subsequent alarm
  if the player leaves. Log `gate-reminder-near-deadline-mid-round13.log`.
  The player may enable reminders halfway through a cooldown or right
  before eligibility; being foregrounded now is not permission to omit
  all future reminders. Native foreground suppression is the delivery guard.

## Do
- Fix actual Android resource staging and native compilation. Keep the
  existing owned monochrome icon, immutable intents and receivers; no
  generic icon fallback, new dependency or exact-alarm privilege.
- Fix Objective-C worker context/interface declarations and the actual
  iOS compile. Keep notification callback isolation, twelve-hour cadence,
  foreground suppression, app-owned privacy export and all SDK bundles.
- Schedule positive short remaining windows correctly, with a distinct
  first delay and twelve-hour repeats. Preserve skip/no-award behavior for
  an already eligible foreground visit where the real attendance claim
  owns the next deadline; do not mint coins from this correction. Register
  the actual controller case for 30 seconds, and native first-vs-repeat
  diagnostics, rather than extending a short first delay into a short
  repeating period.
- Strengthen meaningful build/export regressions so they exercise the
  generated Android resource tree and Objective-C worker placement;
  regexes asserting a method's name somewhere in a file are insufficient.
  Keep the director-run native QA harness usable and observable.

## Acceptance
The director's real Android and iOS bridge builds compile. The actual
thirty-second controller probe sends one schedule with the confirmed
future deadline and native repeat43200seconds. Permission denial/off,
revocation, account retirement and stale callbacks remain safe. SDK
privacy bundles and old hero rasters remain unchanged. Director then
tests actual device notification delivery/tap/cancel and final UI.

## Do not
No network/credential access, deployments, store/version changes, native
auth SDK or IAP changes, git actions, marketing capture, broad asset
regeneration or unrelated suite rewrites. The director supplies native
toolchains and builds; report any unavailable compile honestly.

## Verification
Run affected registered controller/bridge/export checks with true exit
statuses and full diagnostics; small Godot checks have a 45-second bound.
No repeated sandbox-blocked full sweeps. Update the protocol/report with
the exact repaired boundaries; do not claim native build success from
static contracts.
