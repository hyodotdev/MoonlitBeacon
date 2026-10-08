# Brief 207: Recover paid journals through canonical slot moves

## The ask
Keep the user's already-paid continue recoverable when login adopts an existing canonical public ID. Preserve all preceding defeat and account ownership guards.

## Confirmed evidence
The director ran the actual `CloudCoordinator._move_slot_to_canonical()` against isolated Journey/Vault storage after brief 206:
- Guest slot A contains ended seal 5 and an acknowledged one-coin journal for alive seal 6, owned by A.
- Occupy `Vault.TEMP_SAVE_PATH` with a directory, producing a real wallet save failure.
- Set the real coordinator's requested partition to A and canonical ID to C, with the real Vault; call its slot-move operation.
- It moves both journey files out of A into C, ignores `rekey_continue_txn_owner()` returning false, adopts C and reports no save error.
- Remove the fault and reload the wallet. Recovery on C returns `deferred`; the receipt still owns A, whose files no longer exist. The paid revive is stranded.

Director operational probe: `builds/verify/gate-defeat-probe/rekey-round3.log`, clean exit 1, `guest_file_exists:false`, `canonical_file_exists:true`, `journal_owner:A`, `paid_revive_recovered:false`, balance 1, empty save code. This exercises actual production code with fake public IDs and no human data.

## Do
- Make the joint journal/file adoption recoverable across failed journal writes, failed/partial slot moves and process death between these operations. A failure must keep an explicitly recoverable receipt and slot association, not merely its old bytes in a now-unreachable owner scope. Retry after restart must converge without a second debit or importing into an unrelated account.
- Do not ignore migration/rekey failures in coordinator/host startup or canonical adoption. Carry a truthful safe error/retry state where necessary, and retain ordinary play/save behavior for accounts with no pending paid continue.
- Register a real coordinator/host adoption regression with actual Vault temp-path failure, reload and retry. Verify exactly one debit, correct alive seal 6 under the final canonical account, no stale cloud hook for another account and no orphan receipt. Add a process-boundary fixture for the chosen write order. Occupied canonical slots and account deletion still preserve the unrelated account and the prior scoped-journal tests.
- Review the comparable `adopt_legacy_continue_txn()` integration sites for the same ignored-failure problem and cover a confirmed legacy-to-owned paid receipt adoption boundary.

## Do not
No names, attendance, room, native identity SDK changes, IAP change, counters, network, git or store operations. Do not loosen the owner guard, adopt any arbitrary foreign receipt, drop an acknowledged paid revive or handwave that a user can buy another coin.

## Acceptance
After the fault is removed and the account resumes/restarts, the paid transaction reaches the correct canonical slot with no extra charge; the director's probe and registered production-route fault cases pass. Earlier corrupt-main, debit-before-alive, A/B isolation and last-coin result routing stay green. Run affected suites only; no manual sweep of all old game suites if sandbox editor settings blocks the full runner. The director runs the cumulative full suite later.
