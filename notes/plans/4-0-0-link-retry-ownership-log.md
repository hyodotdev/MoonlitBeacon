# 4.0.0 link-retry ownership log — Retry repeats the original operation

Round 1 of assignment 20261003-1422-retry-the-original-account-link-operatio
(brief 127). One confirmed account-ownership defect: `ProductionHost.retry_login`
always dispatched `sign_in_provider`, even when the failed call was
`link_provider`. On a real Android device a failed Google link followed by
Retry silently signed into a newly created Google UID while the original
anonymous UID still owned the profile, checkpoint, and Hall rows. The UI
kept showing the old public ID, so the ownership error was invisible on
screen. No migration, repair, native, backend, rules, config, art, UI
redesign, version, or export change; the already-reproduced device state
stays for the director, who rebuilds preserving device data after
acceptance.

## What was built

`apps/game/scripts/net/production_host.gd` (only production logic change):

- Retry-operation vocabulary (`AUTH_OP_SIGN_IN/LINK/SWITCH`) plus four
  fields: the remembered operation, its provider, and the live session
  (cloud UID + session provider) the attempt started from.
- `begin_provider`, `link_provider`, and `switch_to_provider` record the
  actual last user-requested operation through `_record_auth_attempt`
  BEFORE the account call, because synchronous outcomes arrive during
  it: a synchronous success must clear through the move check instead
  of being overwritten by a record written after. A call that cannot
  start (a request already pending) leaves the live attempt's record
  untouched; deletion refusals return before recording.
- `retry_login` repeats the remembered operation: link after a link
  failure, sign-in after a sign-in failure, and a sign-in-shaped switch
  only after that explicit operation. Guest retry (`""`) keeps its
  current `begin_guest()` semantics. Draining and deletion-ticket
  refusals are preserved (retry now also refuses while deletion owns
  the operation, like begin/link/switch/sign-out already did).
- The retry is bound to the remembered provider. A different stale
  provider, or no remembered attempt at all, returns
  `refused/stale_retry` without touching any account and emits
  `production_changed` so the entry repaints the honest state instead
  of sticking on busy. The remembered record is retained, so a genuine
  Retry for the remembered provider still works afterwards.
- The record clears on ordinary cancellation (live or settled;
  draining keeps it until the terminal lands), on terminal success
  (the live session UID or session provider moved — a link success
  keeps the UID and flips only anonymous to the linked provider), on
  effective sign-out, on completed deletion, and on shutdown. Failures
  and conflicts move nothing and keep the record for Retry.
  `PlayerAccount` pending/request-ID ownership is untouched.

`apps/game/scripts/ui/production_entry.gd` (one-condition companion,
flagged: outside the brief's listed deliverables but required for the
fixed flow to present honestly): the error-hold retire check now also
compares the session provider. Before, only the public ID or cloud UID
retired the hold; a successful link keeps both, so the retried-link
success this brief demands would have left the Error screen stuck.
No strings, layout, art, order, or version change.

`apps/game/tests/test_production_host.gd` (539 to 632 assertions):

- `_test_conflict_switch_preserved` rewritten: the old expectation
  ("retry starts the switch") asserted the defect — Retry after a link
  conflict signed in. It now asserts Retry repeats the link (conflict
  returns, guest kept, zero sign-in calls) and only the explicit
  `switch_to_provider` signs into the other account.
- `_test_link_retry_repeats_link_preserves_uid`: anonymous SDK session
  plus durable binding, checkpoint, and configured cloud; failed Google
  link; shared Error Retry. Asserts link twice, zero sign-in calls,
  same UID/public ID/binding/checkpoint/configured UID/coordinator
  snapshot, wire traffic names the original UID and never a second or
  foreign one, and the card clears.
- `_test_signin_retry_repeats_signin`,
  `_test_switch_retry_signs_in_after_explicit_switch`,
  `_test_retry_mismatched_provider_refused` (cold and mismatched
  refusal, repaint-not-stuck, record retained, genuine retry works),
  `_test_retry_cancel_signout_and_sync_failure_boundaries` (sync link
  failure records link intent, live/settled cancel, sign-out,
  draining-keeps-until-terminal, completed-deletion retires).
- `_test_delete_rejects_switch_and_start` also asserts `retry_login`
  is retired with `deletion_in_flight`.

## What bit

- The entry hold check (above): found by tracing the new success path,
  not by a failure — link success moves neither ID nor UID.
- Early runs printed hundreds of consent-string `ERROR:` lines from
  `gate_entry.gd` (`template % [tos, privacy]`), on the untouched
  baseline too (715 baseline vs 749): a stale resource import in this
  copy, not a defect. One `pnpm godot:isolated --import` cleared it;
  the suite now prints only the macOS CA-certificates engine notice.
  The import itself could not save its editor settings in the sandbox
  (expected; reported).
- `pnpm check:store-screenshots` fails in this copy because the
  gitignored capture proofs are absent ("device capture proof file is
  missing"), not on a fingerprint diff. No recapture: forbidden by
  the brief.

## Evidence

- `pnpm godot:isolated --timeout 150
  res://tests/test_production_host.tscn`: exit 0, 632 cases, no
  `SCRIPT ERROR`, no `FAIL`.
- `pnpm godot:isolated --timeout 150 --script
  res://tests/test_player_identity.gd`: exit 0, 403 cases.
- Negative control: old one-line `sign_in_provider` retry dispatch
  restored → 32/632 fail, including "retried link keeps the uid —
  got fake-cloud-uid, want uid-prod-alice" and "cloud still
  configured for the original uid — got fake-cloud-uid". Fixed bytes
  restored byte-exact (sha256
  `4448c3c95ac6b686328a99cb21e34c4eb74f0eae179f53a56b99004b50766576`)
  → 632 pass.
- `res://tools/check_scripts.tscn`: 164 scripts compile, exit 0.
  `pnpm check:hygiene`: repo rules ok. `--quit` smoke: exit 0.
