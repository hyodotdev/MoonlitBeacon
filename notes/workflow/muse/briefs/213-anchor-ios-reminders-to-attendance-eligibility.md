# Brief 213: Anchor iOS reminder delivery to attendance eligibility

## The ask and confirmed defect
The user wants an attendance reminder every twelve hours while away, with
one switch to disable it. The current iOS schedule creates a one-shot at
`eligible - now` and, simultaneously, a repeating request at 43200 seconds
from NOW. Both use the same notification content. Actual source inspection
of `reminderSchedule:args:` confirms this; it is not just a report risk.

At a fresh reward, firstDelay is approximately 43200, so first and repeat
fire together. Enabling six hours into the cooldown produces deliveries at
+6h, +12h, +24h rather than +6h, +18h, +30h. Locale rescheduling shifts that
second schedule again. The current regex tests affirm this incorrect shape.

## Do
Use a bounded horizon of owned, non-repeating iOS requests at the server
eligibility deadline plus N * 43200 seconds. Reserve room under the OS
pending-request budget for other app requests and the debug request; a
reasonable explicit cap is 48 deliveries (24 days). Refresh that horizon
on a genuine foreground visit without changing its original deadline;
reset after a successful new attendance claim. Existing identical live
schedules can skip needless work but do not permanently prevent horizon
refill. Never schedule already elapsed deadlines as immediate bursts.

Keep request identifiers scoped to this feature. Cancellation, sign-out,
account switch and Settings off must remove the entire owned horizon plus
legacy first/repeat/debug requests and delivered copies, without deleting
other app notifications. Preserve permission/foreground safeguards, no
coins from notifications, no APNs/push service and app privacy disclosure.

Expose actual pending trigger times/owned count/horizon end through the
existing diagnostics. Truthfully document the bounded away period rather
than promising indefinite background scheduling. Correct the source,
contracts and five-language care text as needed, including generated dist.

## Acceptance
Native pending deliveries are unique and twelve hours apart, anchored to
eligibility both for a fresh reward and for a halfway enable. A short first
delay never becomes a short repeat. Refresh/locale change cannot duplicate
or shift deliveries. Off/account retirement cancel all owned requests,
including legacy ids. The director compiles the actual native bridge and
inspects device pending diagnostics. Meaningful regressions exercise the
planned timestamps and identifier/cancel rules, not just matching strings.

## Constraints
No network, credential access, store/version changes, SDK bundle changes,
IAP changes, old hero rasters, git operations or broad suite rewrites.
Run only affected checks with bounded Godot timeouts and full diagnostics;
report native build limits honestly. Preserve the fixes from brief212.
