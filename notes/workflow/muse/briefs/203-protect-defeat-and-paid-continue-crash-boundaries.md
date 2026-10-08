# Brief 203: Protect defeat and paid-continue crash boundaries

## The ask
“죽으면 코인으로 계속하거나 이어서 처음으로 가야하는데 그 스테이지에서 시작하는게 있네? 이거 수정해주고”

Correction to brief 200: defeat must remain terminal through recovery, and an unpaid continuation must never become durable/playable.

## Evidence to verify before changing
- `Journey.write_checkpoint(ended)` rotates the previous **alive** main into the backup. `read_checkpoint()` falls back to that alive backup when the terminal main is corrupt/missing. The new terminal test instead manually overwrites the backup with an ended payload before corruption, so it does not test the file pair produced by the real writer.
- `Arena.continue_run()` writes a newer **alive** checkpoint and notifies its stable/cloud hook before calling `Vault.spend_continue_coin()`. A process death at that boundary leaves a resumable checkpoint with no durable coin debit. A failed wallet write followed by a failed tombstone rewrite has the same result. The happy path and isolated single-write-failure cases do not prove crash safety.

The director reproduced both in isolated storage on 2026-10-07:
- `builds/verify/gate-defeat-probe/result.log`: actual writer, then corrupt primary; exit 1 with `free_resume: true`, `recovered_ended: false`, checkpoint 2.
- `builds/verify/gate-defeat-probe/paid-result.log`: at the alive stable hook, balance still 2 and checkpoint resumable; inject blocked wallet temp and `InstallFault.FAIL_ALL` for rollback. `continue_run()` returns false, balance stays 2, but `has_valid_checkpoint()` returns true. Exit 1. This observes the production code rather than a simulated ordering.

Preserve existing results, score settlement and living-quit behavior.

The director independently reran the registered suites on this initial implementation: defeat 95, Journey 519, coordinator 1167 and production host 804 cases all passed, with exit 0. The two additional probes still fail. Add the missing boundary coverage rather than relying on the existing green suites.

## Do
- Add registered regressions using the **actual** file pair left by normal defeat. Then corrupt/delete the main, reload independently and attempt title/host/resume entry. No surviving older backup or local cloud state may revive this ended journey. Mirror or journal terminal authority durably without destroying unrelated account/run data; preserve healthy alive backup recovery.
- Make paid continuation durable as one recoverable protocol: before a checkpoint is considered alive/resumable or notified/uploaded, its coin debit must be durably acknowledged. Tie any interrupted transaction to the same journey/attempt and ensure retry cannot double-charge, lose a coin or give a free revive. Do not rely on best-effort rollback across two independent saves. Retire any stale ended cloud candidate according to the same transaction's acknowledged newer seal, keeping existing generation/account guards.
- Exercise interrupted execution at each durable boundary, both write failures together, reload and double tap with meaningful fault injection. Include stable-hook observations proving no unacknowledged alive payload reaches the cloud. Report exact outcomes, register the tests and rerun the touched journey/Vault/arena/cloud/host suites.

## Do not
No new names/lodge work in this correction. No native auth, IAP grants, account IDs, version counters, network, stores, git, marketing capture or weakening tests to accept the defects.

## Acceptance
The normal defeat writer's redundant state cannot resurrect after one failed primary file; a crash before durable debit leaves no free resume, and a crash after durable debit recovers a single paid continuation without another charge. Coin balance and receipts agree after reload. Existing living checkpoint recovery, result rewards and cloud ownership continue passing. Supply one negative control for each new guarded boundary which the director can independently run.

A legitimate acknowledged paid continuation must also restore on another client that previously observed the defeat, using the newer alive seal. Intermediate local transaction state must not poison that comparison or publish a resumable checkpoint before payment. Test this explicitly with the real coordinator fixture.

## How the director will judge
Read the actual persistence order, run the registered fault/reload tests in isolated storage, break the two guards temporarily to observe failures, and compare wallet/checkpoint/hook bytes rather than trusting the report.

## Verification scope for this continuation
Run the affected registered suites and static checks. If `pnpm test:game` is blocked by the known sandbox editor-settings failure, report that exact block and stop that check; do not repeat the manual sweep of all 80 existing suites. The director runs the full game suite on the cumulative result after briefs 201 and 202. This correction should focus on the two confirmed persistence defects.
