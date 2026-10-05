# Brief 157: Record the verified combined Hosting release

## The ask
“저기 firebase hosting을 moonlitbeacon.hyo.dev 로 hosting으로 연결해서 관련된 사이트는 chatgpt 호스팅이 아니라 저기에 다 올려서 관리해줘. 모노레포로 관리하면 되려나 개인정보 등등 모두.”

Record the now completed website operation accurately in its existing handoff.

## Where things stand
Brief 154 moved generated output to apps/player-care/hosting-dist and was accepted. The director independently built and checked 49 care + 142 docs files, 26 docs pages and 2,068 local links; hosting tests 21/21, care tests 15/15. Disabling the new project-directory boundary caused one test failure; exact restoration returned green.
The director then ran the exact README hosting-only deploy command in apps/player-care. Firebase CLI reported 191 files, upload complete, version finalized, release complete and Deploy complete (exit 0). Independently fetched every one of the 191 files over ordinary HTTPS at https://moonlitbeacon.hyo.dev and compared its bytes to the reviewed generated output: all HTTP 200 and all identical. Also checked 28 clean routes (root, x-default and five-language care pages, docs home/course/Lesson 1/reference): HTTP 200, exact bytes, canonical custom origin, no NUL. Missing route HTTP 404. Browser followed the live course link and showed the docs home. Source code and static files are in this monorepo.
Local operational evidence is under builds/verify/: release4-final-combined-hosting-deploy-retry.log, release4-final-combined-hosting-live-proof.json, release4-final-firebase-site.jpg. These files are not provided to the copy, so the numbers above are director-supplied verified facts, not your independent measurements.
Current README and notes/release/player-care-publication.md still say final combined release pending, correctly describing the state before the actual successful operation.

## Do
- Update only these two existing documents to distinguish the earlier failed outside-directory attempt, the care-only first release, and the subsequent successful combined 191-file release. Preserve the useful history in a short form.
- Record the exact ordinary-HTTPS verification counts and local proof filenames. Attribute those observations to the director; do not claim you deployed or independently ran remote tests.
- Keep exact build/check/deploy commands, output path, 5 languages, unchanged Terms-source parity and ongoing monorepo management description.
- Explicitly distinguish website publication from native 4.0.0 store submissions. Do not claim the game release is submitted, approved or live.

## Do not
No code, generated HTML, game, assets, versions, auth callback, Firebase config/rules, DNS, stores, scripts, skills or workflows. No network/deploy. No model names, credentials or personal identifiers.

## Acceptance and deliverables
Only apps/player-care/README.md and notes/release/player-care-publication.md change. No stale final-website-pending claims remain. Commands still match current config. Hygiene passes. Read both changed hunks in context; no new tests needed for this small documentation correction.
