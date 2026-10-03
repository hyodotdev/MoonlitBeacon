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
