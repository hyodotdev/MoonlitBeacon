# Brief 010b: The readable caption must also clear the hero

## Confirmed defect in round 1

The director independently passed 40 gate cases, 24 quit cases and 236 staging cases and rendered all five quit titles. Japanese now fits. A real desktop `shot=all tag=director-caption-ko locale=ko` completed and its four rim pictures were inspected. The upper-rim caption lands at about y=132..184, centered at x=404; the actual hero stands at x=404 with its head/body around y=146..180. The second caption line crosses the hero's face/body and is visibly obscured. The geometry guard puts it on screen but introduces this overlap. Do not accept this as finished. Root still has the pre-010 gate, so the full round remains unaccepted.

The bottom-rim diagnostic also contains the initial tutorial banner over the third line. This is forced early staging, not evidence of a natural arrival while that banner is active. Make the rim diagnostic quiet with the existing staging mechanism so the intended caption can be judged, without changing production tutorial/banner behavior.

## Correct only this set

- Keep the current four-rim usable-screen guard, font/copy, tap-through and close/reset/plain behavior. When the caption would intersect the hero, place it at the nearest valid position that clears the real hero sprite bounds plus a small margin. Keep it associated with its gate and inside the usable screen. If a player reference is necessary, explicitly wire it from arena's gate-naming path; that limited arena edit is in scope. Do not change movement, combat, resources, scheduling, scores, IAP, versions or saves.
- Extend the real-camera gate test to reject caption/hero intersection, including the top placement just reproduced. Cover all six shipped heroes' actual sprite footprint at that placement, and keep the existing geometry and behaviors. Mutation-check the new clearance by disabling only it: round-1 placement must fail. Restore the exact production bytes.
- Keep the quit fix and elapsed-time/result-settling fix. Diagnostic rim staging should show a quiet readable gate and hero. Validate its actual player/camera/caption and the absence of the staged tutorial banner, rather than hiding a production defect. No marketing capture or device/network/git operation.
- Revise the one related build-log section to describe the final implementation and actual counts. No unrelated notes edits. Report the known sandbox limitations honestly as before.

The director will rerun new/neighbor checks and negative cases, render the four rims in five languages and inspect them at original resolution, then accept only after player and caption can both be read. The previous first-round Korean render is comparison material, not final evidence.
