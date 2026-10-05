# Brief 074: make adding the next story episode work as documented

## The ask / evidence
The user asks for an endless journey that is easy to expand with later scenarios. The accepted StoryEpisodes comment says append a new episode without reordering stable IDs. The director appended a finite future episode for cycles 13–16 after the shipped endless fallback. Actual code returns episode13=endless / endless13=true while story_keys13 resolves the new authored keys. See `director-story074-append-probe.log`: the fallback's open range captures the appended chapter before it can be selected. The current extension fixture pops the fallback and moves it, so it doesn't test the documented append-only workflow.

## Do
Resolve an applicable authored finite episode before the open-ended fallback, with a deterministic documented precedence for future additions. Preserve all shipped episode/act/chronicle IDs, current 1–12 dialogue and endless behavior outside authored ranges, saves, monetary rules and combat. Add meaningful tests that **append only** to the shipped catalog and prove act/episode/story-key/endless results agree at both chapter bounds, intervening silence and after the new chapter. Correct the author guidance and existing extension example so its commands describe actual behavior. Do not add unrequested new story content or generic infrastructure.

## Scope / judgment
Only StoryEpisodes, directly related story/Journey catalog tests and the author/player guidance already owned by this catalog. No Arena/host/cloud/native/Vault/other Journey persistence/shared runner/package/locked values/art/stores/history. The director will rerun the append-only probe, Journey and story suites, then a restored negative control, and accept normally. One task: reliable future episode additions.
