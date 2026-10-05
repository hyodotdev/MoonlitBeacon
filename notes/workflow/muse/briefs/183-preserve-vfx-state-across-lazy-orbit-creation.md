# Preserve VFX state across lazy orbit creation

Keep the node-budget optimization, unchanged 1200 limit, 18-node single-hand
shape, reviewed physical render and all original image bytes. The director
independently ran the current source in a COW project: node budget 126,
physical motion 6368 and late-game performance 73 pass (Knight Lv40 1198).
Restoring the prior eager Player plus scene makes 82/126 node checks fail.
Both files were restored byte-exactly after that diagnostic.

One narrow correction: the newly lazy ScytheOrbit loses two pre-existing
suppression/restore contracts. Read the supplied lazy-vfx-probe.gd. On a
fresh Player, set_vfx_suppressed(true) before applying Eclipse creates an
orbit whose _vfx_suppressed is false. On another fresh Player, direction
capture suppression true before applying Eclipse avoids allocating the
orbit, but direction suppression false afterward never recreates it, so
there is no active orbit. Both checks failed the independently pinned lazy source and both passed
with the prior eager Player/scene. Your later in-round review already
added `_ensure_scythe()` to direction restore; preserve that repair. The
state-at-creation draw suppression still needs to be inherited. Recheck
the actual latest source rather than treating a fixed finding as open.

Make lazy creation inherit current suppression state, and restoring
Eclipse direction effects activate the lazily absent orbit while retaining
single-hand allocation savings. Check other lazy effects for this same
state-at-creation issue, without adding speculative feature work. Do not
revert to eager allocation or alter physics/motion/combat math. Add
meaningful production transition coverage for these two sequences,
including repeated suppress/restore and no duplicate nodes. Keep all
existing checks. The supplied probe must pass, and reverting each repair
must fail its corresponding checks.

Run node budget, physical motion, direction-capture contracts, unchanged
late-game performance, script compile, rig --check and hygiene. The
root director will run full verification and render afterward; no need to
repeat unrelated long weapon comparisons for this small state propagation
repair. Update the build log's new allocation note with exact remaining
limits and results. No assets, store screenshots, devices, auth, saves,
counters, network, git, instruction changes or unrelated refactors.
