# Brief 201: Claim unique adventurer names for scores

## The ask
“로그인했을 때 이세카이 게이트처럼 처음 어떤 방에서 튜토리얼 같이 다른 캐릭터가 플레이어한테 안내하면서 이름부터 정하게 하고 (중복없이 이게 바로 스코어 저장할 때 쓰여야해) 플레이가 진행될 수 있게 해줘.”

This brief builds the real account-owned unique name and score contracts that the next room UI will use. It does not build the room yet.

## Why, and what good feels like
A name chosen in the lodge identifies the same adventurer in the Hall, on every device and after linking a guest to Google or Apple. Two players submitting the same name simultaneously cannot both get it. Names do not replace or remint existing public IDs, cloud UIDs, journeys, entitlements or best scores.

## Where things stand
- The branch is `codex/gate-chamber-and-defeat-rules`, based on fast-forward-checked main `1ed5fb1`. Brief 200 corrects defeat/continuation before this run starts.
- This is a continuation in the same isolated copy because disk space is limited. Preserve the earlier defeat changes and their registered regressions. The director accepts the cumulative diff only after the name service and lodge are also independently judged.
- `player_account.gd` supplies durable `MB-` public IDs. `production_host.gd` owns sessions, generation-bound operations, entry plans, cloud restore and score mapping. `cloud_identity.gd` reserves canonical public IDs atomically.
- `cloud_schema.gd`, `cloud_hall.gd`, `cloud_coordinator.gd`, `cloud_account.gd` and `firestore.cloud.addition.rules` carry the current owned cloud contracts. Profiles and public-ID reservations are immutable pairs. Preserve that protection.
- Current Hall rows carry public ID, hero, score and cycles but no user-chosen name. Baseline `test_cloud_identity.gd` passes 54 cases. Real enforcement lives in `tests/cloud-rules/cloud-rules.test.mjs`; the director supplies its emulator/dependencies.
- `firestore.rules`, `firebase.json`, version counters and credentials are protected. Edit only the additive cloud rules and its tests; the director reviews/deploys a generated combined ruleset if required.

## Do
- Add private, account-owned adventurer metadata and a globally unique name-reservation pair (e.g. `mb_adventurers_v1/{public_id}` plus `mb_names_v1/{name_key}`). Bind both halves to the existing canonical public-ID/UID pair before and after every relevant atomic write. Never permit lone reservations, another owner's name, reassignment, public enumeration of private UIDs or a stale reply adopting the wrong account.
- Define identical client/server normalization and validation: 2–12 visible characters, precomposed Korean/Japanese/Chinese, Latin letters, digits and underscore; trim boundary whitespace, case-insensitive Latin collision keys, no path separators, controls, invisible/combining characters or ambiguous interior whitespace. Return clear invalid/taken/offline/auth errors. A Firebase-registered anonymous guest can claim a name; a local-only offline guest cannot falsely certify global uniqueness. Existing verified names remain usable offline from a bounded account-partitioned durable cache.
- Expose generation-bound load/claim/mark-intro-complete operations through the production host/coordinator. A successful durable claim returns the chosen display name and immutable key; an intro-complete bit changes only false→true. Restart after claim but before tutorial completion must recover the same name. Token refresh, account switching, cancellation, double tap, local write failure and uncertain network acknowledgement must be recoverable without stealing/reminting IDs or freeing an active name.
- Add the verified display name to new Hall score writes and mapped rows without losing hero, score, rank or stable owner ID. Preserve backward compatibility for unnamed existing rows and existing registration. When an existing player claims a name, attach it to their existing best row at the same score safely, with no invented zero-score record or best-score downgrade. Extend atomic account deletion to remove the owned name and adventurer metadata with existing rows, so deletion cannot strand a name or release it under a living score. Register client regressions and real rules-emulator tests; document the protocol and public nickname disclosure accurately.
- Cover the actual result recording route as well as cloud hooks. `Arena._on_result_record()` currently opens `LadderPanel.ask()` with an independently editable name and uploads via the legacy `GlobalLadder`. A verified named production player must not be asked for another name or allowed to publish a different one here: use the verified account handle for every new score/record, and route the player to a coherent owned Hall or read-only named result view. Preserve existing old records and course/unnamed fixture behavior without falsely labeling legacy names globally reserved. Register a real Arena/result recording regression, including account switch and local save retry.

## Required account-preservation regression before name integration
The director confirmed one remaining canonical-adoption defect in the preceding correction. `Vault.prepare_receipt_move()` currently returns `ready` as soon as the **source has no paid journal**, before it checks whether the canonical target already owns a paid journal. The director's actual production-coordinator probe at `builds/verify/gate-defeat-probe/target-pending-round4.log` creates target C's acknowledged one-coin receipt for journey `d1`/seal 6 with no surviving target files (a supported paid recovery state), plus an unrelated living source A journey `d1-other` with no source receipt. `_move_slot_to_canonical()` imports A into C, and `recover_paid_continue()` calls C's original paid receipt `stale` and deletes it. Clean exit 1, balance 1, `paid_target_restored:false`, `guest_file_retained:false`, `journal_retained:false`. No human data was used.

Fix this preservation prerequisite as part of the first-login account integration: a target's own pending paid recovery or existing journey is occupied even when the source has no receipt. Do not import unrelated source bytes over it or mix an unrelated source backup into it. Recover the target's exact acknowledged seal, retain the source bytes safely, and never debit again. Preserve the preceding rekey-first crash-window recovery and canonical/legacy retry behavior. Register source-with-no-receipt → target-with-receipt and occupied-target-with-no-source-receipt cases through the actual coordinator/host route, including reload. This exception permits the small migration guard/integration fix; it does not authorize combat or unrelated gameplay changes. The director will repeat the exact probe independently before accepting names or the cumulative diff.

## Do not
- Do not gate the current production play UI on these new methods yet; brief 202 integrates the lodge and entry gate.
- Do not build the room, edit existing hero assets, change gameplay, native provider SDKs, IAP, release counters, locked settings, stores or marketing screenshots.
- No network, deployment, git changes, real cloud data, secrets or protected deploy inputs. The director runs the actual emulator and deployment operations.

## Acceptance
- Two concurrent authenticated owners claiming the same normalized name yield exactly one winner in the real emulator; mixed-case Latin variants collide; valid Korean and Japanese names round-trip through real REST paths/encoding and rules. Invalid/invisible names fail at both boundaries.
- Client and real rules tests catch forged display names on Hall writes, mismatched/lone name pairs, stale account callbacks, arbitrary metadata changes, unverified offline claims, partial deletions and name release while a public score/owner remains. Existing ID ownership and legacy rule tests still pass.
- Linking guest credentials retains the verified name and original best/journey. Separate accounts never share the local nickname cache. Reload and retry after an acknowledged or uncertain claim restore one canonical name.
- Hall rows show the chosen name, actual hero and actual score, including a safely backfilled prior best; older unnamed rows still render honestly. Equal-score retry does not downgrade a newer best.
- Supply one callable API contract for brief 202, include all new registered tests and command results, and pass related cloud/host/locale/hygiene/docs checks. Test reports are claims; the director reruns the enforcement suite.

## Deliverables
Cloud name/schema/store services, production-host/coordinator operations, Hall name propagation, atomic deletion integration, additive Firestore rules and enforcement tests, registered Godot regressions, targeted reference/privacy-source clarification if needed, and the author-only protocol note `notes/plans/gate-account-protocol.md`. List exact public methods for the next brief. This note belongs in unprotected author plans, not the director-owned briefs/standing-orders tree. Later attendance/lodge/reminder tasks will extend the same note.

The public player-care privacy sources in `apps/player-care/content/{ko,en,ja,zh-Hans,zh-Hant}.mjs` currently describe a Hall with no name (for example English says “No name, email, account reference, token, or save appears in a Hall entry”). Update the factual disclosure in every supported language for the new user-chosen public game handle; keep the distinctions for private Firebase UID, credentials, email/profile and save data accurate. Inspect the actual locale filenames rather than inventing new ones. Regenerate the site's committed output with its build script and run its source/freshness tests. No deployment in the implementer's copy.

## Settle these yourself
Use separate adventurer metadata rather than making the canonical UID→public-ID mapping mutable. Keep nickname claims immutable initially: renaming is out of scope. Explain that this is a public game handle, not a real name. Only the initial claim requires online confirmation; previously verified returning accounts can use the cached handle offline. Bounded caches must not expose tokens, emails or raw native identity profiles.

The Japanese character set includes the ordinary prolonged-sound mark (e.g. `ルミー`). Backfill an existing best row by preserving its saved hero and cycles even if the currently selected hero differs; test that distinction explicitly.

Prove collision/error mapping with actual REST emulator responses, not just SDK `setDoc` tests. Do not call every permission failure "taken" (missing backend rules is a configuration failure). A name index exposing only the already-public handle/public ID, with no UID, credentials or private metadata, is an acceptable way to establish a collision; the adventurer metadata remains private. Alternatively distinguish the real atomic commit/precondition responses safely. Whichever design you choose, preserve ownership on both sides and do not expose another player's private UID during lookup.

The director has independently exercised the existing actual GDScript transport/identity registration against the local Firestore emulator (404 profile → 200 atomic commit → 200 owner reload). UTF name tests will use that same actual client path. Keep raw Unicode document resource names in commit JSON; URI-encode path segments only when constructing HTTP request URLs. Do not reserve a literal percent-encoded document ID in place of a Korean/Japanese name.

## Primary reference
Firebase String rules officially support `lower()`, `matches()`, `size()` and `trim()`: https://firebase.google.com/docs/reference/rules/rules.String . Match the explicit character allow-list on client and server instead of assuming Unicode normalization which either side does not implement.

## How the director will judge
Read every new private/public data boundary and write batch. Run the client tests and the real rules emulator independently, including a concurrency collision and ownership negative control. Inspect the Hall mapping. Verify raw local files and late callbacks under distinct fake accounts. Rendered room and native gameplay are checked in brief 202, not claimed by this service task.

Run affected registered suites, not another manual sweep of all existing 80 game suites. If `pnpm test:game` is blocked by the sandbox editor-settings error, report it and stop that check. The director runs the full suite on the cumulative result after the lodge integration. The real rules emulator is also the director's operation.
