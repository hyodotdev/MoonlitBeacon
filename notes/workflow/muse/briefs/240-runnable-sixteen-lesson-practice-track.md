# Brief 240: build the runnable practice foundation (Lessons 1-8)

## The ask
"강좌도 현재 스텝별로 따라하면 바로 익히고 겜도 만들수 있는 구조인지 잘 확인해봐"
"강좌를 보고 godot을 마스트하자 이런느낌으로도 잘 만들어줘. 현재 godot 4.7.2인데 최소 지원 버전 같은거 그리고 latest까지 잘 된다고도 잘 얘기하고"

## Why / where things stand
Continue Briefs 238/239 in this copy. The audit found no matching beginner checkpoints and missing complete source. Marketing changes alone do not make the course followable. This task builds the first half of a complete practice path; a subsequent brief completes Lessons 9-16 before publication. Both editors compile 174 shipping scripts and open its title, but practice execution is still unverified. No shipping game changes are authorized here.

## Do
- Author a small educational project source under examples/course/, outside apps/game, with complete end states for Lessons 1-8. Reuse only an explicit small selection of tracked art/audio and a real licensed font; retain licenses and a reuse manifest. No native plugins/secrets/ignored original packs, gray placeholders or default font.
- Add a deterministic Node creation command from a fresh clone: chosen lesson -> complete standalone project in builds/course or a NEW/empty custom folder. Refuse destructive/existing learner work, source folders, path traversal or symlink escape. Copy only necessary selected assets, never all packs/cache. Shared sources are fine; each output contains only its introduced dependencies, with readable changes from the preceding lesson instead of one runtime lesson-number flag.
- Match the goals: 1 attractive title/blinking prompt; 2 separate forest/beacon scenes; 3 three instances/title transition; 4 state setters/signals with sequential ignition; 5 four-direction idle player; 6 floating movement/stop/facing/bounds; 7 proximity charge/ignition; 8 chase/contact/hit feedback. Full-file source and exact node paths must exist. Use a beginner app/user-data identity separate from installed Moonlit Beacon.
- Add a practice guide with exact setup, file changes and editor steps for each completed lesson, one independent modification exercise and an observable success criterion. Link from course overview and those lessons. Reference checkpoints are for comparing; learners edit their own project and never overwrite their work unknowingly. Explain differences from historical clips. Mark 9-16 pending until the next task, without weakening goals.
- Add meaningful creation/import/compile/boot and progression tests, including half-width input at wide viewports, release/facing stability, beacon signals and enemy layer separation. Tests use isolated user data and cannot touch installed-game saves. Register commands/help and useful tests. No tracked ZIPs (hygiene bans them).
- Correct collision terminology: mask value 2 is inspector checkbox 2, value 4 is checkbox 3. Remove the audit's false shipping joystick finding: arena.tscn lines126-131 override MoveStick to full-screen (anchor_right=1, offset_right=0). The historical default lesson snippet was wrong; no native fix follows.

## Do not
No apps/game, store, release, auth/analytics, Firebase services/rules, protected instructions or engine-lock changes. No phone/export/capture claims or invented history. No network/install/git operations. Future editor versions get no untested compatibility claim.

## Acceptance / deliverables
All eight checkpoints have complete executable source, explicit learn/edit/verify/apply steps and can be created from a fresh clone without secret assets/cache. Relevant tests and docs/hosting/skills/hygiene/diff checks pass (director runs anything unavailable). Source/outputs stay bounded with no redundant binary copies in Git. Report actual checks and gaps. The director creates all projects, runs both 4.7.1 and 4.7.2 independently, inspects title/movement pictures and judges all code/prose before the next task.
