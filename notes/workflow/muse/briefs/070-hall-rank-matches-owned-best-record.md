# Brief 070: the player's rank, hero and score describe the same Hall record

## The ask
“랭크는 캐릭터랑 점수가 잘 나와야하고 플레이어 아이디는 고유로 ... 명예의 전당 붙여서 계속 랭크 보여주면 어때?” The ongoing HUD must show the player's actual Hall standing with the hero/score attached to that record.

## Confirmed semantic mismatch
The accepted coordinator's `refresh_rank()` derives the active checkpoint's score, then `CloudHall.fetch_rank` counts every Hall row strictly above that score and adds one. Hall stores ONE BEST row per public ID. Consider the board containing just our own Knight record at 100, then we explicitly start a fresh Dancer journey at 10. Its aggregate query (`score > 10`) counts our own previous record (1) and returns rank 2, although the board contains only one player and our actual record is rank 1 at 100/Knight. Even without this arithmetic edge, displaying that rank beside the fresh Dancer/live score would mismatch the record the Hall ranks. The existing contract deliberately described checkpoint-relative score comparison; the final product must use actual best-record standing.

## Where things stand
Owned-cloud foundation and coordinator are accepted. Coordinator passes 750 director cases, related Journey 484, cloud service suites and 38 genuine rules-emulator cases; three failed-save/interleaving reproductions and upload generation ownership are verified. Preserve those. A production host is implementing presentation in another copy, using `refresh_rank()` with no arguments and `rank_snapshot()`; keep that API compatible and document any additional fields exactly. Native, painted art and the host do not belong to this task.

## Do
- Add a validated, generation-safe read/cache of OUR actual `mb_hall_v1/<canonical-id>` row, and rank its actual best score against the Hall. Carry its `hero`, `score`, `cycles`, `public_id` with the rank result/snapshot so presentation never combines a cached rank with a different hero/score. Keep ID ownership checks and safe resource-path validation.
- A missing own record is genuinely unranked (no invented #1, no invented submission). Submission success/not-best and another device's higher record must converge to the actual server record. Preserve current gameplay/local checkpoint data; ranking neither rewrites nor floors a journey. Empty/failure/offline cache states are clearly labeled and bound to the same account.
- Keep the complete self-row + rank refresh bounded/throttled (the existing global five-second window and bounded cache); fetching the own row on every score change would evade the throttle. Preserve timestamps/score association of stale results. Do not claim simultaneous global snapshot consistency from two ordinary HTTP reads; if needed, label the measured cached snapshot accurately.
- Add targeted scene/service tests for own previous best > current journey, correct historic hero versus newly selected hero, missing own row, another device's better row, tied scores, malformed rows, offline labeled cache, switch/cancel during own-row/aggregation awaits, concurrent calls and bounded requests. Existing coordinator baseline/receipt/pending/lock behavior must remain green. Update the host contract and log.

## Do not
No production host/UI/Arena/native/PlayerAccount/Vault/Journey, shared runner/package/locked project values, art, deployments/network/device/store/history, currency/IAP sync, fake production seed rows, or anti-cheat-authority claims. Do not change public collections/rules/index requirements silently; if a query needs a real new index, provide its additive entry and explain the contract.

## Acceptance
Director fixtures reproduce the one-player 100/Knight versus current 10/Dancer case as actual rank 1, score 100, hero Knight; absent row stays unranked. The current no-argument coordinator API remains host-compatible; all relevant suites and a broken-line negative control pass/fail appropriately, and real rules remain valid. Report exact commands and request budget, then finish through ordinary Muse harvesting.
