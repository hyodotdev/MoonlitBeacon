# Brief 072: bound rank refreshes while the first reply is still in flight

## Confirmed evidence
The director ran a clean isolated project using your actual CloudHall/CloudSchema files and a transport that delays each read by 100 ms. Three simultaneous `fetch_self_rank` calls for the same bound ID at the same injected time produce **gets=3, posts=3, outcomes=3**; all return the same Knight best score 100 / rank 1. The log is `director-hall070-concurrent-clean.log`. There is no known pair yet, so the current throttle falls through on every caller. This violates the complete-refresh five-second bound and is reachable when deferred canonical adoption, checkpoint acknowledgement and explicit refresh overlap.

## Correct
Make the entire owned-row-plus-rank refresh own a generation-safe in-flight ticket before the first await. Concurrent callers may await the same result or return a clearly labeled pending/throttled response, but must not start more reads, invent rank, combine different row/rank pairs or permanently strand a lock. A submit/cache invalidation, account switch (including A→B→A), cancellation, timeout or late old reply must retire the right ticket without releasing a newer one. Keep no-argument Coordinator APIs compatible. Add meaningful delayed/concurrent and recovery tests, and preserve the historic Knight100/new Dancer10 association, missing-row unranked semantics, cache bounds, existing payout/baseline safeguards and source timestamps.

The coordinator test run must finish cleanly, not hang awaiting a fake reply whose scripted order changed after the new owned-row read. Bound failure paths in the focused fixture so a missing reply reports a test failure promptly. Do not weaken assertions or discard prior safety scenarios.

## Scope / judgment
Only the assigned Hall/Coordinator/helpers/tests and their contract/log files. No host/UI/native/PlayerAccount/Vault/Journey/shared runner/package/locked project/art/network/deployment/history changes. The director will rerun the same simultaneous probe (one owned read and at most one aggregate read), read the historic best/missing-row fixtures, run all Hall and Coordinator cases and perform a restored negative control before ordinary acceptance.
