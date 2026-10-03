# Brief 133: align the current game reference with the final entry

## The ask
"/loop-review돌리고 메인 다 클린한상태로 둔 다음 할까"
Complete the same review round by correcting two independently confirmed current-reference discrepancies.

## Where things stand
This continues brief 132's documentation-only copy. Keep its three corrected files and add only `apps/docs/docs/game.md`.

The director read the actual `ProductionEntry._ready`, `_on_title_start`, `_refresh_identity`, and `CloudSchema.HALL_FIELDS`, and inspected the final native title/tap/identity screens.
- `game.md`'s current 4.0.0 moon-gate paragraph says a brand-new installation first shows the sign-in choice and a returning account goes straight to its card. Actual first paint is always the original title; a tap opens the chooser or restored-account card over it. The initial cloud check then owns the card until its result or explicit offline choice. Preserve the original title/shop/menu design in the description, and describe Google then Apple then guest order and truthful provider readiness.
- Immediately after the 4.0.0 section, the paragraph beginning "The online ladder is implemented with Firestore REST" describes the legacy public-name `/scores` ladder and says default builds use only local records. The new authenticated `mb_hall_v1` implementation uses public ID, canonical hero, score, cycles, release, schema, and update time; it never uploads the legacy name or a rank field. Scope the old paragraph explicitly as the legacy path instead of contradicting the active 4.0.0 Hall. Explain the active Hall from source without claiming release/provider setup is complete.

## Do
- Correct only those two parts of the game reference; keep lesson and historical 3.0.0 descriptions intact.
- Keep the brief 132 changes intact, including source-only versus enforcement evidence and pending provider boundaries.

## Do not
- Change code, assets, tests, dependencies, presets, or any other documentation.
- Claim a mid-fight save, proven anti-cheat, Apple Android readiness, Play Games readiness, or unobserved native results.

## Acceptance
- Final diff changes only the three brief 132 files plus `apps/docs/docs/game.md`.
- The entry explanation matches the actual title-first tap flow and saved-gate check.
- The active Hall row description matches `CloudSchema.HALL_FIELDS`; the legacy paragraph is clearly historical/legacy and no longer describes current Hall upload as name/rank data.
- Documentation build and anchor checks pass where the copy's dependencies permit; report unavailable dependencies honestly.

## How the director will judge
Read every changed line against runtime source, independently run the corrected rules commands, and run the normal integrated verification in the real tree after acceptance.
