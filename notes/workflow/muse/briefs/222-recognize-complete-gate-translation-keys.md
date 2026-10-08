# Brief 222: recognize complete gate translation keys

## The ask
"코인은 그리고 반나절마다 출석하면 2코인씩 주고 반나절마다 알림을 보내면좋아 지금 출석하면 코인 받는다고. 그리고 알림은 설정에서 안받게 할 수도 있게 해야하고"
Close the integrated verification of the already accepted lodge and attendance feature.

## Where things stand
The feature and native reminder builds are accepted. Root `pnpm verify` passes the Android/iOS preservation and package tests, then fails `test:gate-locale`: `test_gate_lodge.gd:1034` uses `begins_with("gate.lodge.")`, which the existing quoted-key scanner falsely treats as a complete translation key. This is a legitimate prefix, not displayed UI copy. The scanner already intentionally ignores the bare `gate.` prefix.

## Do
- Correct the complete-key recognition in `scripts/lib/gate-locale.test.mjs` so trailing-dot namespace prefixes are ignored while complete used keys, including misspellings, remain checked against the CSV. Add focused evidence for that distinction if necessary.
- Run `pnpm verify` in this copy. Fix only additional confirmed integration defects, keeping changes narrow and reporting the actual failing command and evidence. Stop and report anything requiring product policy or unrelated redesign.

## Do not
- Do not alter the translation CSV, lodge art, production game behavior, native code, wallet rules, locked engine settings, verification budgets, or existing screenshot files just to satisfy a scanner.
- Do not remove tests or exclude game tests from the scan. Do not modify the director review note or briefs.

## Acceptance
- `pnpm test:gate-locale` passes and still rejects a real nonexistent complete key in an independently reversible negative control.
- `pnpm verify` passes in the integrated copy, or reports concrete next blocking evidence without pretending success.
- No production visual or runtime changes for this scanner correction.

## Deliverables
The scanner fix, any focused scanner regression evidence, and a short report of actual checks. No build-log expansion needed for a test-only correction.
