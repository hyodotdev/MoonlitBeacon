# Brief 004: Store text for 3.0.0

## The ask

The user: "3.0.0 최종 릴리즈 상태로 잘 작업해줘 끝까지" and, about the stores: do not upload anything yet, but have everything
that the update changes ready. This brief is the text half (the screenshots are the director's, later).

## Why, and what "good" feels like

When 3.0.0 is submitted, a player reads "What's new" and the store description before anything else. They must be true
to the game, in the voice the existing copy already has, in all five languages, inside every store's limits, and pass
`pnpm check:store-metadata`. Nothing is uploaded: this is repository text only.

## Where things stand

- Copy lives in `notes/release/store-page.md` (base metadata, short blurb, five full descriptions, the Screenshots
  section, Google Play release notes per language, itch.io file info) and `notes/release/store-localizations.csv`
  (short fields per store and locale: names, short description, subtitle, promotional text, keywords; IAP rows).
  `scripts/check-store-metadata.mjs` checks lengths, locales, product coverage and that the public copy matches the CSV.
- The release notes today describe 2.1.0 (Safe Kindle / Overcharge, Resonance, cash out or continue). Version rows and
  the itch.io file line say 2.1.0.
- What 3.0.0 is (from `apps/docs/docs/game.md`, `notes/plans/3-0-0-build-log.md` and `3-0-0-expedition.md`; read them,
  and read the code before you claim anything): a new UI kit and lighting; redrawn heroes, spirits and guardians; a
  structured story (four acts, a chronicle, per-hero voice); six places with forks (from the second cycle you choose
  between two gates, each showing its place and its omen); an endless stretch past the map's end that keeps changing
  (depth, omens, guardians that grow mutations); nine new skills that unlock as cycles pass; guardians and spirits that
  fill the air with slow bullets to weave through. The bullets are being finished right now: mention them only as
  "weave through", and do not give numbers.
- Limits: Google Play name 30, short description 80, full description 4,000, release notes 500 per language; App Store
  name 30, subtitle 30, promotional text 170, description 4,000, keywords 100 bytes, "What's New" 4,000. The checker
  has the authoritative numbers.
- IAP products, prices and review notes are not part of this update.

## Do

1. Write the 3.0.0 release notes for Google Play (`en-US`, `ko-KR`, `ja-JP`, `zh-CN`, `zh-TW`) under 500 characters each,
   a short list in the same style as the existing ones, led by what a player notices first. Write the App Store "What's
   New" the same way if the page has a place for it; if it has none, add one next to the Google Play notes following the
   page's own structure.
2. Update the full descriptions and the CSV short fields where a claim is now wrong or where 3.0.0 makes the pitch
   stronger (places, forks, the endless stretch, skills, guardians that fight back). Keep what is still true, keep each
   language's voice, and do not turn a description into a feature list. Every claim must be checkable in the game.
3. Version rows and the itch.io file line (`MoonlitBeacon-3.0.0.apk`) say 3.0.0.
4. The Screenshots section lists the six store screens by name and caption. Keep the six names
   (`01-moonlight-barrage` to `06-hero-preview`); rewrite the captions only if they no longer describe what the
   screens will show (the director decides the shots and will send a correction if they change).
5. `pnpm check:store-metadata` passes. Run `node --test scripts/lib/store-metadata.test.mjs` too.

## Do not

- Do not touch anything under `stores/`, the IAP rows, prices, the seller values, review notes, or `iap-store-setup.md`.
- Do not claim a feature the game lacks, a review status, a price or a date. No superlatives you cannot show.
- Do not change the app names or the one-line pitches unless a claim in them became false.

## Acceptance

1. `pnpm check:store-metadata` passes and the store-metadata tests pass.
2. Every language has release notes within 500 characters, and every feature sentence in any language maps to a
   sentence in the English one (the report gives the mapping for the release notes).
3. The report lists each claim that is new or changed and where in the game or the docs it can be checked.
4. `grep -n "2\.1\.0"` in the two files shows only historical records, not the current version.
5. `pnpm check:hygiene` passes (no banned word, no stray model name).

## Deliverables

`notes/release/store-page.md`, `notes/release/store-localizations.csv`, `IMPLEMENTER_REPORT.md`.

## Settle these yourself

- How many bullet points the release notes use (default: four or five, shortest first claim leading).
- Whether to mention the new heroes' art (default: yes, as "redrawn", because the store images change too).

## How the director will judge

The director runs the two checks, reads all five release notes (with a native-reading pass on ko and ja), and checks
each new claim against the game.
