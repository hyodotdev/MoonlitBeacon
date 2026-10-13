# Brief 238: audit and repair the course entry path

## The ask
"강좌도 현재 스텝별로 따라하면 바로 익히고 겜도 만들수 있는 구조인지 잘 확인해봐"

Determine whether a novice can follow all sixteen lessons in sequence and make a runnable game. Repair confirmed entry-level blockers and report the remaining gaps honestly.

## Why, and what good feels like
The learner should know where to start, which project they are editing, which commands exist there, and what each code excerpt omits. A list of concepts and successful website builds do not prove a complete blank-project walkthrough.

## Where things stand
- All sixteen lessons have concept, implementation, verification and exercise sections. No lesson/checkpoint tags exist; the available `release-2.1.0` reference is already a later survivor, not the Lesson 16 dodge game.
- `chapter-01.mdx` asks for a new project under apps/game, calls repository pnpm scripts without explaining Node/pnpm/clone setup, and section 5 only lists title layers. Lesson 2 assumes a detailed 1296-node title scene which section 5 never constructs.
- Lesson 5 excerpts use undeclared `_sprite`, `_walking`, `facing` and leave setup to inference. Lesson 6's left-half Control sets offset_right=404 with anchor_right missing, yet says it remains half-width on wide screens. Confirm and repair that specific contradiction.
- `docs/assets/download-guide.md` says ignored original packs are already downloaded, although a public clone never includes them. Selected game assets are tracked.
- Current main game is 4.0.1, while lessons describe a 90-second beginner dodge game. Some Lesson 15/16 warnings exist but the top-level promise still implies current-main equivalence.
- The director has read Lessons 1-6 and the headers/checklists of 7-16. Audit the actual body of EVERY lesson yourself; these findings are starting points, not the entire review.

## Do
- Produce an evidence-based audit of all 16 lessons: entry prerequisite, changed files/nodes, missing definitions/wiring/assets, exit checkpoint, exact source line evidence and severity. Classify self-contained versus excerpt/reference-dependent. Do not invent intermediate snapshots.
- Repair confirmed setup and reference confusion in course/intro, reference intro, asset guide, and Lesson 1: exact safe clone/install/editor route, separate blank learner folder versus existing complete game, current game versus historical course scope, no overwrite of an existing clone project, engine/download links suitable for all OSes. Teach what helps the learner; keep audit/production notes outside published prose.
- In Lesson 1, add concrete editor steps and values for a minimal usable title scene, including exact tracked asset paths, layout/anchors, main scene, title/prompt and animation controls. Clearly distinguish this from the advanced historical forest scene assumed by Lesson 2; do not claim to have rebuilt a missing historical checkpoint or fulfilled every later dependency by merely running main.
- Fix the verified Lesson 6 anchor contradiction and other small confirmed instruction defects you find. Mark code excerpts as excerpts and give missing declarations/wiring or point to verified matching full source where available. Do not link current 4.0 code as if it exactly matched historical snippets.
- Provide an ordered backlog for remaining substantive missing implementation steps. Preserve the useful concepts, clips and English language. Do not weaken the lesson goals to declare success.

## Do not
- No game/asset/store/version/auth/analytics changes, no captures, no network, no git operations or deployment. No large fictional rewrite, no fake first-play participants or run/phone verification.
- Do not claim all 16 are reproducible from scratch unless complete evidence exists. No new telemetry, tracking pixels, forms or participant PII in public sources.

## Acceptance
- All sixteen lessons individually covered with source evidence in `notes/course/followability-audit-20261013.md`, retaining original goals and identifying unresolved blockers.
- A fresh reader has a precise prerequisites/clone/install/run route and cannot mistake a blank learner project for the complete shipping project. Every new local link and asset path exists.
- Title scene instructions can be followed in a separate blank project; the director will reproduce them. Lesson 6 uses a genuinely half-width anchored Control.
- English public prose; pnpm docs:build, check:docs, check:skills, check:hygiene, git diff --check must pass. Report any check you could not execute rather than guessing.

## Deliverables
The audit in notes/course/, targeted edits to the named course/reference pages and any other small confirmed instructional corrections. An implementer report listing the remaining gap count by severity and which steps were actually checked.

## Settle these yourself
Use the simplest existing tracked CC0 artwork and font for the entry example. Full snapshots for all lessons are a separate larger task; identify their absence and required work precisely instead of synthesizing an unverified claim.

## How the director will judge
Read every changed hunk, spot-check audit citations against all sixteen source pages, reproduce the new title steps with Godot in a throwaway internal-disk learner project, run docs/link/hygiene checks, inspect browser rendering, and preserve the primary clean main.
