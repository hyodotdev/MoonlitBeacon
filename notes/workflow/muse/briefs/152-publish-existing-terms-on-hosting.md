# Brief 152: Publish the existing in-game Terms with player-care

## The ask
"저기 firebase hosting을 moonlitbeacon.hyo.dev 로 hosting으로 연결해서 관련된 사이트는 chatgpt 호스팅이 아니라 저기에 다 올려서 관리해줘. 모노레포로 관리하면 되려나 개인정보 등등 모두."
Make the existing Terms available on the same owned public site, without drafting a new agreement or changing the in-game Terms.

## Where things stand
The accepted player-care site has privacy/support in five languages. The game already shows gate.terms.title and gate.terms.p1 through p8 from apps/game/localization/gate_entry.csv in its local modal. The combined Hosting composer checks care output plus course/docs under /MoonlitBeacon/. Root Firebase config is Firestore-only and must remain unchanged.

## Do
- Add /terms (English x-default) and /{en,ko,ja,zh-Hans,zh-Hant}/terms with the SAME eight paragraphs, in order, as the game's CSV locale cells. Read the CSV at build time using the existing CSV parser; escape its text, do not duplicate or edit the agreement in site content files. Labels/title may be localized, body must equal the in-game source after decoding HTML text.
- Link Terms alongside Privacy/Support in localized site navigation, chooser and footer as appropriate. Keep existing privacy/support facts and actual links intact, including processor policies and course/reference navigation.
- Rebuild committed care output; update exact route/output counts in tests and checkers; register meaningful source-parity tests for all five locales and one changed/missing paragraph negative case. Combined hosting integrity must still verify all care files and all real docs pages/assets.
- Keep the game CSV, game settings/logic and native callbacks byte-identical. Do not add an acceptance checkbox/form, new legal promises, external policy, tracking or credentials.
- If the Hosting config's deploy creates a .firebase cache in this app, add an appropriate scoped ignore for it so repeat deploys never dirty Git. The director observed exactly apps/player-care/.firebase/hosting.ZGlzdA.cache after the first authorized deploy; it contains only generated hosting file hashes and is already removed from commits.
- Update the README and publication note with the Terms source and routes, and the exact final combined deploy/check procedure. Report publication status as director-operated, not implemented evidence. Correct stale claims of zero prior Hosting releases: the director has now deployed the inspected privacy/support care-only release successfully and verified all 18 routes over ordinary HTTPS; the final combined docs/Terms release remains director-operated and pending. The implementer must not claim its copy deployed anything. Add the existing Terms URL to the Docusaurus public nav/footer alongside privacy/support if helpful.

## Acceptance
- All six Terms routes render the exact existing eight paragraphs for the correct locale, including punctuation and ordering. No change to the game's agreement.
- The normal player-care checker, site tests, hosting checker/tests and real combined build pass; missing/changed Terms source fails the relevant test before restoring exact bytes.
- Site mobile layout wraps 5-language nav; local links and actual missing-page 404 behavior remain valid.
- Game/native/root Firestore/workflow bytes unchanged; hosting cache and combined output are ignored; no secret files, new dependencies or author notes in public output.

## Deliverables
Only apps/player-care source/tests/dist/config/doc changes needed for Terms publication, scoped .gitignore entry if needed, and current publication handoff. No external operations.

## How the director will judge
Read the full diff, compare every Terms paragraph to CSV independently, run focused tests/checks, break a paragraph in the copy to see the test fail and restore, inspect rendered mobile/desktop Terms and site navigation, then deploy the accepted complete Hosting site and verify real URLs.
