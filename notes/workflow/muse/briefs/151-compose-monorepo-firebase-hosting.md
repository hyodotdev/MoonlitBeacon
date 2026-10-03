# Brief 151: Compose the monorepo public Firebase Hosting site

## The ask
"저기 firebase hosting을 moonlitbeacon.hyo.dev 로 hosting으로 연결해서 관련된 사이트는 chatgpt 호스팅이 아니라 저기에 다 올려서 관리해줘. 모노레포로 관리하면 되려나 개인정보 등등 모두. vercel에 url연결도 너가 해줄 수 있나"
"vercel도 로그인해놨어 너가 hosting moonlitbeacon.hyo.dev로 연결해줘"

One production task: assemble the existing player-care site and Docusaurus course/reference into one inspectable Firebase Hosting deployment from this monorepo.

## Why, and what good feels like
Players find privacy/support in their language; students find the existing course and reference through the same public domain. One build/deploy procedure manages the complete site without replacing player-care pages with the course or leaking author notes. Domain/DNS and credentials are operated by the director, never this implementation.

## Where things stand
- The new apps/player-care contains a dependency-free generator, five content locales, 37 committed exact dist files, 18 routes, and 11 passing regressions. Its canonical origin and the game's two contact settings are https://moonlitbeacon.hyo.dev.
- apps/docs is the existing Docusaurus site with 26 generated pages. Current config url is GitHub Pages, baseUrl /MoonlitBeacon/, trailingSlash false. Keep the base path unchanged so the existing GitHub Pages mirror and links remain usable.
- .github/workflows/deploy-docs.yml automatically publishes the legacy mirror on main. Do not disable it or change its permissions/credentials.
- Root firebase.json deploys Firestore only. Do not edit it. apps/player-care/firebase.json targets the existing default hosting site moonlitbeacon-778ee and currently public dist.
- The director has already configured the requested Vercel DNS CNAME and Firebase custom domain. TLS now validates over the custom origin; site files have not yet been deployed. No deploy or external mutation is yours to perform.
- A confirmed small Korean typo in content/ko.mjs reads "부정·증복 방지"; fix to "부정·중복 방지" while generating the new navigation. Do not rewrite the privacy facts.

## Do
- Make Docusaurus canonical url the requested custom origin while keeping /MoonlitBeacon/ base path. Add appropriate clear links between course/reference and player care using actual routes, with five localized player-care nav labels. Do not put production directions in student prose.
- Implement a deterministic combined public directory: all inspected player-care files at root; all existing Docusaurus build files under MoonlitBeacon/. Build fresh both inputs before composition. Keep generated combined output gitignored and the committed player-care exact dist checker intact.
- Add build/check/hosting-only deploy entrypoints, scoped explicitly to the existing Firebase project/site and app-local config. The deploy operation must build/check before invoking firebase, use --only hosting, and never deploy Firestore or change auth callbacks. Use the existing authenticated CLI; no tokens, new dependencies, credentials, IAM or new remote sites. A director-only documented raw command is acceptable if a safe wrapper would overcomplicate this.
- Check exact composition against both inputs, route/asset/link health including extensionless Docusaurus routes, absence of NUL HTML, no author notes/secrets/symlinks, real missing-page 404 (no SPA catch-all). Fail on missing/stale docs assets or a changed care page. Bound destructive cleanup to this generated output, reject unsafe paths/symlinks rather than delete arbitrary directories.
- Register focused meaningful regressions for composition, missing asset/stale source/missing course route, and unsafe input/output boundaries. Update the current README/publication handoff and package verification registration. Do not invent deploy success or live release evidence.

## Do not
- Do not change game logic, art, version/build numbers, Terms, native auth settings/callback, IAP, store metadata beyond current contact documentation, old release evidence, Firestore rules, AGENTS, .claude/.agents, muse configuration, or PR guards.
- Do not deploy, call the network, use credentials, push/merge, or add analytics, scripts to the player-care pages, new frameworks, remote fonts, forms, or a broad SPA rewrite.
- Do not modify course content gratuitously, remove the Pages mirror, or copy notes/ into public output.

## Acceptance
- Existing 11 player-care regressions and exact committed dist check still pass (route/navigation additions may alter exact outputs only by rebuilding).
- Combined hosting build succeeds with the real Docusaurus build (not fixture-only); exact checker verifies all 26 docs pages and all 37 care files plus assets and resolves their local href/src links without disguising missing URLs.
- New regression suite proves omission of a referenced asset and corruption of a care output fail; wrong output locations and symlinks are rejected without deleting unrelated content. Director independently breaks one boundary and restores bytes.
- Config selects hosting site moonlitbeacon-778ee only and generated combined directory; original Firestore config and deploy-docs workflow are byte-identical.
- Existing repo hygiene, locale, docs build/anchor checks pass. No new secrets, NULs, author notes or personal device data in deliverables.
- Browser can render root, Korean privacy/support, docs home, course guide and Lesson 1 through one local server with all assets loaded.

## Deliverables
- apps/player-care hosting composition/check scripts and their registered tests, hosting config, README, content/nav/generated dist where needed.
- apps/docs/docusaurus.config.ts canonical origin and appropriate care navigation only.
- package.json scripts/verification registration, .gitignore for combined generated output, notes/release/player-care-publication.md current handoff.

## Settle these yourself
Keep /MoonlitBeacon/ as the docs path. Prefer short root scripts hosting:build, hosting:check, test:hosting and a documented hosting-only deploy command. Use node fs and existing tools only. No timestamps in generated HTML, no blanket link checker exemptions. Publish only generated outputs from the two existing apps.

## How the director will judge
Read the full diff and new source/tests, run the new tests and existing site tests, build actual Docusaurus and the combined directory, perform a deliberate missing-asset failure, inspect source byte parity and browser render at desktop/mobile widths, then deploy and verify live TLS/HTTP externally after acceptance.
