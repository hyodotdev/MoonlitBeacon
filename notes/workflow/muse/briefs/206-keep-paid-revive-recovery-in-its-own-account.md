# Brief 206: Keep paid revive recovery in its own account

## The ask
Preserve the user's login-owned last-played journey while fixing coin continuation. A paid recovery must never transfer gameplay into another account.

## Confirmed evidence
While independently reviewing brief 203, the director ran the actual journal API in isolated storage:
1. `Journey.use_account(MB-a...)`, write terminal seal 5.
2. `Vault.begin_continue_txn(journey, 6, alive_text)` acknowledges the debit; reload Vault before materializing the checkpoint.
3. `Journey.use_account(MB-b...)`, whose checkpoint slot is empty.
4. `Vault.recover_paid_continue()` returns `recovered`, writes account A's alive checkpoint into B's slot and clears A's journal.

Proof: `builds/verify/gate-defeat-probe/account-result.log`, director operational probe exit 1, `wrong_account_import: true`, `journal_retained: false`, balance 1. No real account data was used.

The actual result-button routing also strands the last paid coin: start with one coin, seal a real defeat, inject `Journey.InstallFault.FAIL_ALL` for the alive install, then call `continue_run()`. Balance is 0 with a journaled paid revive. `ResultPanel.reopen_after_failed_continue()` followed by the real `_request_continue()` emits `continue_purchase_requested` instead of retrying that already paid transaction. Proof: `builds/verify/gate-defeat-probe/last-coin-result.log`, `routes.purchase: true`, `routes.continue: false`. This routing probe disconnects scene-swap subscribers only so its exit does not launch an asynchronous shop; the production button method itself is unchanged.

## Do
- Bind every pending paid revive to its exact owning public-account/save slot as well as its typed journey ID and attempt. Recovery on another account is deferred without touching its files, notifying its cloud hook or consuming/discarding the original pending receipt. Account switch, token refresh, deletion and guest-to-provider linking must respect ownership.
- Keep A's pending paid recovery recoverable while B starts, plays, quits or continues its own run. Do not overwrite A's pending receipt with another attempt/account, and do not clear it merely because B's file is empty or contains a different journey. Avoid blocking ordinary B play; explicitly abandoning A's paid revive requires the existing user-confirmed fresh action in A's scope.
- Keep the debit/journal atomic, preserve all purchased-coin and shard receipts, and make same-attempt retry validate the exact journaled seal/owner rather than treating any equal numbers as an acknowledged transaction.
- Register isolated account-A/B reload/switch tests (including B empty and B with a living run), late cloud hooks, B fresh and B paid-continue, then switch back to A and prove exactly one debit and its correct original revive. Preserve the prior corrupt-main and stable-hook fault tests.
- Let the real loss-result button retry its own acknowledged pending revive even when its debit spent the last coin. Show a localized save-retry state rather than sending the player to buy another coin. A true zero balance with no owned pending receipt still goes to the shop as before. Register this real button/signal route and prove recovery never charges again.

## Do not
No names, attendance, room, native auth, IAP behavior, version counters, network, stores, git or marketing screenshots. Do not relax tests to permit transfer or silently lose the first paid recovery.

## Acceptance and judgment
The director's actual A→empty-B probe no longer imports any checkpoint into B; A's pending receipt survives until A is restored. Registered multi-account tests prove both attempts can settle independently, balances and receipt bytes survive reload, and unrelated account files remain byte-identical. Run affected Journey/Vault/arena/coordinator/host tests only. If the full runner hits the sandbox editor-settings block, report it and stop; the director runs the cumulative full suite after the remaining features.
