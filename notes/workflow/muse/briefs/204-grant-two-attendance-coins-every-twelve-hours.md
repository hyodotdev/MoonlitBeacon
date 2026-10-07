# Brief 204: Grant two attendance coins every twelve hours

## The ask
“코인은 그리고 반나절마다 출석하면 2코인씩 주고 반나절마다 알림을 보내면좋아 지금 출석하면 코인 받는다고. 그리고 알림은 설정에서 안받게 할 수도 있게 해야하고”

This task implements the real attendance reward. The next brief adds native reminders and settings, using this task's next-eligible time.

## Why, and what good feels like
Returning to the game gives two continue coins, at most once per rolling twelve hours after the last successful claim. The first eligible visit also receives two. Returning after several days still grants two, not a stockpile for missed periods. A notification never grants coins by itself. The player can keep playing while attendance is unavailable; no extra blocking login or tutorial.

## Where things stand
- Continue the same isolated cumulative copy after defeat recovery and unique adventurer-name work. Preserve their guards, tests and original title, existing saves, IDs, names, bests and purchases.
- `Vault.grant_continue_coins(count, transaction_key)` already makes a durable idempotent coin grant alongside purchased-coin receipts. Preserve all existing IAP receipts, balances and paid-continuation recovery.
- The production host/coordinator owns generation-bound Firebase operations. Anonymous Firebase guests count as accounts; local-only offline guests cannot establish server eligibility. The new name/intro service supplies the account's setup state.
- `firestore.rules`, `firebase.json`, version counters and credentials are protected. Only the additive cloud rules and their real emulator tests may be authored here. The director deploys a generated reviewed combination if needed.

## Do

### Confirmed shared-operation prerequisite

The director independently executed the real production
`delete_current_account()` wrapper while a name claim waited at token
refresh. The UID/coordinator stayed A, the actual deletion ticket became
nonempty, and the remote deletion body was held behind a latency barrier
(no real deletion). Releasing the name token dispatched `Alpha` to A
during deletion and returned `ok`. Proof
`builds/verify/gate-defeat-probe/name-token-deletion-round6.log`, clean
exit 1 in 2.5 seconds. The round-6 ticket checks UID/coordinator but not
the real in-progress deletion or its lifetime.

Before adding attendance calls, close this shared boundary: claim/load/
intro/backfill and attendance must not start or resume while deletion is
in flight. A request begun before deletion must remain cancelled even if
the deletion later fails while keeping the same account/coordinator; pin
the deletion generation as well as the account lifetime across awaits.
Register the actual begin-deletion barrier, not a test that only calls
`_retire_coordinator()` after deletion. Preserve retry after failed
deletion for a genuinely new request, and all preceding wrapper guards.
This is the only extra name correction in this attendance brief; do not
expand into unrelated old account behavior. The director reruns the exact
probe and all reviewed name/rules suites.

### Attendance implementation

- Add a small private account-owned attendance record and bounded REST service. Server time and ownership enforce a rolling 43200-second cooldown; use Firestore server timestamps and conditional atomic writes. Concurrent claims for one account yield one new receipt. Client wall-clock changes, time zones, repeated app launches and account/provider switches cannot reset eligibility. Return granted/already-claimed/cooldown/offline/error honestly, with the server-confirmed next eligible time for reminders.
- A first attendance read must yield authoritative not-found for the owner proved by the canonical ownership pair. Do not repeat the name-service defect where dereferencing a missing `resource.data.uid` produces 403 before the writer can run. Real 403/configuration errors must remain errors; strangers and private enumeration stay denied. Include the actual REST read-before-first-write route in registered tests.
- Derive remaining cooldown from a real server read/commit timestamp (for example the single-document `batchGet` read time), not from an assumed-correct device UTC clock. Supply both deadline and bounded remaining delay to the reminder API; an offline cached reminder must never become an authority to grant coins. Cover forward/backward device-clock changes in the client tests.
- Make acknowledged or uncertain claims recoverable across process death and failed local wallet writes. Apply exactly two through the real Vault with a stable receipt key once. Bind a claimed reward to its receiving install so another device cannot replay that same grant into a second wallet; a different device may claim the next eligible period. Do not invent cloud synchronization of existing purchased/device coin balances. Persist no auth token, email or raw native profile in the attendance data/cache. Report the exact receipt/receiving-install contract.
- Keep attendance replay state bounded for an endless game (for example an owner-bound monotone receipt watermark), rather than accumulating a new large wallet entry every twelve hours forever. Never evict purchased-coin transaction keys or make a pruned attendance receipt grant again. Bound failures must preserve playable wallets and report honestly.
- Wire a nonblocking claim on genuine account entry or foreground attendance after setup permits play, and on a later eligible foreground return. Never a background timer/notification/capture harness. Respect pending restore/account deletion/generation changes and retry only in bounded fashion. Existing players keep their living run. A new player can finish naming first; do not overlay attendance while an IME or NPC dialogue is active.
- Show a small world-skinned five-language receipt such as “출석 보상 · 계속하기 코인 +2”, only after durable local grant. Expose a safe view/signal for the upcoming reminder controller and a readable next-reward time where it belongs without redesigning the title/shop.
- Include attendance in atomic account deletion, preserving legacy unnamed and never-attended accounts. Update the player guide and private/public data disclosure accurately. Register focused service/host/Vault tests and extend the real rules-emulator tests.

## Do not
No native reminder/permission code yet, no new dependencies, new shop products, purchased-coin migration, release counters, original hero changes, combat rebalance, stores, marketing capture, network, deployment or git operations.

## Acceptance
- Real rules execution permits owner claims and denies strangers, forged timestamps/counts, premature retry, receipt reassignment and partial deletion. Seed an old server record to test twelve-hour boundaries without waiting twelve hours. Real REST concurrent conditional claims give one grant; existing cloud/name/legacy contracts still pass.
- Client tests cover first claim, just-before/at/after twelve hours, no catch-up stacking, restart, double tap, uncertain acknowledgement, wallet temp-file failure, stale callbacks, guest-to-provider link, another account and another receiving install. Two coins and its receipt survive reload together, with no replay and no loss after the remote claim was acknowledged.
- Offline or permission failures neither grant unverified coins nor block normal play. The notification layer can get the confirmed next eligible UTC time without being able to mint a reward.
- Supply a callable API note for the next brief; tests are registered and affected static/locale/docs/rules checks pass. Do not manually repeat all old game suites if sandbox editor-settings blocks the full runner; the director runs the cumulative full suite.
- Extend `notes/plans/gate-account-protocol.md` with the exact attendance methods, snapshot/signal fields and native-ready eligibility values, so the later lodge and reminder briefs can reuse one verified protocol without depending on a report file that the continuation runner replaces.
- Preserve each check's true exit status and full diagnostic log. For small Godot checks use a bounded 45-second timeout; a parse/settings error is not a successful check even if a later `tail` or `grep` exits 0. Do not repeat a sandbox-blocked command; report it for the director's normal environment.

## Primary references
- Firestore `request.time` equals a server timestamp in a write: https://firebase.google.com/docs/reference/rules/rules.firestore.Request .
- REST conditional writes and server-time field transforms: https://firebase.google.com/docs/firestore/reference/rest/v1/Write .

## How the director will judge
Read the actual remote-claim/local-grant ordering and receiving-install partition; independently run the client tests and real rules emulator with competing claimers and fault injection. Check wallet bytes and receipts after reload, and confirm entry UI remains playable without cloud availability. Preserve the original defeat and lodge work throughout.
