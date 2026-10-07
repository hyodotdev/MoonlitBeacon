// Pure attendance-reminder horizon planner, shared by the iOS native
// schedule path and the host-side numeric test. All times are integer
// UTC milliseconds and all math is exact: the equal-time boundary and
// the duplicate gate must decide identically on every run, with no
// floating-point epsilon between "due now" and "elapsed".
//
// A horizon is 48 twelve-hour slots on one server-owned anchor. Slot k
// fires at anchorMs + k * 43200000. A schedule plans the 48 slots from
// the first not-yet-elapsed position; an identical re-schedule while at
// least 8 of the recorded window are still future is a duplicate that
// touches nothing. The game-side refill margin mirrors this rule from
// the recorded window metadata so both sides agree when a refill is
// due. A slot firing exactly now is due, not elapsed: it schedules
// once (the caller clamps its trigger to a valid delay) and never
// replays as a burst, because the next computation already counts it
// as past.
#ifndef MOONLIT_REMINDER_PLANNER_H
#define MOONLIT_REMINDER_PLANNER_H

// 48 deliveries cover 24 days away and stay under the 64-request OS
// pending budget, leaving room for other app requests plus the QA
// one-shot.
static const long long kReminderHorizonSlots = 48;
// A held horizon with at least this many future slots is adequate:
// identical re-schedules skip without touching the center.
static const long long kReminderMinFutureSlots = 8;
// Twelve hours in milliseconds.
static const long long kReminderRepeatMillis = 43200000LL;

// First slot not yet elapsed: the smallest k with
// anchorMs + k * REPEAT >= nowMs. Zero while the anchor is still
// future; exact at every grid multiple (no float division).
static inline long long MoonlitReminderFirstFuture(
	long long anchorMs, long long nowMs) {
	if (nowMs <= anchorMs) {
		return 0;
	}
	return (nowMs - anchorMs + kReminderRepeatMillis - 1)
		/ kReminderRepeatMillis;
}

// Absolute fire time of an ordinal slot on its anchor.
static inline long long MoonlitReminderSlotFireMs(
	long long anchorMs, long long slot) {
	return anchorMs + slot * kReminderRepeatMillis;
}

// Future slots still held from a recorded window base: the 48
// scheduled ordinals minus the elapsed prefix. A base entirely ahead
// of now (the clock regressed) counts whole; the gate below still
// refills that corner rather than holding it.
static inline long long MoonlitReminderRemaining(
	long long recordedBase, long long firstFuture) {
	if (firstFuture < recordedBase) {
		return kReminderHorizonSlots;
	}
	long long remaining =
		recordedBase + kReminderHorizonSlots - firstFuture;
	return remaining < 0 ? 0 : remaining;
}

// The native duplicate gate: identical inputs hold while at least 8
// of the recorded window's slots are still future.
static inline int MoonlitReminderWindowHolds(
	long long recordedBase, long long firstFuture) {
	if (firstFuture < recordedBase) {
		return 0;
	}
	return (firstFuture - recordedBase) + kReminderMinFutureSlots
		<= kReminderHorizonSlots;
}

#endif // MOONLIT_REMINDER_PLANNER_H
