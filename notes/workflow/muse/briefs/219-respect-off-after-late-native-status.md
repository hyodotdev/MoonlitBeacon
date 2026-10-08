# Brief219: Respect off after a late native status result

## User requirement and confirmed evidence
User wants attendance notifications switchable off in Settings. Director
actual isolated production AttendanceReminders with registered fake
host/bridge: enabled valid owned view, native status pending, user_disable,
then that tracked status completes granted. Actual schedule_log1 while
Settings.reminders_enabled false; clean assertionexit1. Raw
gate-reminder-pending-after-off-round20.log. This is after20completed and
restored all negativecontrols. It is not an OS delivery claim.

_apply_status_outcome caches permission then calls _schedule_for_view on
fresh view, bypassing _reconcile's enabled/source guards. That common
schedule tail must respect current user intent and known live/cache
ownership too, including fields retained after source becomes none.
A status callback may update the truthful OS cache while off, but must
never re-enable intent or create a delivery after off/unknown scope.

## One narrow correction
Centralize or re-check the current settings and source/account/deadline
preconditions before any schedule side effect, in both sync and async
paths. Do not only special-case the director fixture. Preserve bounded
async convergence, same-owner held-window skip, expired-known-cache
future-only refill, duplicate metadata, explicit user re-enable,
account/deletion and generation guards. No rewards or wallet edits.

## Acceptance
Registered actual controller tests for pending-status then off then late
grant (zero schedules/record stays cleared), pending then source none with
retained deadline (zero), and a later genuine enabled known view still
schedules once. Director independently repeats exact fixture. Meaningful
negative control plus restored clean related reminders suite, script
compile; no weakening existing580checks. No need full game sweep here.

## Boundaries
Only attendance_reminders.gd, its registered test and relevant tiny
protocol/build-log note. Do not change native files, planner header,
Kotlin, assets, lodge/UI, package, backend/rules/network, versions, stores,
git, or budgets. Director is building both final native variants while
this bounded GDS correction runs; their source must stay byte-identical.
