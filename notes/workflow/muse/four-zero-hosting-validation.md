# 4.0.0 Hosting migration — director validation

Recorded 2026-10-04. Operational evidence is local under `builds/verify/`,
not a store-submission receipt. This note does not claim 4.0.0 has shipped.

## Domain and first public release

The requested public origin is `https://moonlitbeacon.hyo.dev`.
Vercel manages `hyo.dev` DNS. The Firebase-generated setup was applied to
that zone: `moonlitbeacon` CNAME points to `moonlitbeacon-778ee.web.app`,
and the dedicated ACME TXT verification record was added. Existing apex,
mail, wildcard and unrelated subdomain records were preserved.

Firebase readback confirmed host and ownership active. Certificate
propagation was observed, then ordinary HTTPS requests (without disabling
certificate validation or overriding DNS) returned the reviewed site.
The first hosting-only deploy succeeded on the existing default site.
No Firestore rules or native Firebase/Apple callback was changed.

At 2026-10-03 19:14 UTC, independent HTTP verification checked 18 routes:
root, English x-default privacy/support, five locale choosers, and ten
localized privacy/support pages. Every response was HTTP 200 and matched
the accepted static bytes exactly. CSS matched too; a missing route
returned HTTP 404. No NUL byte was found in the HTML.

Proofs:
- `release4-custom-domain-state.json`
- `release4-vercel-dns-cname-add.log`, `release4-vercel-dns-acme-add.log`
- `release4-player-care-first-deploy.log`
- `release4-player-care-live-proof.json`
- `release4-player-care-live.jpg`

The monorepo course/reference composition is a subsequent implementation
brief. Its final deployment must be independently verified; the first
release above contains only player-care.

## Player-care implementation review

Briefs 148–150 produced 53 accepted files: dependency-free five-language
privacy/support source and exact static output, hosting config and current
game/store contact links. Processor disclosures and native-session/data
retention details were checked against the owned published policy and game
source. The report alone was not counted as verification.

Independent site tests: 11/11; contact tests: 4/4; gate-locale tests: 5/5.
A Japanese processor link was deliberately replaced in the copy; tests 1
and 6 failed (9 pass, 2 fail, exit 1). Restoring the original bytes returned
11/11. Normal implementer quick-check judging passed (13 seconds, exit 0,
zero failure-looking lines). Root site/check tests passed after acceptance.

All ten policy/support pages were rendered at 390px width in Chrome.
Document scroll width equalled viewport width on every page; each support
table contained exactly ten products. The viewport override was reset.

## Android Google account recovery

On the attached Samsung device, the director observed the existing Google
account and Wave 1 save, signed out, then completed reauthentication via
the official Google native confirmation using keyboard navigation.
After the confirmation, the original public player ID and Wave 1 hero/save
returned. Account UI explicitly showed Google signed in. Resume loaded the
actual arena and rendered gameplay; the process being alive was not the
criterion. The game was left stopped at its level-up choice.

This test used the previously installed development build. Later accepted
changes touch capture evidence and website contact links, not provider or
save logic. Final native store-binary tests are still required before
claiming final release verification. This does not prove iPad Apple sign-in
or store purchase/restore transactions.

Proofs:
- `release4-galaxy-google-reauth-account.png`
- `release4-galaxy-google-resume-arena.png`

No credentials, Google email/profile, purchase token or private account
identifier are recorded in this note. The public ID is visible only in the
local screenshot proof and was not sent to the implementer.

## Combined care/course review

Brief 151 was independently judged and accepted, then committed as
`055a0eb`. The real combined build copied 37 care files and 142 docs files
(26 docs pages); its checker resolved 1,725 local links. All 20 hosting
regressions passed. The director disabled the symlink guard in the copy:
the suite exited 1, then the original bytes were restored and the suite
returned to 20/20. Nine scope boundaries, including root Firestore config,
the existing Pages workflow, the game project and Terms CSV, remained
byte-identical. Normal quick-check judging and root hosting/care checks
passed.

The director served the composed output and followed the visible course
link into Lesson 1. Images loaded, the canonical URL used the requested
custom origin, and the mobile page at 390px had no horizontal overflow.
This review is distinct from deploying the final combined site; Terms
publication and the final combined deploy are subsequent work.

## Integrated verification and capture restart

The root `pnpm verify` after briefs 146–150 passed, including the game/IAP
regressions, engine smoke check, asset generators, locale, repository rules
and the actual 26-page docs build/anchor check. The new hosting regression
suite was independently run after brief 151 acceptance.

The first final phone recapture built and installed successfully, then
failed its initial title-ready marker after 90 seconds. No new canonical
set was published. The producer restored existing persistent files.
Inspection confirmed the marker writer still looked for `Ui/Screen` on
`current_scene`, while production embeds that original title under
`Title`. Brief 153 repairs this specific readiness path and adds marker
coverage; the richer title capture-state bridge is already covered by its
218 scene checks. This failure is not a successful screenshot recapture.

The director also found the local release environment still resolving
`MOONLIT_PUBLIC_SITE_URL` to the former public host. Only that public URL
line in the private `.env` was changed to the requested origin; credential
lines and mode 600 were preserved. A new process loading the normal
release environment independently confirmed the custom Firebase origin.
The private environment file is not tracked or sent to the implementer.

## Terms review and actual combined-deploy findings

Brief 152 was read and independently judged. Site tests passed 15/15;
hosting tests passed 20/20. Every localized Terms page and English
x-default decoded to exactly the same eight CSV paragraphs in order. A
changed English source paragraph made the site suite exit 1; restoring
the exact original CSV bytes returned 15/15. All five Terms pages rendered
at 390px with eight paragraphs and no horizontal overflow. Existing
styles, game CSV/config, root Firestore and Pages workflow were unchanged.

The combined build contained 49 care plus 142 docs files (26 docs pages),
and checked 2,068 local links. Normal quick-check judging initially
failed because this fresh copy lacked imported translation resources;
the actual editor-import operation created those generated resources,
after which judging passed with zero failure-looking lines. Brief 152
was accepted and committed as `ee4984d`; the scoped app ignore also keeps
the generated Firebase cache out of Git.

The real combined deploy was then attempted with the documented command.
Firebase CLI refused `../../builds/hosting` as outside the config's project
directory before uploading. The care-only live release remained in place.
Brief 154 fixes the output location and adds that actual CLI boundary to
the config checker; no final combined live success is claimed here yet.

Brief 153 repaired the missing title-ready marker and was independently
verified: 45/45 marker cases, 218/218 rich title-state cases, and 64/64
clean-UI cases passed. Replacing production resolution with the old root
lookup made the marker suite fail, then an exact byte restore returned
45/45. Quick-check judging passed. The accepted root marker suite passed,
and the change was committed as `4418533`.

A subsequent full root verify caught a stale Node assertion still looking
for inline screen/version checks after the four-frame wait. Those checks
now live in the strict clean-title predicate before marker writing. This
is tracked as brief 155; the final whole-tree verification has not passed
yet, despite the related behavioral scene suites passing.

## Combined website published and verified

Brief 154 was independently read, tested, accepted and committed as
`1c8945b`: hosting regressions 21/21, care regressions 15/15, actual
combined build/check passed (49 care + 142 docs files, 26 docs pages,
2,068 local links). Disabling the in-project public-directory guard made
one regression fail; exact restoration returned 21/21. Scoped hygiene
passed. The composer itself did not use the checker during the separate
mutation probe; the actual final checker ran after restoration.

The director reran the documented hosting-only Firebase deploy from
`apps/player-care`. It completed upload, finalization and release (exit 0).
Ordinary HTTPS verification fetched all 191 deployed files: every response
was HTTP 200 and byte-identical to the inspected combined output. The 28
clean routes also matched, used the canonical custom origin and contained
no NUL. A missing route returned HTTP 404. Browser verification followed
the live care navigation into the rendered course/docs home.

Proofs: `release4-final-combined-hosting-deploy-retry.log`,
`release4-final-combined-hosting-live-proof.json`, and
`release4-final-firebase-site.jpg`. This proves website publication only;
it does not prove native store submission. Brief 157 records that actual
operation in the existing public-site handoff.

Brief 155 was accepted and committed as `d6e0a11` after independent
capture-state 40/40, Android build 130/130 and Play-package 232/232 tests.
Bypassing the live marker predicate made the capture-state suite fail;
exact restoration returned green. Root capture-state checks passed. This
repairs the stale source assertion without weakening the runtime proof.

The second final phone producer passed title boot, then failed the actual
direct-distribution boundary. The installed build reported its real
feature/cache/ledger checks correctly, but the remaining Ui lookup still
expected Title to be current_scene rather than ProductionEntry.Title.
Brief 156 repairs this confirmed embedding error; no canonical phone
screenshots were published by this failed attempt.

## Distribution probe accepted; final integrated pass in progress

Briefs 156/159 were independently judged and accepted through the normal
path. All new source and the 447-line real-scene test were read. The
copy's overlapping marker-source assertion edit was returned because
brief 155 had already supplied the independently verified stronger
assertion in the real tree; the corrected task omits that file.

The director performed a real import, then changed only the title
resolver to the old root lookup in the finished copy. The new behavior
suite exited 1; the probe bytes restored exactly to SHA-256
`91730bdd66f92428ef6fb20a271ce4992e3695efe67e8fdb0f1ce4f672c74fb7`.
Independent positive suites then passed: direct-distribution title 108,
boot marker 45, rich title forwarding 218 and clean UI 64. No engine
errors were present. Standard quick-check judging passed (12 seconds,
zero failure-looking lines). Code/registration committed as `2bd5d9d`,
its implementer-authored log as `850133b`.

The root whole-tree verification is now running in
`release4-final-integrated-verify-retry.log`. The first seventeen TAP
groups finished 645 tests with zero failures; game regressions remain
in progress at this entry. The separate store-capture check still rejects
missing current canonical proof (`release4-post156-store-capture-check.log`).
No successful final capture or native store submission is inferred from
these intermediate results.

The verified Hosting record was accepted after correcting the initial
report's operation chronology and limiting its native-release statement
to version 4.0.0 (`1945442`). `AGENTS.md` now identifies the requested
Firebase origin as primary and the unchanged Pages workflow as its mirror.
The remaining owned Desktop test screenshot was moved to recoverable Trash.

## Final stock verification and Android captures passed

The unmodified root `pnpm verify` completed successfully after the accepted
production-title probe correction: 652 Node tests in 19 groups, all 76
registered Godot checks, 165 compiled GDScripts, five locales, ten product
rows, deterministic graphics/assets, hygiene/skills, and the 26-page docs
build with clean anchors. No engine failure lines remained. The measured
headless peak of 1196 nodes is a headless budget result, not native FPS.
Local proof is `builds/verify/release4-final-integrated-summary.json`.

Changed 4.0.0 art/layout justified the previously requested recapture. The
final phone producer published 30 marketing and ten product-review native
PNGs; separate fresh builds published 30 seven-inch and 30 ten-inch native
PNGs. The director decoded every PNG, checked dimensions and report hashes,
viewed every five-locale six-screen board and all product images, and ran
the unchanged strict validators against all three canonical reports. The
combined result is phone 40, seven-inch 30 and ten-inch 30, all current at
runtime SHA-256 `ae1865d0031d1b89892991cf1153cd940ca396bd0df567c50ef110ea22031683`.
Each producer proved byte-exact static and dynamic-account save restoration;
APK/build/signature/source evidence was independently validated. A first
phone validation raced an active Gradle directory cleanup; rerunning only
after the build ended passed without changing the validator. Android
screenshots do not establish purchases, physical Pixel coverage, or iPad
rendering. Owned emulator processes were closed after capture.

The final Android 4.0.0 (17) signed AAB and direct-distribution APK build
commands have succeeded. iPad capture and Play artwork generation are now
running; their completion, store uploads, final native purchase checks,
remote merge and review submission are not claimed at this entry.

## Final public policy and Play declaration pass (2026-10-04)

Firebase custom-domain readback reached HOST_ACTIVE, OWNERSHIP_ACTIVE and
CERT_ACTIVE. All 90 Play marketing images were generated, checked,
synchronized and committed; the director viewed all 15 final locale/device
contact boards. The final AAB was rebuilt after the iPad capture's initial
export restored the preset file and advanced its timestamp; the normal
package check now passes for 4.0.0 (17), five listings and 90 images.

Brief 160 added a source-backed privacy inventory. The director read the
entire document, checked the auth dependencies, automatic guest/cloud/Hall
paths and deletion sequence, and ran hygiene in the copy and real tree.
Its proposals are audit inputs, not proof of a store submission. The
director's actual Play choices add Account management to the three personal
information purposes; the official Firebase disclosure explicitly includes
authentication and account management. Already-held Apple service-key and
deployed-rule evidence is separate from the copy's unresolved inventory.

The audit found a real mismatch: the published policy said every local save
remained, but successful deletion removes that account's journey slot and
UID binding. Brief 161 corrected exactly one privacy bullet per locale.
The director inspected all five changes against production source and ran
15 player-care tests, 21 hosting tests, custom-origin build/check and
hygiene. Tests temporarily changed generated files in the copy; the
director restored only those operation-generated files to its baseline
before the normal five-file accept. The initial parallel content check
observed test fixture output; a sequential rebuild/check passed. The real
build regenerated the 12 committed privacy HTML variants normally.

Firebase redeployment succeeded. Independent live proof found all 191
files byte-identical to the build, 15 clean legal/support routes with the
custom canonical origin and no NULs, and a true 404 for an absent route.
Terms and game/runtime source were unchanged by this correction.

Play Data safety changes were saved and show Ready to send for review:
OAuth and anonymous guest account creation; name/email optional, user IDs
and checkpoint/Hall actions required; no third-party sharing under the
service-provider exception; purchase history and purchase diagnostics kept
at their prior optional purposes. Both deletion links use the custom
privacy route. The newly issued domain initially triggered Play's URL
finder warning, but the next check advanced after ordinary HTTPS and DNS
were independently verified. The old privacy-policy URL is being replaced
separately. No production review submission is claimed.

The first internal-track apply failed with HTTP 503 during the image reset,
before commit; the normal client attempts to discard an uncommitted edit.
A fresh local ready check preceded the normal retry. Its result is still
pending at this entry. Native purchase verification, final iPad capture,
App Store upload, PR, CI, merge and final review remain separate gates.

## Follow-up classification and live internal-track proof

Briefs 162/163 corrected only the source audit: Apple Product Interaction
includes the functional saved game place as well as any analytics; the
analytics-disabled finding cannot remove the cloud-checkpoint label.
Gameplay Content stays declared. Account Management complements App
functionality for Play's account identifiers/profile fields. Independent
source reads and Apple primary definitions confirmed this classification;
the existing hygiene check passed in the copy and real tree. The corrected
audit keeps unfinished native testing and final review explicit.

Play's normal apply retry committed internal 4.0.0 (17), five listings and
90 screenshots. The read-only API audit and visible Console both confirmed
artifact 17 available to internal testers. Production is still 3.0.0 (16).
The first apply hit HTTP 503 before commit and was discarded; no duplicate
version was published. The device still uses a sideloaded debug package,
so installer and real purchases remain unverified.

Play Data safety and privacy URL edits are saved for review. Apple privacy
URLs were saved in five locales; new account/cloud-save types are still
being prepared. No final review or main merge is claimed.

The first full iPad attempt completed 21 shots, then timed out on the
22nd handoff during context recovery. Mandatory cleanup restored the
keychain search list and removed the isolated capture app; production
app data remained untouched. Its failure/evidence is preserved. A normal
fresh full retry is running; partial shots are not labelled canonical.
