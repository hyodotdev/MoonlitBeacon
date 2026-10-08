# Brief 208: Close real name boundaries and token switches

## The ask
Continue the user's first-login unique-name and same-name score request.
Correct the confirmed boundaries in brief 201 before attendance or the
playable lodge builds on this protocol. Preserve every preceding defeat,
paid recovery, account migration and name/Hall regression.

## Confirmed director evidence

1. **A fresh registered owner cannot start naming.** The director ran the
   actual GDScript CloudIdentity + CloudName + CloudTransport through the
   local Firestore emulator with six synthetic owners. Canonical ID pairs
   register successfully. `claim_name()` starts with a missing adventurer
   GET; the new rule uses `resource.data.uid` even when no row exists, so
   the server returns HTTP 403 before the atomic name writer runs. Korean
   `달빛기사`, Japanese `ルミー`, and Latin `Luna` all fail. Independent
   SDK inspection reproduces an owner's missing-row read as
   `permission-denied`, not authoritative not-found. Proofs:
   `builds/verify/gate-chamber-names-preliminary.log` and
   `builds/verify/gate-name-rule-boundaries-preliminary.log`, both clean
   exit 1. Permit an authoritative missing-row read only for the owner
   proven by the canonical ownership pair; keep other owners/private
   enumeration denied. Then confirm actual Unicode commit/reload,
   intro-complete reload, case collision and concurrent claim results.
   Do not translate every 403 to taken. A known public name-index lookup
   containing only display/public ID is acceptable for distinguishing a
   real collision from missing rules/configuration errors.

   A separate low-level actual GDScript writer probe already passes with
   the current atomic builder: raw Korean document names commit, reload
   and index GET correctly; intro completion and full six-row deletion
   also succeed. A competing real `exists:false` writer receives HTTP
   409 `ALREADY_EXISTS`, mapped to `conflict/precondition-failed`.
   Proof `builds/verify/gate-name-writer-preliminary.log`, clean exit 0.
   Preserve this working writer behavior; the first missing-row GET is
   the concrete blocker, not a need to rewrite the entire protocol.

2. **The immutable name can be released while its account stays live.**
   The independent emulator probe registers the canonical pair and the
   name/adventurer pair using ordinary authorized atomic SDK writes.
   Deleting only the name and adventurer, with no Hall row, succeeds while
   the profile/reservation remain. The rules require only the other name
   half and Hall to be absent, not the living canonical pair to be gone.
   Proof `gate-name-rule-boundaries-preliminary.log`: `partial_release`
   is `allowed`, `profile_retained:true`. Make an owned live name release
   part of the full atomic account deletion: no partial release under a
   living profile/reservation, no orphan or reassignment, including a
   name-only pair with no Hall/checkpoint yet. Preserve no-op missing-row
   deletes, legacy unnamed accounts and actual six-row full deletion.
   Check both ownership halves before/after relevant writes, not just
   client deletion order.

3. **A name request can cross a token wait onto a different coordinator.**
   The director executes the unchanged production
   `claim_adventurer_name()` method with a held token-refresh barrier and
   recorder coordinators. It begins under A, the configured account and
   coordinator retire to B during the await, then token completion
   resumes it. B receives `Alpha` and the old request returns `ok`.
   Proof `builds/verify/gate-defeat-probe/name-token-switch-preliminary.log`,
   clean exit 1, `account_b_calls:["Alpha"]`. The test overrides only the
   token latency and state observation, not the name wrapper. Capture an
   account/coordinator lifetime ticket BEFORE the token await and verify
   it after every async boundary. Claim, load, intro completion and Hall
   backfill must cancel when the initiating account retires, even before
   entering the coordinator service; a token failure must not dispatch a
   new mutation. Register production-wrapper regressions for all four
   routes, token refresh/switch/deletion/shutdown and stale completions.

4. **Restoring a claimed name erases a completed tutorial cache.** The
   director's real REST probe registers A, writes the Korean name pair,
   marks the server intro complete, configures the actual coordinator,
   calls its actual `complete_intro()` (cache true), then calls actual
   `claim_adventurer_name("Different")`, which correctly restores A's
   existing immutable name. However the restore result omits
   `intro_complete`; `_cache_verified_name()` defaults it to false and
   the Vault overwrites true. After `Vault.load_vault()`, the same owned
   name still has false. Proof `builds/verify/gate-name-restore-preliminary.log`,
   clean exit 1: `before.intro_complete:true`,
   `after_reload.intro_complete:false`, restored claim acknowledged/cached.
   Return the real completion bit on every restored/uncertain claim path
   and prevent an older incomplete same-name response from regressing
   this monotone durable bit. A new unrelated account must still start
   incomplete. Register the actual coordinator/Vault reload path plus
   delayed same-account claim-vs-complete ordering; the director repeats
   this exact emulator probe independently.

The director's probes are outside the isolated copy and are operational
measurements, not product fixtures. Reproduce the specified states in
registered tests; the director will rerun the exact independent probes.

## Also inspect

The current production `_map_hall_rows()` drops the server row's `display`
entirely, and `GateHallPanel` renders only rank/score, hero and MB ID. A
verified nickname must actually reach and appear in the owned Hall, not
only exist in stored payloads. Preserve the stable MB ID as a separate
field/line, add readable chosen-name presentation with the existing skin,
and register the production mapper-to-real-panel test. Legacy unnamed rows
keep their honest existing fallback. Cover Korean/Japanese maximum-length
handles and the actual row layout at 808×360 and iPad 4:3.

The new host method insertion currently leaves `_push_rank_to_hud()` below
`return filled` in `backfill_hall_name()`, rather than after
`_submit_best()`'s completion. Restore the actual score/HUD flow and pin it
with a named production result/standing regression. Do not weaken existing
rank propagation tests or treat a source-only assertion as evidence.

## Acceptance

- A fresh canonical owner receives a true missing-row response and can
  atomically claim/reload a Korean or Japanese name through actual REST.
- Exactly one concurrent owner wins a normalized name. The loser sees
  taken; unrelated permission/configuration errors stay truthful.
- Partial name/adventurer release is denied with either canonical half
  still alive; full owned deletion succeeds for named and unnamed users.
- The production token-barrier probe returns cancelled with no call to B.
  All four wrappers and their registered callback/refresh tests agree.
- A completed name restore retains the true tutorial bit after local
  reload, and a late incomplete same-name response cannot regress it.
- The actual named result uses the verified handle and same saved hero,
  score and cycles; best completion reaches HUD standing again.
- Earlier defeat, paid journal, canonical/legacy adoption and existing
  name/Hall/deletion tests stay green. Update the exact shared callable
  contract in `notes/plans/gate-account-protocol.md` for the next brief.

## Scope and checks

During round 5 the director observed a concrete parser failure in the new
host tests: `test_production_host.gd:1209` split
`await (host as Node)` and `.claim_adventurer_name(...)` onto separate
lines without a continuation. The analogous load/intro calls had the
same shape. The host command stayed alive until the wrapper timeout because
the scene script never loaded. Round 5 has since repaired that syntax and
restored the registered calls. Preserve those repairs and run the
registered host scene with its real exit status. A pipeline that only
greps `FAIL|cases` omits `SCRIPT ERROR: Parse Error` and can report shell
success after timeout; it is not evidence of a passing suite. Preserve
complete output and the wrapper exit code, and report any sandbox-only
platform errors separately. Small Godot checks need a 45-second bound,
not another five-minute timeout. Do not repeat a sandbox-blocked check;
the director runs it in the normal environment.

The independent reverse partial-deletion probe already passes: deleting
only profile/reservation while the name pair stays is denied, and the
public name remains. Proof `gate-name-orphan-preliminary.log`, exit 0.
Preserve that existing protection while fixing the opposite name-only
release described above.

Only these confirmed name integration boundaries and their meaningful
tests/documentation. No room, attendance, native SDK changes, release
counters, original hero edits, live network, deployment, git or marketing
recapture. Keep all six director-provided raw art source files untouched.
Run affected suites/static/locale/care/docs checks; do not manually sweep
all old suites if the sandbox editor-settings error blocks the full runner.
The director supplies the real rules emulator and cumulative verification.
