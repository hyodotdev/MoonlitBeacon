# Brief 035b: reject a newer committed Play build before mutation

## The ask
“심사 제출해줘 최종본으로 다 빌드해서”

This corrects the new binary-only internal update before any real store write.
Keep the accepted release scope and every guard in brief 035.

## Confirmed director evidence
In a separate sanitized measurement copy, the director reused the actual
registered fixture/test and changed only its remote artifact from code 2 to
code 3, while the local new binary remains code 2 and retained binary code 1.
Both the internal and production variants reach an internal commit of code 2.
The existing test fails with `binary-only app commit succeeded=true` and a
later missing-new-release readback. Neither variant rejects the newer remote
code before insertion, upload, track update or commit. No real API was used.

Evidence is in `builds/verify/play-binary-higher-code-probe/receipt.json` and
the two logs there. The measured candidate module SHA-256 was
`2027a000af51492600922cfaafe30b716ae5678f0ffba781dfa1ae00d44b6a7b`.
Original implementer files were never modified by those probes.

## Correct
- Preserve duplicate-code detection and the exact retained-release gate.
- Before creating a receipt or inserting an edit, validate remote artifact
  version codes and refuse when the proposed code is below or equal to any
  existing code on internal or production. Do not downgrade or overwrite a
  surprise newer build. Reject malformed/conflicting codes conservatively.
- Add genuine registered regressions for newer internal and production
  states, asserting no mutation calls and no intent receipt. Keep existing
  duplicate/unchanged-gallery and successful code-1-to-2 cases intact.
- Independently demonstrate failure under the round-1 predicate, restore
  the candidate exactly, run the related suites and finish the report.

## Scope and acceptance
Only the new binary-only module and its existing registered test file need
changes. All pending round-1 work remains in the copy. No runtime, metadata,
gallery, protected paths, network or device actions. Preserve the dedicated
token, immutable artifact, account-owner config, internal-only scope,
uncertain-commit receipt and unchanged-gallery checks. The director will
read the final diff and repeat the registered tests and negative controls.
