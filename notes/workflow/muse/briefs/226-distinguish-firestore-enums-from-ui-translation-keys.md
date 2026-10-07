# Brief 226: distinguish Firestore enums from UI translation keys

## The ask
"코인은 그리고 반나절마다 출석하면 2코인씩 주고 반나절마다 알림을 보내면좋아 지금 출석하면 코인 받는다고. 그리고 알림은 설정에서 안받게 할 수도 있게 해야하고"
Finish integrated validation of the accepted attendance feature.

## Confirmed defect
Root `node .github/scripts/check-locale.mjs` fails on `apps/game/scripts/cloud/cloud_attendance.gd:72`: REQUEST_TIME is not in the translation table. This is the real Firestore `setToServerValue` wire enum, not displayed copy; actual Firebase claims already successfully used it. The uppercase-string heuristic confuses this protocol value with a UI key.

## Do
- Correct the scanner to recognize REQUEST_TIME specifically as the direct string value of a Firestore `setToServerValue` field. Do not globally exempt that token: `tr("REQUEST_TIME")`, scene text, a stored UI-label key, or an unrelated literal should still be caught as missing translations. Keep table/resource/other-script coverage, CSV placeholder checks and font checks intact.
- Add focused registered regressions that run the actual checker over independent fixtures: valid protocol transform passes, nonexistent real UI key fails, REQUEST_TIME used as UI still fails, and a line containing both protocol and UI literals must not hide the UI occurrence.
- Run the focused Node checks and existing gate-locale tests. No full copied-environment game verification is needed; the director will run root `pnpm verify` afterward.

## Scoped exception
The director explicitly authorizes writing `.github/scripts/check-locale.mjs` in this isolated copy for this narrowly described validation correction, as an exception to standing order2. No other protected path may change. The director will independently review the scanner, test its negative controls, and use `muse accept --allow .github/scripts/check-locale.mjs` for this exact file. Do not change CI workflows or acceptance tooling.

## Do not
Do not add REQUEST_TIME to the player translation table, obscure/split the production protocol string, alter reward or request behavior, weaken checking by excluding files, or change assets, native code, credentials, versions or marketing screenshots. Do not edit the director's briefs/notes.

## Acceptance
Root scanner recognizes the valid server timestamp transform while continuing to reject all the specified nonexistent UI uses. Registered meaningful tests pass; existing localization and font checks are preserved. No player-visible or runtime change.

## Deliverables
Narrow scanner correction, registered regression evidence and an accurate report. No production game or asset changes.
