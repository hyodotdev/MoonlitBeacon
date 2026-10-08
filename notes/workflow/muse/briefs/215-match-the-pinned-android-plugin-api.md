# Brief 215: Match the actual Android Godot plugin API

## Confirmed actual native build failures
After brief212, generated resources now reach Gradle and the drawable
error is gone. The director's REAL debug build exits1 on newly exposed
Kotlin API typing defects, full log gate-native-reminder-android-round14.log:

- `onMainRequestPermissionsResult` currently returns Boolean, but the
  overridden `GodotPlugin` member returns Unit. The actual pinned Godot
  core AAR extracted jar was inspected with javap: public void
  onMainRequestPermissionsResult(int, String[], int[]). This is distinct
  from onMainBackPressed, which returns boolean. Current regex regression
  incorrectly demands Boolean and must be corrected, not preserved.
- Five `val context: Context = activity ?: godot` assignments fail:
  Godot is not a Context, common inferred type Any. Occurrences currently
  at1260/1288/1342/1387/1435/1459. Obtain a real Activity/Context through
  the existing actual plugin/Godot API, or return honest unavailable when
  lifecycle has no context. Never crash, dereference null, or fabricate a
  type cast; avoid leaking Activity references across lifecycle.

## Do
Fix those compiler boundaries against the pinned engine artifact. Preserve
permission-owner isolation, cancellation/stale completion guards and all
existing Firebase auth/IAP behavior. Add meaningful regression proof of
the required callback return and context source. The director will rebuild
the actual AAR and inspect the resource entries, then perform native QA.
No changes to cadence/server rewards/room layout in this task.

## Acceptance
Real Gradle Kotlin compilation succeeds using existing pinned Godot AAR
and dependencies. Reminder permission callback settles once when matching
and ignores unrelated callbacks without violating Unit signature. Status,
schedule, cancel, settings, diagnostics work or honestly fail without a
context. Existing identity callbacks and scoped mutation behavior hold.

## Constraints and verification
No network, credentials, new dependencies, SDK bump, store/version changes,
IAP changes, git or image changes. Bounded affected contracts/controller
checks, true exit status/full diagnostics. Do not claim native compilation
from static tests; director supplies the actual toolchain/build.

## Actual iOS build exposes typed API failures too
Director round14 SCons build now clears the previous Objective-C context
errors, but exits1 with4errors and2availabilitywarnings, raw log
`gate-native-reminder-ios-round14.log`:
- NSUserDefaults has no longLongForKey: or setLongLong:forKey: selectors.
  Use a supported NSNumber object or appropriate supported typed accessor,
  preserving full 64-bit UTC milliseconds without truncation. Occurs in
  schedule persistence and pending diagnostics.
- nextTriggerDate is not a property on base UNNotificationTrigger. Query
  supported concrete interval/calendar trigger types safely and preserve
  correct future timestamp diagnostics for the eligibility horizon.
- UNAuthorizationStatusEphemeral is iOS14+, deployment target13. Keep the
  app's existing minimum; availability-guard supported handling.

Close these real typed API boundaries too, preserving brief213's corrected
eligibility-anchored horizon. Director compiles actual iOS again. Do not
weaken the API diagnostics or privacy checks to pass regex-only tests.
