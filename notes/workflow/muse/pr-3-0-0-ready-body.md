The 3.0.0 renewal gives each run a concrete purpose: light the road that lets Nari return to Lantern Hollow. Restored places, hero voices, route choices and the ending carry that promise through the game, alongside the rebuilt art, combat and interface.

## Changes

- Rebuild the six heroes, seven regular spirits and twelve guardian forms with original pixel art, distinct combat profiles, readable attacks and full-body previews. Replace the title, HUD, cards, shrine, shop and result presentation while retaining the integrated IAP 3.6.1 purchase/restore behavior.
- Expand the expedition into six terrains with fork clues, terrain structures, lighting, mist and floor detail. New owl, toad and sentinel guardian moves, mutations, formations, nine skills and the optional Depth stretch give repeated runs more choices.
- Establish Nari, Lantern Hollow and the road-home promise across three acts and an epilogue. Six dim/lit place motifs reveal ribbons, chimes, a kettle, a bell, a paper boat and a lens. Hero relationships, pause objectives and forty Chronicle entries connect discoveries to that world.
- Resolve the main story when the player completes cycle eight and returns: Nari is home. Early return and defeat have their own closing lines; continuing into Depth is voluntary. The official ending requires neither a paid hero nor every terrain memory.
- Keep discovery lines readable when a beacon also opens a fork or summons a guardian. Records survive deferred presentation, route captions avoid the hero and HUD at all four screen edges, and settled endings keep the Road detail separate from score rows.
- Tune ordinary barrages into slower, separated volleys with gaps, arrival quiet time and a shared 150-bullet field. Preserve guardian warnings, cover collision, damage protection and the node budget.
- Align the reference docs and five-language store descriptions with the accepted game. Preserve all one hundred existing IAP metadata rows. Separate code review from subsequent device, marketing capture and store submission steps.
- Correct regression checks for cold/warm title loading, cumulative skill discoveries, deterministic spatial-index selectivity and one-fight bot mode. A continuation retries only an explicit stale-session error; refusals and unknown failures remain failed runs.

## Validation

- Director-run `pnpm verify` passed on the final game/art/tooling state: 467 Node tests, 48 Godot game checks plus two import steps, all 118 scripts compiled, five locales loaded, 557 translation keys checked, 259 assets covered, deterministic generated art, store metadata, skill mirrors, hygiene, docs build and anchors. A subsequent single-paragraph Chronicle timing correction passed a separate final docs build, anchor and hygiene check; game/art/tooling bytes are unchanged from the full verification.
- Mutation checks demonstrated failures for broken discovery protection, hero clearance, Depth visibility, title deadlines, unseen-skill selection, spatial filtering, barrage caps, bot fight mode and refusal handling; exact restoration passed their related tests.
- `pnpm android:build` produced a signature-verified direct-distribution debug APK: package `com.crossplatformkorea.moonlitbeacon`, version 3.0.0 / code 15, arm64-v8a. Package inspection excludes tests/tools, Play Billing code and the IAPKit configuration. SHA-256: `c765d96e1390330f15aed346dc157e79e9e7078a662ab5f6c51b156c8b9c21e6`.
- Personally inspected all 22 UI stages across five locales using desktop harnesses, with separate settled act/result captures and four-edge caption captures. Reviewed all 192 hero, 112 spirit and 200 guardian production sprite cells, all nine skill icons, custom pickup/projectile/slash cells, six terrain composites and thirty terrain corner/center views.
- Frozen twelve-run bot confirmation covered 46.89 simulated minutes: 1.173 hits/minute, bullet peak 52, no pickup stuck or soft lock. The separate eighteen-fight guardian batch won sixteen fights, with 1.17 hits/fight and bullet peak 62. These are automated desktop measurements, not a human difficulty or mobile performance verdict.
- The director independently inspected implementer reports, diffs, source and measurements before accepting the work. Two final reviews of the full branch from different angles found no further corrections; [the tracked director record](notes/workflow/muse/director-continuation-3-0-0.md) contains the detailed evidence and boundaries.

## Follow-up release boundaries

- Physical-device visual/play confirmation is pending. The desktop manual diagnostic used debug controls and does not establish an eight-cycle human playthrough or an all-direction device matrix. No device install or store upload was performed.
- `pnpm check:store-screenshots` failed because the device capture proof file is missing. Existing marketing captures do not prove the renewed screens. No marketing screenshot was recaptured or uploaded; that remains a separately authorized release task.
- Echo-ring repeats remain bounded by the 24 hostile-projectile cap, so their warning can show more spokes than the actual repeat. Keep the mobile budget rather than remove the cap without device evidence.
- The passing title-transition check prints an eighteen-object teardown warning; its cause has not been established. No speculative production fix is claimed.
- Store AAB/iOS distribution archives, device purchase checks, Firestore deployment, store submissions and the release tag are not completed by this PR. Committed analytics remains off by default.
- GitHub CI and mergeability can be confirmed after publication. This preparation does not authorize merging.

Implementation was carried out by the repository's configured Muse implementer; the director supplied briefs, reviewed the results and ran the independent validation.
