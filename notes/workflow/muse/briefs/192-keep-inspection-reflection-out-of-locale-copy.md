# Brief 192: Keep inspection reflection out of locale copy

## The ask
“캐릭터 일관성이 젤 중요해 크기 이런거 항상 잘 확인해 이것때문에 계속 배포를 못하고 취소하고 하자나”
Fix the confirmed final-check failure in the recently accepted unboosted native inspection regression, preserving its real safety assertions.

## Confirmed failure
The director's actual root `pnpm verify` passed the game regression battery and stopped at `check:locale`:
`apps/game/tests/test_store_capture_clean_ui.gd:266: INSPECTION_KINDS is not in the translation table — the key will show on screen`.
At that line `_has_inspection_kinds()` reflects on the boot script's constant map; the string is an internal symbol, never player copy. The frozen standing-art copy's successful whole check predates the later inspection test changes, so it did not contain this literal. This finding is independent of the finished three-round standing-art repair.

## Do
- Change the inspection test's internal reflection lookup so it retains the same constant-presence behavior without presenting an uppercase locale-key literal to the locale scanner. Follow existing test conventions; a small split/composed internal-symbol value is appropriate.
- Keep all real-production entry, unboosted Lv1 boot, no Vault mutation, no journey arming and persistent capture safety assertions intact. Run the registered clean-UI suite and `pnpm check:locale`; both must pass. Demonstrate the reflection predicate still rejects a missing constant with a temporary isolated negative probe or an existing meaningful check.
- Add a short 4.0.0 build-log entry explaining the false positive and actual verification, without claiming native matrices or store submission complete.

## Do not
- Change the locale scanner, translation tables or scanner exclusions. Do not add a fake translation or remove/weaken the reflection check.
- Change production scripts, hero art, rigs, thresholds, versions, stores, capture provenance or marketing/IAP images. No fourth standing-art round.
- Network, git history, credentials or device operations.

## Acceptance and deliverables
Only `apps/game/tests/test_store_capture_clean_ui.gd` and `notes/plans/4-0-0-build-log.md` change. The internal constant lookup behaves as before, registered clean-UI regression and `pnpm check:locale` pass, and `git diff --check` is clean. Report exact commands and results, including any sandbox import limitation. The director will independently run the real root commands again before release.
