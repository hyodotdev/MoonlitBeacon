PR #14, reviewed head c885995bb4ef2ad862880d9984ab0852cf603b0e against base c41d12077d12873999e6bf0d7c9f18f0ef9766ef.

Round 1: reread generator and verifier implementations, source/output containment, credential/cache exclusions, learner/reference/shipping identity separation, exact error/leak gates and real-scene close probes. Course regression tests 24/24. Independently ran reader --list (16 lessons), generated Lesson 16 in a fresh temp folder, reran into the nonempty folder and confirmed refusal with unchanged project bytes, and rejected lessons 0 and 17. All temporary outputs removed. No new confirmed defect.

Round 2: reread homepage, course overview, first-play copy, store/contact/privacy constants and measurement contract. Browser observed 131 full source links and no horizontal overflow on practice page, then verified first-play page exact UTM identity, install-before-first-open, separate observation consent, optional guest entry and mailto-only contact. Hosting regression tests 27/27 and growth state validation pass. Fresh production Lesson 16 import/compile/boot/checks/close/save run passes, real user data untouched. No new confirmed defect.

Two consecutive clean self-review rounds. Full pnpm verify and both-version 16/16 proof from prior accepted-tree review remain applicable; no source change was made in these PR rounds. Device exports and human first plays are outside the desktop proof and remain explicit course/recruitment steps. CI is separately checked for this exact head before merge.

## Merge and public verification

All four PR head CI jobs completed successfully. PR #14 was squash-merged
as 0b88971599b26c34f3bdb94272076b5a2d2d1568 on Oct 13 at 09:03:07 UTC.
Primary main was fast-forwarded, then hosting:build and hosting:check
passed on that merged tree. Firebase Hosting-only deploy exited 0 with
195 files, upload/finalization/release complete.

Public proof observed 2026-10-13T09:10:47.475Z: all 195 deployed files
returned HTTP 200 with SHA-256 identical to reviewed output, six clean
routes returned 200/no NUL, unknown route 404. All 131 full-source links
resolve on public main; 122 unique source bytes match. Browser confirmed
hero naturalWidth 1616, no horizontal overflow and Start the practice
path navigation to the page containing 131 source links.

Public origin: https://moonlitbeacon.hyo.dev/MoonlitBeacon
Primary ignored evidence: builds/verify/course-hosting-live-proof-20261013.json
and course-hosting-deploy-20261013.log. No native build, store submission,
telemetry activation, spend, direct outreach or human session was performed.
The first verified publication observation starts E04; it is not a claimed
upload instant or first visitor. Operational reconciliation follows in
brief 248.
