# Brief 008: Finish the road home on the current tree

## The ask

> 약간 세계관이랑 스토리도 좀 부족한 느낌이 드는데 그 세계관에 빠져들 수 있는 스토리로 더 보완해줘 그 컨셉으로 겜을 다시 구성해야하면 에셋 다 수정하고 만들고 해도 되니까 자유롭게 재밌고 몰입감 있게 만들어줘

Integrate the already authored Lantern Hollow journey and fix the three defects found by the director.
This is a fresh copy because round 006's result patch no longer applies after the accepted UI polish.
Read brief 006 for canon and scope. The mechanically exported reference patch is
`notes/workflow/muse/inputs/story-006.patch`; it is reference material, not a deliverable to edit.

## Where things stand

The current tree has the accepted result Depth caption, English Wave wording, and shop description wrapping.
Preserve them and the current main IAP/Shop integration. The bullet round freezes combat balance and adds a
one-fight gauntlet rule. Do not retune it. Applying the reference patch may require reconciling the result script,
CSV, regression registry, game reference and build log; preserve both independent changes.

The director read the story implementation and ran its full game suite and 533 place cases successfully.
Six dim/lit terrain boards, all fourteen new motif cells, all five opening/ending boards and all five
fork/Chronicle boards were inspected. The modest pixel props fit the existing art. Keep those assets.
Two real-path diagnostics then failed: at the first fork `_open_fork()->_say("fork")` immediately replaces
the place discovery; at the classic third beacon `_summon_guardian()->_announce_guardian_meet` replaces it.
The existing six-place test mostly calls `_maybe_show_place_memory` directly and misses these paths.
A separate actual result geometry diagnostic failed: Detail was 117 px high and its bottom extended 6.5 px
into Road. The staged Japanese and Chinese results also visibly crowd score total and Road together.

## Do

1. Integrate the entire reference change into this baseline, including its two PNGs, generator, manifest,
   registered tests, five-language copy, six place memories, Chronicle compatibility and story documentation.
   Keep accepted result Depth behavior and score arithmetic. Avoid displaying Depth redundantly twice.
2. Preserve a new place discovery for a readable interval through the real first-fork and third-beacon paths.
   Guardian names, telegraphs and actionable route labels remain available. Do not mark suppressed discoveries
   as seen or silently lose their Chronicle entry. Avoid delayed callbacks outliving their run or speaking
   over a modal. Test actual `debug_light_next_beacon` paths, all six terrains, repeat/fresh runs and modal guards.
3. Resolve Nari's personal promise explicitly at eight completed cycles. Her signal answers and she reaches
   home; the kettle detail pays off in a short warm line, not only an abstract statement that a road is lit.
   Both the cash-out ending and the eight-cycle continue choice must communicate that resolution. Cycle 9
   explores other forgotten roads voluntarily. Earlier return and defeat must never claim she was rescued.
   Keep three acts at 1/3/6 and epilogue at 9, the existing save IDs and no-hate canon. Carry it in all five
   languages; purchased heroes and visiting all six terrains remain unnecessary for the official ending.
4. Give Road a real, nonoverlapping place on the result card. Preserve the score breakdown, grade, earned
   rewards, goal and buttons. Test actual visible Road, not only legacy callers which hide it: win, early,
   defeat, deep runs and large scores in all five languages. Assert rectangles separate and text fits.
5. Update the story bible/beat map and related reference/build-log sections to the final behavior. Remove
   the stale "fourth terrain" follow-up and "deep-night only balloons" claim where contradicted. Keep
   historical combat measurements dated and unchanged; final release records have a separate brief.
6. Extend the story screenshot harness for the explicit official resolution/continue choice and the real
   discovery cases. Capture after reveal/fade settles; terrain lit staging must really ignite its beacon.
   It remains diagnostic desktop evidence, not store capture. Finish the report with exact commands.

## Do not

No combat tuning, new mechanics, versions, locked values, controls, IAP pricing/ownership, Vault/ladder schema,
analytics policy, unlock cycles, terrain IDs, course prose, release/store files, git history, network, device
operations or protected edits. No store screenshot recapture. Do not work around a stale patch in the real tree.

## Acceptance and judging

Run the full registered game suite, locale/scripts/smoke/assets/hygiene and docs build/anchors. The late-game
node budget remains below 1200. Run store proof checking and report it without recapture. Mutation-check the
discovery priority or Road geometry guard. The director repeats those checks, the real integration paths,
critical five-language renders and a natural play diagnostic in your copy before acceptance.

Deliver the integrated game/art/tests/harness, asset tooling/manifest, story bible, game reference and build log.
Do not edit briefs or the input patch; do not leave temporary diagnostic modifications in the final diff.
