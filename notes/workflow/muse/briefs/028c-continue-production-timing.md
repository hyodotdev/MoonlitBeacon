# Keep real charge and travel time in the race evidence

## User words
"/loop-review 돌아서 확실하게 해줘 pr 만들어 이번에는 내가 승인"

## Director finding
The rewritten round-2 test fixes the paused-death and result-input problems.
It still calls _on_gate_entered immediately after Continue, and then calls
debug_light_next_beacon immediately after the fade. The test labels this
"Travel plus the next real beacon", but it omits player travel and the real
1.3-second charge/choice. Those shortcuts create the very timing window
under investigation. A debug helper may arrange a starting state; it may
not erase production intervals used to prove reachability.

## Required decision
Establish the race at time_scale 1 with realistic post-continue production
intervals. Inspect ALL _say_after_discovery callers, including world-rule
announcements on entering a zone: the victim may be a deferred omen rather
than a second beacon. For a beacon victim, actually use the production
charge/choice path and its normal duration after Continue. For a gate
victim, establish that the death location can be reached during the guard
from a real lit beacon using attainable movement/dash values; do not claim
instant _on_gate_entered is elapsed player travel. Initial state fixtures
are allowed, but the timing argument must count the skipped earlier travel
if it limits how long the old worker could remain alive.

One candidate without a second charge/gate shortcut is moonfire awakening.
_activate_moonfire calls _say_after_discovery, and the charge survives
Continue. A realistically almost-full gauge after the first beacon plus
an automatic kill of a surviving ranged target outside the 132px continue
clear radius and its real ember pickup may defer a new awakening line
inside the old worker's window. Check that route rather than assuming it
works; leave its voice moment unspent and count actual projectile/pickup
times. An attainable initial gauge/target fixture is allowed; directly
injecting the final voice queue, faking a pickup signal or calling the
awakening merely to meet a deadline is not evidence of this path.

Measure the live original/fixed outcomes and timing. If the bug cannot be
reached, revert the speculative arena change and build-log claim, and
remove the artificial race assertion. A truthful passing characterization
of natural death/continue is acceptable. Do not substitute "closed by
construction" or possible future changes for evidence of a current player
defect. The director will accept no production fix without that evidence.

Only the paths and constraints in 028/028b apply. No timer, movement,
balance, art, sound, IAP, version, capture, proof, guard or network changes.
