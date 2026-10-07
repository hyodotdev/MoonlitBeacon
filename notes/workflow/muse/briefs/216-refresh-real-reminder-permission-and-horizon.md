# Brief 216: Converge reminder state after OS changes and return

## Confirmed evidence
Director actual AttendanceReminders + real Settings (autoload scene,
isolated user files), registered fake native bridge. Explicit enable under
granted permission schedules once. Native permission then changes to
denied and controller.refresh() runs on the same account/deadline/locale.
It exits1: Settings.reminder_os_state still granted. Raw log
`gate-reminder-revocation-round16.log`. The identical-input return happens
before live status checking. Native delivery protects the device, but the
controller and existing open Settings row can continue to claim on.

SettingsPanel.open() queries refresh_permission(), but on iOS reminderStatus
returns its cached permission BEFORE requesting an asynchronous OS refresh;
no updated status outcome is delivered afterwards. Returning from system
notification settings must converge in the current open panel, without
requiring close/reopen twice. Explicit intent remains distinct from OS
permission; unknown/pending/failed permission must not display as enabled.

Round15's iOS horizon refill is also not a refill: loop always enumerates
absolute slot0..47 from eligibility. For now >eligible+47*43200 it adds0
requests and returns ok. The identical deadline controller guard also
prevents reaching that native path. Its independent JS test mirrors the
loop and tests only3elapsed days, so cannot catch exhausted/refill failure.

## Do
Re-check effective OS permission before unchanged-schedule skipping, and
on genuine foreground return / opening Settings. Handle iOS async status
refresh via an explicit bounded bridge result or another genuinely observed
convergence mechanism, with account/generation guards. No automatic OS
permission prompt: only user's explicit enable/offer/Settings actions.
Keep denial/off cancellation safe and show truthful unknown/permission
needed when appropriate. Avoid settings-changed recursion or polling loops.

When a genuine foreground refresh refills a bounded iOS horizon, compute
the first future N on the SAME eligibility anchor and plan up to48future
slots from there. Stable bounded identifiers can use ordinal positions
0..47, while timestamps remain eligibility+N*43200. Persist enough metadata
to determine actual held horizon end; skip needless reschedule while it is
still adequately held. No elapsed burst and no forever-first48 cutoff.
A fresh successful attendance claim resets its anchor as before. Ensure
controller doesn't prevent this native refresh forever. It must not move
the deadline or create repeat calls on every frame/settings redraw.

## Acceptance
- Director same-deadline revocation probe updates to denied and never
  leaves effective-on UI; already-scheduled no-duplication still holds.
- Current open Settings converges after returning from OS deny/grant
  changes on Android/iOS, without a second reopen and without prompting.
- Actual planned timestamps at day25 retain full48future unique12h slots
  on the original anchor; diagnostic horizon_end matches the held times.
  A mid-window refresh does not duplicate/shift existing schedules.
- Off, account switch/deletion and stale callback cancellation still pass;
  notification/permission transitions cannot credit a coin.
- Meaningful production-side planner/controller tests, not a duplicated
  JS implementation that can diverge independently. Keep the API build
  repairs from brief215 and privacy/SDK assets unchanged.

## Constraints
No network, credentials, stores/versions, new SDK/backend/FGservice, IAP,
hero images, git operations or broad suite rewrite. Five locale strings
only if a truthful status requires them. Affected bounded checks only,
fullraw logs and real exit statuses; director compiles/delivers QA.

## Related confirmed reminder node-budget regression
Director cumulative `pnpm test:game` stops at late-game performance:
KnightLv40 node_peak1202 exceeds unchanged1200 budget; failed1/73, true
exit1, rawgate-cumulative-game-round15.log. New reminder controller is1
persistent node and SettingsPanel scene adds2ReminderLabel/Reminder nodes
although its panel is closed during combat. HUD offer button is already
lazy, so do not misdiagnose it. Baseline director comparison is running.
Keep the budget1200 unchanged; make the reminder Settings controls lazy
when the panel is opened (or another evidenced actual lifetime reduction),
fully rendered/interactive on open, rather than adding dormant combat
nodes. Do not hide work only in headless tests, remove real gameplay or
relax test caps. Registered Settings interaction and five-language fit
must exercise opened actual controls; native offer/controller remain safe.
Director unchanged-main comparison now passed73/73, knightLv40peak1198,
clean exit0/29.6s (gate-late-game-main-baseline.log). Newcopy1202 is a real
regression, not a reason to raise1200. Preserve projectile density/output.

If updating relevant protocol/docs, also correct the cloud-rules README's
obsolete Expected62/13 paragraph to the actual88/14 suite reported at top;
no lesson or broader docs rewrite.

Native diagnostics also currently label PendingIntent.FLAG_NO_CREATE token
existence as `alarm_scheduled` / "OS actually holds the repeating alarm".
That is not an AlarmManager query, and cancel() creates/retains those
PendingIntent tokens, so it can remain true after actual cancellation.
During this status correction, make the diagnostic honest (e.g. distinguish
owned persisted schedule intent from token existence, clear/cancel tokens
when retiring), do not claim an OS-held alarm from token existence alone.
The actual Android director will exercise schedule/cancel diagnostics.
Android effective status must include the app-global notification switch
and attendance-channel importance, rather than permission alone. Current
notificationsAllowed returns true unconditionally below33, and status
returns granted even when the delivery path channelOpen would refuse.
Use the actual NotificationManager effective switches for honest status
(and preserve the runtime permission request when permission is missing).
No new permission prompt on foreground/settings refresh.
