# Brief218: Close the remaining real reminder refill boundaries

## Actual native build defect
Director round18 actual Gradle build fails at MoonlitReminderAlarm.kt106:
Unresolved reference OPSTR_POST_NOTIFICATION. That is not in the public
SDK used here. Keep the effective API23 app-global check using the verified
AndroidX fallback pattern, not a blanket grant or unguarded24+API. Primary
reference (standard reflective int-op check, with safe fallback):
https://android.googlesource.com/platform/frameworks/support/+/f82200123a365205ce2af67df269fb1dc56b55bb/core/core/src/main/java/androidx/core/app/NotificationManagerCompat.java
No new dependency needed. Director rebuilds. iOS18actualcompile+stage PASS.

## Confirmed game/native integration starvation
Director actual AttendanceReminders + registered fake host/bridge, isolated
scene, known cache source owned account, anchor25days ago, expired native
horizon, explicit enabled+granted: native_schedule_calls0, cleanassertion
exit1. Rawgate-reminder-expired-horizon-round18.log. `_schedule_for_view`
still returns whenever remaining_seconds==0. This prevents the production
native refill on any expired cached deadline (especially offline returns),
although the native48-slot math now supports it. Successful online claims
reset the anchor, but a reminder refresh must also work without awarding
a coin or requiring a successful claim.

Allow a known server-owned expired anchor to plan future-only notifications
on genuine refresh. Preserve source/account/intent/status guards and no
wallet changes. Newly successful attendance still resets its anchor.
For Android too, an overdue first trigger should stay on its original12h
anchor's next future slot without an immediate/burst overdue delivery.
Do not replan on every frame or every settings redraw.

## Native/GDS horizon disagreement and incomplete duplicate receipt
The current native duplicate gate holds when at least8 future slots remain:
firstFuture-recordedBase+8<=48. GDS uses now+8*43200<horizonEnd, which
requires more than8 intervals: at anchor+19.75days, nativebase40 gives8
future slots and returnsduplicate, while GDS(end=anchor+47*43200)returns
false. The iOS duplicate ok receipt also omits horizon_end_unix/base_slot/
scheduled_slots, so the game records0 from that legitimate response and
can keep trying to refill. Align their future-slot criterion (including
exact-boundary cases), make every successful native schedule receipt carry
its actual held metadata, and preserve known metadata rather than replacing
it with an unknown0 after duplicate success. Do not claim OS-held success
from a mirror; diagnostics and receipt must match the held anchor/window.

Director compiled and executed the unchanged numeric firstFuture/duplicate
calculation and loop prefix extracted from production .mm, with sourceSHA:
exact eligible==now currently yields47 future slots because firstFuture0
and fire<=now skips slot0; day25 yields48 atbase51. Ensure exactly48 future
slots at that equal-time boundary too, and no elapsed burst.

## Acceptance
Actual controller expired known cache can refill once with the same anchor,
then skips while adequately held. Unknown/none source never schedules.
A duplicate receipt keeps known end and causes no self-sustaining
Settings.changed/status/schedule loop. Native and GDS agree at7/8/9future
slots and exact eligibility; actual numeric production planner execution
proves48 uniquefuture12h slots atinitial/equal/day25. Do not replace that
with another independent JS simulation or only source-text regex assertions.
Use a production pure helper invoked by both real native code and a small
runtime unit test if needed; update the existing renderer if it introduces
an owned header. Director's extracted-code probe is independent evidence.
Preserve off/account switch/deletion/async generation/realOS permission
convergence, UI fitting/lazy node budget1199, typed API repairs/privacy
bundles and no coin credits from notifications. NativeAndroidcompile must
pass against actual SDK/AAR. Bounded relevant suites and true exits.

## Boundaries
Only reminder/runtime/test/build-helper changes and relevant protocol docs.
No lodge/hero/art, backend/rules/credentials/network, IAP, stores/version,
git operations or raised budgets. Keep the first attendance2 +12h rules.
