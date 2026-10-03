# Brief 130: own restore completion and timeout exit

## The ask
“아이패드 로그인도 해줘야지 게스트 로그인은 잘돼? 이제 로그인 사용자 마지막 어디서 플ㄹ이했는지 알고 플레이 구간 있음 거기서 띄워주는거야?”
Finish the initial restoration guard from 129 with correct ownership and a usable bounded escape.

## Confirmed evidence
Director-only isolated probes (no production file changes) observed the R1 candidate:
1. _retire_restore sets _restore_fetch_seq=0; the next account claims sequence1 again. _release_restore_fetch takes only the sequence. A direct operational runtime probe with new generation42/live sequence1 and a retired sequence1 completion clears the NEW claim (new_fetch_claim_lost=true; exit0/no ScriptErrors). The existing switch test delays B's profile too, allowing A to complete before B's claim, so it does not cover the harmful ordering. Reproduce a natural two-account sequence where A's old checkpoint is held until B's checkpoint is already pending, then release A. B's claim/deadline must survive; B failure must show Error, not remain checking forever.
2. The real HungSender fixture with FakeClock and restore_timeout_seconds0.3 reaches restore_failed=true/reason restore_timeout, but accept_offline_entry returns refused/restore_in_flight. The advertised offline button cannot act until the orphan reply arrives. Exiting Busy is not a bound if the failure UI's advertised decision stays refused indefinitely. This is directly measured through inherited fixture/runtime (exit0, no ScriptErrors).

## Do
- Fix completion/release ownership across retired and newer generations, including returning to the same UID/public ID. Use a never-reused fetch identity or verify owning ticket/generation consistently on release and late adoption.
- On elapsed timeout, safely retire the initial restore operation before allowing explicit offline choice or retry. Its late reply must never install into a newly started journey or unlock/change a newer check. A narrow coordinator-owned restoration cancellation/epoch hook is permitted if required; preserve profile/settlement/rank/conflict semantics. Do not invalidate unrelated operations merely to abort a read.
- Keep actual retry/offline actions available at timeout as promised by the screen; honest network failure still needs explicit choice. Multiple taps create one active restore attempt. Late retired responses cannot overwrite local journey bytes, change Ready/Error for the new attempt, or grant anything.
- Director windowed renders also show identical failure headline and body repeated. Use the body to explain the offline decision: it uses this device's saved journey, and starts a fresh journey if this device has none. Keep the existing crafted style and fit all locales/framings.
- Add registered regression assertions for A held -> B held -> A late -> B failure/deadline; A signout/relogin A with newer generation; timeout -> explicit offline -> plan fresh while old read remains held -> release old valid remote (no install); timeout -> retry while old read held -> old reply first -> new failure/success; repeated taps. Tests should inspect live UI and save bytes as well as host state.

## Do not
Do not redesign UI/art or native auth. Do not weaken prior guards/tests. The R1 timeout test's orphan-retry refusal is the defective behavior; replace that expectation with safely retired/retryable behavior and preserve its no-late-overwrite intent. No user data, credentials, cloud rules or network work.

## Acceptance
All existing/new host assertions and related coordinator/entry/locale/hygiene checks pass without ScriptErrors. Director negative must catch unsafe old-owner release or missed entry guard. Timeout makes an honest actionable failure, explicit offline planning works before an orphan returns, and old valid bytes never mutate a newer local journey. No regression in local guest/resume, provider retries or per-account binding.

## Deliverables
Narrow R2 patch to R1 files plus apps/game/scripts/cloud/cloud_coordinator.gd and its registered tests only if required for safe restoration retirement; notes/plans/4-0-0-build-log.md. Explain cancellation and in-flight ownership. Preserve all accepted root packets and all R1 sound changes.

## How the director will judge
Read full R2 diff and report, run host/coordinator/entry checks independently, reproduce both operational failures and inspect actual UI, guarded-line negative and exact-byte restoration before normal accept. Root verify and sequential native export/install follow acceptance.
