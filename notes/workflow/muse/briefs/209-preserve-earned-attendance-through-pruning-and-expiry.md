# Brief 209: Close earned attendance and deletion boundaries

## The ask

Keep the requested rolling twelve-hour two-coin attendance reward reliable.
Correct only the three independently reproduced boundaries below,
then supply the verified protocol for the lodge and reminder briefs.

## Confirmed evidence

The director executed the actual Vault in an isolated HOME, using a
durable generated install ID and a synthetic purchased-coin receipt. Ten
different canonical public IDs each received one acknowledged attendance
grant one minute apart, all within one twelve-hour cooldown, then the
Vault reloaded. Replaying the first public ID's identical
old receipt increased balance from 27 to 29. Both its receipt and owner
watermark had been evicted at eight entries. The purchased receipt stayed.
Proof: `builds/verify/gate-defeat-probe/attendance-pruned-owner-round7.log`,
clean exit 1 after 2.4 seconds. Same-owner long-history tests miss this
cross-owner pruning boundary.

The director also executed the real coordinator, attendance service,
transport and Vault with a scripted sender and real filesystem failure.
The server commit acknowledged a reward at 2026-10-06T21:00:00Z while a
directory at the actual wallet temp path prevented its local save. The
coordinator returned `local-grant-failed` with `server_claimed: true` and
the old receipt. After removing the fault and reloading the Vault, the
next visit read that same owned server row at 2026-10-07T10:00:00Z. The
service overwrote it with the next eligible claim and granted only the
new two coins. Balance was 2 then 4; the previously acknowledged two
coins never recovered. Correct total is 6: two initial coins plus two
earned visits. This is no missed-period stockpile.
Proof: `builds/verify/gate-defeat-probe/attendance-expired-recovery-round7.log`,
clean exit 1 after 1.4 seconds. No human account, token or wallet was used.

The director ran the real `CloudAccount.delete_account_data()` REST route
after the actual attendance service's first conditional server claim. All
attendance reads/claim/hold/race checks passed, but full account-data
deletion returned `permission-denied` with four remaining steps:
`hall`, `checkpoint`, `reservation`, `profile`. The source commit builder
still omits the attendance row, while the new rules correctly require it
gone with the canonical halves. The registered rules suite's updated SDK
helper covers a different, correct payload; it does not verify this actual
client route. Proof: `builds/verify/gate-attendance-rest-delete-round7.log`,
clean exit 1 after 2.4 seconds. Only emulator identities/rows were used;
Firebase Auth deletion was never called.

## Do

- Preserve a bounded durable replay guard when attendance receipt keys
  and owner entries prune. An evicted owner must never regrant an already
  applied receipt. Preserve every purchased receipt and balance. Handle
  a genuine new account/period and timestamp ties honestly; a bound
  failure must preserve the playable wallet rather than silently grant
  or lose replay protection. Register the actual multi-owner reload case.
- Recover a previously acknowledged, locally unapplied owned reward
  before advancing to the next eligible period. Preserve the exact
  durable earned amount across restart, failed wallet writes and an
  uncertain acknowledgement, including when the visit is after twelve
  hours. Do not erase the last recoverable earned receipt merely because
  a new period or another receiving install can now claim. Choose a small
  bounded protocol rather than a full cloud-wallet synchronization or
  indefinite list of twelve-hour receipt documents. Purchased balances
  remain local and outside this protocol. Explain the exact recovery and
  bounds in the durable API note.
- Include attendance in the actual account deletion plan, commit body and
  remaining/completed-step contract for both named and unnamed accounts.
  Preserve idempotent deletion when there is no attendance row, and never
  delete native Firebase Auth until the single remote data commit really
  succeeded. Register the actual client builder/transport route and run it
  through the emulator; a hand-authored SDK helper is not that evidence.
- Register the real service/coordinator/Vault boundaries above, including
  retry after the first acknowledged save failure, restart, next-period
  receipt, another receiving install, double replay, purchased-receipt
  preservation, attended-account deletion and any new remote
  conditional/rule transitions.
- Keep the working claim APIs/deadlines usable by briefs 202 and 205.
  Update `notes/plans/gate-account-protocol.md` with their exact verified
  methods and fields. Do not rely on an overwritten implementer report.

## Preserve

The director independently passed the existing cumulative real rules
suite: 84 tests in 14 suites, zero failures; the attendance service suite:
62 cases, exit 0; actual client REST owner first read, first claim,
same-install reload, cross-install hold, stranger denial, standalone
attendance deletion denial and competing claims: exit 0. Those passes do
not waive the three confirmed failures. Preserve all preceding name/deletion,
defeat/paid-revival, Hall and original-hero contracts.

## Do not

No lodge or native reminder implementation in this correction, no new
dependencies, purchase migration, title/provider/button redesign,
release versions, stores, network, deployment or git operations. Do not
broaden into speculative old-account or anti-abuse work.

## Acceptance and director judgment

All three exact operational probes pass with true clean exits. Registered
affected tests cover the previously missed boundaries. The director reads
and executes the actual remote conditional protocol with the emulator,
independently verifies coins and receipts after reload, then continues
the playable lodge and native reminders.

Use 45-second bounds for small Godot checks and preserve their true exit
codes and complete logs. A parser/settings error is not a pass. Do not
repeat the sandbox-blocked full runner or manually sweep all old suites;
the director runs the cumulative full suite after the final integration.
Round 7 used commands such as a 280-second host run piped through
`grep` and `head`, whose tool exit was 0 while its output said the suite
failed. Stop using this pattern. Redirect the full log to a file, retain
the original runner exit, and read diagnostics in a separate operation.
