# Brief 005: Release record for 3.0.0

## The ask

The user: "3.0.0 최종 릴리즈 상태로 잘 작업해줘 끝까지". The release needs its written record: what it is, what was checked,
what is left, in the same form the 2.1.0 release left.

## Why, and what "good" feels like

Someone opening `notes/release/checklist.md` in a month must see, without reading the game code, what 3.0.0 is, what
was verified and how, what was deliberately left undone, and what only the user can do next. It must be short, true,
and follow the tables the earlier records already use.

## Where things stand

- `notes/release/checklist.md` has a version table at the top (2.1.0, iOS build 9, Android versionCode 14) and dated
  records: "1.0.2 submit record", "1.0.2 resubmit prep record", "2.1.0 submit prep record (2026-08-26)", "2.1.0 store
  reflection (2026-09-04 console)". Their form is a two-column table of facts.
- `notes/plans/release-2.1.0.md` is the plan and record of the previous release; use it as the model for a 3.0.0 one.
- `notes/plans/3-0-0-build-log.md` and `3-0-0-expedition.md` say what was built, measured and left undone.
- Locked values for this release: app 3.0.0, Android versionCode 15, iOS build 10. Both stores have 2.1.0 live.
- Facts you may state, because the director measured or set them: `pnpm test:game` passed on the working tree on
  2026-09-30; `check:assets`, `check:store-metadata`, `check:hygiene` and `check:skills` passed; `check:store-graphics`
  and `check:store-screenshots` are red on purpose until the store images are recaptured. Anything else you need, read
  from the repo or leave as "not yet run".
- The analytics gate of 2.1.0 (collection off in the submission build until the protected ingest path, privacy labels,
  Firestore rules deploy and release `firebase.cfg` are done) is unchanged; `firestore.rules` is modified in the working
  tree and not deployed, which is the user's step.

## Do

1. In `checklist.md`, change the version table to 3.0.0 (iOS build 10, Android versionCode 15) and add a "3.0.0 prep
   record (2026-09-30)" section in the same two-column form: source version; what changed since 2.1.0 (six lines at
   most, in player terms); checks run and their results; store images (recapture planned after the game freeze, nothing
   uploaded); release gates that remain (the analytics gate as above, store console steps, the iPad capture needing a
   sudo RSD tunnel started by the user); what is deliberately not done. Do not edit the older records.
2. Add `notes/plans/release-3.0.0.md` modeled on `release-2.1.0.md`: goal, scope, what changed, budgets and how they
   were measured, verification, known limitations (quote them from the build log's "Not done" lists, corrected: the
   first-fork hint exists), and the steps between here and a store submission, each marked as the user's or the
   director's.
3. Do not state a result you were not given or cannot read from the repo. Mark it "not yet run".
4. `pnpm check:hygiene` passes (no banned word), and links in what you write resolve.

## Do not

- Do not touch `apps/`, `stores/`, `scripts/`, the older records, the store copy, or `notes/plans/3-0-0-*.md`.
- Do not write dates or statuses of submissions, reviews or tags that have not happened.

## Acceptance

1. `pnpm check:hygiene` passes; the new file and the new section exist and follow the earlier form.
2. Every fact in the new record is either from the list above, quoted from the repo, or marked "not yet run".
3. The diff touches only `notes/release/checklist.md` and `notes/plans/release-3.0.0.md`.

## Deliverables

`notes/release/checklist.md`, `notes/plans/release-3.0.0.md`, `IMPLEMENTER_REPORT.md`.

## Settle these yourself

- Section order inside the new record (default: the order of the 2.1.0 records).
- How to word a step that needs both roles (default: name the owner in brackets).

## How the director will judge

The director reads the record against the repo and the numbers above, and checks that nothing states an unverified
result.
