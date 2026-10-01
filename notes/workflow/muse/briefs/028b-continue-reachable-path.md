# Establish a player-reachable continuation race

## User words
"/loop-review 돌아서 확실하게 해줘 pr 만들어 이번에는 내가 승인"

## Director finding on round 1
The new regression currently opens Dialogue directly, waits while it
pauses the entire tree, then manually calls _finish(false) and continue_run
in the same frame. Dialogue.play sets get_tree().paused = true. A player
cannot receive a fatal combat hit while that modal pauses the game, and
ResultPanel accepts input only after its real 0.6-second gate. That fixture
therefore does not yet establish the acceptance criterion of a reachable
player defect. Do not call it confirmed merely because its assertion fails.

## Correction
1. Establish the race through an unpaused production path. Beacon discovery
   and a real fork or guardian announcement can schedule the strip worker
   while combat is active. Arrange a real route/beacon state using existing
   debug helpers if needed, but do not inject queues or a generation.
2. Let death happen with the tree unpaused. Observe the actual result input
   gate, skip reveal with real result input after the 0.6-second minimum,
   then use the real continue button callback with a valid isolated coin.
   Immediate same-frame continue alone is insufficient. Do not hold a
   synthetic modal through death or manufacture a stale timer by pausing
   it beyond a reachable combat sequence.
3. Trigger subsequent presentation with an actual beacon/fork/guardian
   path using production intervals. Measure elapsed timing and assert that
   the old worker wipes that new presentation on original code, then prove
   the fixed code preserves it and spends exactly one coin. Also show
   normal death suppresses old speech and a later queue remains usable.
4. If there is no reachable reproduction, remove the speculative arena
   change and its build-log claim. Return the evidence disproving the
   suspicion. A test-only characterization is acceptable if its assertions
   express real player behavior and pass original code, but do not leave
   a failing or synthetic-race regression just to keep the fix.

## Unchanged constraints
All limits and permitted paths in brief 028 still apply. No art, music,
balance, IAP contract, version, capture, fingerprint, proof or guard edits.
No real user save or store action. The director judges and reruns the
checks in your copy before acceptance.
