# Preserve the stride on the first target turn

Keep the successful fractional handoff, rig-authority hold, actual painted
render scale/light, physical action and visible mover lanes. Do not revisit
art or combat math. The director independently tested your latest Player
in a COW project, not the real tree or a device.

Read builds/hero-attack-review/gait_turn_entry_probe.gd and its log. The
same actual AnimatedSprite2D progress 2.75 survives a same-facing attack
after round 6. But first face LEFT, set walk frame 2 plus 0.75, then make
the production primary attack face RIGHT: the entry clock becomes 0.0,
losing the full 2.75 frames. face_toward calls _play_current before the
split starts, and play(want) resets on the direction change. The new
fractional tests pre-face the exact attack aim, so they miss this ordinary
moving-against-aim entry. A first attack turning to its target must keep
the current stride frame and fraction, just like a mid-attack retrigger.
Fix the production primary-turn path narrowly, without changing ordinary
idle/walk or sidearm ownership. Cover all six heroes with opposite
horizontal and vertical first-entry turns, nonzero fraction in walking
and idle, correct new sheet/legs column, one paused clock, exact recovery,
and unchanged gait rate. The provided turn probe must read 2.75 before
and after. Keep every existing assertion. A reverted first-turn fix must
fail the new checks.

Two documentation corrections are also independently confirmed. The
asset manifest still says every muzzle seat is untouched, but the seats
were deliberately recalibrated from centered hand constants to painted
wrists; state that the spawn agrees with the new painted muzzle while
combat timing, damage, range and counts remain unchanged. Also, the rig
bake cuts 80 torso/arm PNGs, but its two Eclipse profile off-hand nubs are
authored fixed templates with sampled paint colors, not literal atlas
cuts; describe that honestly while retaining the 82 PNG plus 6 JSON,
88-output count. Do not repaint them or regenerate existing art just to
make the prose true. Review this prose alongside the actual pack code.

The real root build log has a retained-gallery replacement entry from a
separate accepted release-tool run. Its public current text is supplied
as director-current-build-log.md, for context only. Do not add that
root-only entry to your candidate diff: acceptance would add it twice.
Instead move your own actor additions before the last existing baseline
entry, with at least three unchanged baseline lines after the insertion,
so your patch does not demand that the old baseline still be the root's
end-of-file. This leaves the root-only paragraph byte-identical on apply.
Do not remove root notes or alter protected files. Report any unresolved
patch conflict to the director instead of guessing.

Run the focused suite, supplied same-facing/facing-boundary/turn probes,
related hero/weapon/missile checks, rig --check and script compile. No
retry-to-green of a failing facing assertion. Report exact results and
remaining limits. No new features, auth, saves, UI, store images, counters,
network, devices, git or instruction changes. The director will judge,
render and accept independently.
