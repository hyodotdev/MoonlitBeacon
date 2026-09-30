# Brief 006: A road home, told by the places the player restores

## The ask

The user's words:

> 약간 세계관이랑 스토리도 좀 부족한 느낌이 드는데 그 세계관에 빠져들 수 있는 스토리로 더 보완해줘 그 컨셉으로 겜을 다시 구성해야하면 에셋 다 수정하고 만들고 해도 되니까 자유롭게 재밌고 몰입감 있게 만들어줘

Make the world worth caring about and let playing reveal its story. The user permits restructuring the game and
replacing or making assets. This continues the 3.0.0 renewal on the current feature branch; the endpoint is a PR
ready for review and merge, without merging or submitting to a store.

## Why, and what good feels like

The director read the complete current story in the CSV and the bible. Its ideas are evocative but abstract:
the Wardens fell, darkness is hungry, light draws a line, an unspecified debt is paid. There is no named person to
care about, no concrete place to return to, and no discovery attached to choosing one terrain rather than another.
The director rendered all six places, the actors, the fork and the epilogue. Art is already charming and the places
are distinct. Preserve that strength. A player should understand an immediate personal goal before moving, discover
something emotionally concrete at their first beacon, and feel the world answer their actions. Combat remains a
readable, cute dodging game. This is one integrated narrative journey, not a lore encyclopedia.

## Direction decided by the director

- Home is **Lantern Hollow** (Korean **등불마을**). One named supporting character is **Nari / 나리**, the signal keeper
  and a friend of the chosen hero. Nari went to repair the failing beacon road and disappeared in the Moonless.
  Her last message asks the hero to keep the road home lit. Give the message an ordinary human detail (a kettle kept
  warm, a promised festival, a lamp in a window); the specific detail must pay off in the ending.
- Darkness swallows light and with it paths, names and shared memories. It is hunger, not an evil emperor.
  Spirits are lost fragments drawn toward light. Guardians are swallowed light holding the habits of their places.
  Recovering the light restores a way home, rather than slaughtering monsters. Keep the existing no-hate canon.
- Preserve three acts and an epilogue at cycles 1, 3, 6 and 9. Give them dramatic movement: a promise and a trail;
  the discovery that what pursues the hero is lost rather than hateful; learning that beacons must remember one
  another to form a road; the road home restored, with other lights still beyond the map.
- Cycle 8's official settlement is a real payoff to Nari's opening message. Continuing into Depth is a voluntary
  expedition for other forgotten roads, not a declaration that the ending did not matter. Defeat and early return
  have distinct compassionate closures and a concrete reason to try again.
- Each hero has a different relationship to the same place and promise: Warden carries the message, Keeper tends
  its hearths, Knight once guarded its road, Dancer misses its festival, Sage charted its signals, Eclipse recognizes
  the first missing light. Rewrite the current generic debt copies into these voices. Do not add named people just
  to inflate the cast. The paid heroes are alternative voices, never prerequisites for the main story.
- Each terrain reveals a local memory through a recognizable object and a sensory detail: forest trail ribbons,
  field wind chimes, camp kettle/hearth, frost signal bell, marsh paper boat, ruins signal lens. You may improve
  these motifs if the existing art gives a better concrete expression. The same canon must support all routes.

## Where things stand

Read `notes/plans/world-story-pass.md`, `3-0-0-expedition.md`, `3-0-0-build-log.md`, `apps/docs/docs/game.md`,
`scripts/gameplay/acts.gd`, `chronicle.gd`, `hero_voice.gd`, and the story/route/beacon/guardian functions in
`apps/game/scripts/gameplay/arena.gd`. Paths without a prefix in that sentence are under `apps/game/`.
UI is in `scripts/ui/dialogue_scene.gd`, `act_card.gd`, `voice_panel.gd`, `chronicle_panel.gd`, `result_panel.gd`,
`run_choice_panel.gd`, `pause_panel.gd`. Copy is in `apps/game/localization/moonlit.csv`, all five languages.
There are 34 current chronicle entries, 6 heroes, 7 spirits, 12 guardian forms and 6 terrain IDs.
The first cycle has the classic route; forks start at 2; frost/marsh unlock at 3 and ruins at 4. An official win
does not require visiting all terrains. Existing save IDs and chronological entries already exist on users' devices.
The bullet and UI polish work accepted before this brief is the baseline: do not undo it or retune its balance.

## Do

1. Build this canon into concise opening, cycle, hero, guardian, act, fork and ending copy. The first playable
   minute must contain a human hook, a clear goal and a discovery, not only instructions and abstract sayings.
   Keep dialogue quickly dismissible; make previously seen text available in Chronicle. Do not repeatedly interrupt
   dodging to read a paragraph. Main story beats depend on cycle progression, never on lucky terrain RNG.
2. Attach six **place memories** to actual first-beacon restoration in their terrain. Each has a small crafted
   visual motif in the real world which changes from lost/dim to restored/lit when the beacon is lit, a concise
   nonblocking discovery line, and an entry the player can reopen in Chronicle. A run repeats neither the discovery
   popup nor duplicate entries; new runs still have a visible restorative action. Put motifs near existing beacon
   clearings, not in movement corridors. They add no combat power and no collision. Avoid a scavenger hunt away
   from the existing core loop. Route choice should suggest the memory waiting in that place while retaining the
   actual terrain, omen and guardian information the player needs to dodge.
3. Give the player a compact accessible reminder of the immediate story objective/progress (in an existing pause,
   choice or HUD space that fits). Close the loop in the settlement and ending: do not invent a cutscene that
   claims Nari returned before the official road is complete. The ending may use a small crafted village/window
   motif to answer the opening message. Preserve every actionable button and the existing score arithmetic.
4. Make any assets this needs through a deterministic local generator and real production textures, following the
   existing limited-palette pixel pipeline. Add manifest rows and `--check` integration when appropriate. Reuse good
   existing hero/combat art. No network or image service is available in your copy; request the director's operation
   in the report if a new visual needs it. Six modest world motifs can be authored with the existing generators.
5. Preserve existing Chronicle records, validate new IDs and make restore/save/reset behavior testable. Extend and
   register tests covering: first beacon once per terrain; six places and alternate routes; persistence with old
   records; repeated beacons and fresh runs; correct ending boundaries; main story not gated on six-place completion;
   all five languages fitting; no popup during a modal/transition; budget and clean teardown. Mutation-check a
   representative integration guard. Avoid tests which only pin the exact prose.
6. Update the story bible, build log and game reference to the implemented canon, including a beat-to-trigger map
   and what a person can actually see in the first minutes. Remove obsolete assertions such as the unresolved debt
   or off-map lore having no names where the new game contradicts them. Keep course lesson prose untouched.
7. Stage a desktop screenshot harness for opening, each terrain before/after restoration, route clues, a resumed
   Chronicle, and all three ending outcomes; include a validation mode if rendering is unavailable. Name output
   paths and commands in the report. Run the related checks and finish `IMPLEMENTER_REPORT.md`.

## Do not

Do not change version/build numbers, engine/renderer/resolution, controls, IAP pricing/ownership, Vault schema,
score/ladder storage, analytics consent, unlock cycles or terrain IDs. No new combat mechanics, enemy health or
bullet tuning in this brief. No individual node per particle. Do not touch stores, capture store screenshots,
upload, deploy, commit, push or open a PR. Leave protected files alone. Do not replace the charming art with a dark
epic aesthetic. Do not gate the official ending on rare routes or purchased characters. Do not turn narrative
progress into a claim that all missing people are rescued after one early beacon.

## Acceptance

- The director can reproduce a fresh title start and read who Nari is, what was lost and what the hero promises
  before movement. A real first beacon produces the first place discovery and restores a visible motif.
- All six terrains have different, readable before/after motifs and memories; forks keep actionable labels;
  repeated beacons do not spam; Chronicle survives a reload with old records intact.
- At early return, defeat, the official win and Depth, prose and visible progress agree with the real state.
  The main arc is complete without visiting frost/marsh/ruins; every hero can finish it for the same gameplay cost.
- `pnpm test:game`, related new registered tests, `check:locale`, `check:scripts`, `game:check`, `check:assets`,
  `check:hygiene`, `docs:build`, `check:docs` pass, or the report precisely names sandbox-only rendering failures.
- `test_late_game_performance` remains within 1200 nodes; no crowded HUD, hidden input or lingering audio on quit.
  Run and report `check:store-screenshots` without recapturing. The director separately renders the staged shots.
- Report the exact new entry/asset counts, triggers, tests, measurements and limits, with no TBD placeholders.

## Deliverables

The integrated game/data/UI changes, new deterministic production art and manifest, registered tests, the screenshot
harness, `notes/plans/world-story-pass.md`, `notes/plans/3-0-0-build-log.md`, `apps/docs/docs/game.md`, and the report.
All narrative copy travels together in en, ko, ja, zh_CN and zh_TW. Do not edit `notes/workflow/muse/` or release copy.

## How the director will judge

The director reads all new copy and code, repeats tests in your copy, mutation-checks a guard, renders all before/after
place states and endings, and watches natural play so that an explanatory test stage cannot stand in for real
triggering. The director can return a correction for tone, pacing or implementation defects. Finish a coherent
playable journey before adding extra optional lore.
