# Brief 016: Describe place-record timing accurately

Only `apps/docs/docs/game.md`, the paragraph under **The chronicle.** Current text says every story beat, place memory, first-sight line and ending is written “at the moment it plays.” Accepted `arena._restore_place()` writes a place entry at restoration before `_maybe_show_place_memory`; a modal can defer its discovery line without losing the entry. So that blanket statement is false for place memories.

Change only this paragraph to distinguish place entries recorded when their beacon is restored from dialogue/first-sight/ending entries recorded as their moment occurs. Keep forty entries, unmet blanks, separate Chronicle/Vault save files and missing/unreadable-file behavior. Do not change game code, saves, other docs, numbers, tests, scripts, assets or notes. No network, device, capture or git action.

Read actual restore/Chronicle/voice/result call sites. Run hygiene and docs build/anchor checks if feasible, report limitations honestly. The director will compare the one-paragraph diff to source and final root docs build.
