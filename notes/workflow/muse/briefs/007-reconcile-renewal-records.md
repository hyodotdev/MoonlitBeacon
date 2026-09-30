# Brief 007: Release copy and records describe the playable road home

## The ask

The user asked to continue the 3.0.0 renewal, make the world immersive through story and playable discoveries,
review until stable, and prepare a merge-ready PR without merging. This task reconciles the release copy and
author records after the game rounds have been judged. It does not submit or publish anything.

## Where things stand

Read the actual current game, locale CSV, story bible and the accepted changes in the build log. The implemented
game is authoritative. Separate rounds renewed the bullet balance, result depth/English Wave wording/shop layout,
and the Lantern Hollow / Nari story with place restorations. Current main's IAP 3.6.1 / Shop update is integrated.
The existing 3.0.0 store text and release record were prepared before the stronger narrative, so they need a final
pass. No store screenshot recapture, upload, analytics deployment, store submission or release tag has occurred.

## Do

1. In all five full descriptions in `notes/release/store-page.md`, lead with the concrete personal hook and
   playable discovery: Nari's missing signal, the road home and the memories restored with beacons. Describe only
   the accepted game. Keep the six terrains/forks, skills, readable bullets and optional Depth accurate; use Wave
   consistently in English. Rewrite the story paragraph and release notes / What's New to match. Do not claim
   all missing people return after an early beacon, or that every terrain must be visited to finish.
2. Keep existing IAP products, prices, support/privacy links, screenshot files and screenshot captions intact.
   App/promotional CSV fields may be synchronized to the new hook where it improves them, without touching IAP
   rows. Preserve required store field topology. Target English full description at most 3800 characters for
   headroom, all descriptions below the actual 4000 limit and Google Play release notes below 500 characters.
   Remove repetitive decoration before removing useful controls, purchase or offline behavior information.
3. Keep the placeholder-rejection test meaningful if the opening sentence it uses changes: update its required
   anchor (or a robust fixture insertion point), never remove the negative case. Run store metadata checks and
   the complete related Node tests yourself.
4. Reconcile `notes/plans/release-3.0.0.md`, the 3.0.0 preparation section of `notes/release/checklist.md`,
   `notes/plans/3-0-0-build-log.md` and `notes/plans/3-0-0-expedition.md` with accepted behavior. Remove current
   assertions that first-fork hint, result Depth or new story are unfinished. Preserve historical measurements
   as dated comparison, not current evidence. Never silently rewrite old measurement values.
5. Correct the new bullet log's claim that the bot dodges worse than people and its hit rate is a floor. No
   human comparison established either claim, and worse dodging would not imply that floor. State these are
   automated measurements, with machine/seed limitations and no human play-feel verdict. Do not claim measured
   average contrast proves that a texture never vanishes on every composite. The director inspected the eight
   rendered barrage scenes, all six terrain composites and thirty corner views; label that scope precisely.
6. Pin current entry/asset/test counts only when directly recounted or reproduced, and label commands by what
   you actually ran in this copy. A separate director final verification may still be pending; do not invent it.
   If direct commands fail in the sandbox, identify the limitation and run the isolated equivalents where valid.
   No FILL/TBD or stale "director run in progress" sentence may survive in final release records.
   The director repeated the explicit one-fight batch (`director_gaunt_one runs=18 seed=11 speed=3 loops=1
   gauntlet=1 guardians=0,1,2,3,4,5 starts=2,6,12`): 18 fights, 16 won (88.9%), mean 1.17 hits/fight,
   peak 62, zero stuck/soft lock. Places and cycles were paired cyclically, not a full Cartesian matrix.
   A further director diagnostic on the corrected mode (`director_mode runs=4 seed=11 speed=3 loops=2
   gauntlet=1 guardians=3 starts=2`) settled all four runs after one fight, 41.6 seconds wall time.
   These supersede any "being repeated" status; preserve older measurements as dated history.
   The same development machine ran these measurements; do not call it another machine.
7. Distinguish code merge requirements from later store operations. Marketing screenshot proofs are stale after
   visual changes and must be reported; they do not authorize recapture. Firestore rules are committed but not
   deployed; analytics collection remains gated. Build/upload/review/tag rows stay uncompleted until performed
   under separate user authorization. Do not claim 3.0.0 is live, submitted, tagged or already merged.

## Do not

Do not edit game code/art/locales, README, student reference pages or lessons; the separate docs audit owns those.
Do not change engine, versions, package, purchases, checks or protected paths. Do not capture screenshots, run
devices/emulators, network operations, deploy, commit, push, create/comment on a PR or merge.

## Acceptance and deliverables

- Only the named author records, store-page/localization files, and the necessary store fixture test change.
- `pnpm check:store-metadata`, `node --test scripts/lib/store-metadata.test.mjs`, `check:hygiene` pass.
- The descriptions can be traced to actual opening, beacon, ending and Depth triggers; five-language metadata
  length checks pass, and IAP rows / existing marketing screenshots remain byte-identical.
- Release preparation is current without fabricated final verification or store actions.
- `IMPLEMENTER_REPORT.md` lists changes, field lengths, counts, reproduced commands, and remaining real limits.

The director will read every changed description and record, compare their assertions with the game, rerun the
metadata checks and inspect the final diff. Do not turn this into a new game-design round.
