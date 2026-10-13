# Course practice foundation: director judgment

Date: 2026-10-13. Run: `course-followability-20261013`, first-eight checkpoint work.

## Independently executed

- `pnpm test:course`: 7 creation tests passed.
- `pnpm course:verify` with installed Godot 4.7.2: all eight generated
  checkpoints passed its import/boot/functional assertions.
- The same command with the official Godot 4.7.1 editor: all eight passed.
- Rendered Lesson 1 title and Lesson 8 arena with windowed Movie Maker;
  inspected the PNGs. These are course QA images, not store captures.
- The site source uses a base-aware hero image after the previous round.
  Earlier independent docs/hosting checks passed; final checks remain due.

Logs and images are local ignored output under
`builds/verify/course-20261013/`; no device/export evidence is inferred.

## Confirmed defects returned in Brief 241

The functional pass is not acceptance: the verifier currently suppresses
audio leak messages and does not reject errors when the engine exits 0.

- Lesson 1's original check accessed a nonexistent Label property and hung.
  A bounded director probe printed SCRIPT ERROR with exit 0. The implementer
  subsequently corrected the property access in this round.
- Rendered Lesson 8 arena quit with four leaked objects and two resources
  still in use, despite exit 0. Stop-only audio cleanup is insufficient.
- Fresh Lesson 3/8 imports set both music streams' loop flags false.
- The bottom-anchored charge ring has the wrong vertical offset sign.
- An external sibling symlink into a fake repository's apps directory
  bypassed the creation guard. No real source was written.
- A synthetic `.godot/export_credentials.cfg` in a fake layer was copied
  to generated output. No real credential was read or used.
- Existing real learner-save directories would be wrongly reported as
  newly touched by the verifier.

Brief 241 must close these while completing Lessons 9–16. Full script
compilation, strict engine output checks, final visual judgment, and both
engine versions are still required before accepting the change.

## Scope

Shipping game/native identity and store screenshots remain unchanged.
No site deployment, Git push/PR/merge, or real volunteer session has occurred.

## Additional director probe during round 4

A fresh current Lesson 12 output was launched in a normal current-scene context,
entered through the production title request, dashed, and restarted through the
production arena method. Official 4.7.2 exited 0 with no error or leak lines.
This did not reproduce a dash/restart coroutine defect. It is one checkpoint
and one transition, not an all-lesson or normal-close result. Evidence is kept
in the ignored verification log `dash-restart-lesson12.log`.
