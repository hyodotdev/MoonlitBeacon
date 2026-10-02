# Brief 030b: complete the same boundary fix for Wide Arc

## Confirmed remaining path
Your round-1 report explicitly leaves the same antipodal failure in an ordinary attack widened to 360 degrees. This path is reachable: Wide Arc's amount is 1.25, `_feed` caps attack_arc at 360, and five Warden stacks take the default 130 degrees past that cap. The same float32-PI angle is rejected when half_arc is PI and the special full-circle flag is false.
The user asked for a reliable whole-release loop review, so leaving this same defect in a reachable full-circle path is not a complete correction.

## Correction
- Extend the narrow fix to every actually full-circle melee arc, including the 360-degree Wide Arc cap. Preserve all partial arcs below 360, radial limits, Eclipse inner hole, damage, cadence and VFX.
- Add a regression using genuine Wide Arc card takes to reach the cap and verify rear hits, with an ordinary partial-arc control. Include a portable precision case which fails under round-1's special-flag-only logic rather than trusting the host's antipodal angle rounding.
- Keep the original 355 checks and round-1 additions. Use the smallest clear production change; do not refactor unrelated combat code.
- Make the comment describe the portable float boundary. An exact Linux angle value was not measured in this copy; do not claim that host measurement as evidence.

## Verification and scope
Run the existing weapon scene through `pnpm godot:isolated`, a meaningful negative control, and hygiene. Report the known sandbox limitation of the standard full suite; the director independently ran the actual standard `pnpm test:game` successfully for round 1 and will run final root verification after acceptance.
Do not reimplement the suite, pipe a failed command through tail without preserving its exit status, or author scratch scripts/logs outside this copy. Your /tmp measurement files violated the copy-only standing orders; the director will preserve and remove only the identified files as an operation. All new measurement output belongs in an ignored directory inside your copy. No recapture, network, git, version, asset, or unrelated changes.

## Acceptance
All reachable 360-degree melee paths accept the synthetic one-ulp-past-PI bearing; a 359-degree and a normal partial arc still exclude the opposite bearing. Actual Wide Arc takes produce a capped full circle with unchanged damage/cadence rules. A negative control restoring round-1 logic fails the new precision case. Only arena.gd and its existing weapon tests change.
