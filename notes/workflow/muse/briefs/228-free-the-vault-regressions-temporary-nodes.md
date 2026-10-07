# Brief 228: free the vault regression's temporary nodes

## The ask
Complete the integrated gate-lodge and twelve-hour attendance work with clean root verification.

## Confirmed root failure
`pnpm verify` stops at [Vault purchases and migration]. All381 behavioral checks pass, but Godot reports16 leaked ObjectDB instances and2 resources still in use, so the unchanged strict regression runner correctly fails. A director isolated verbose run names13 leaked Nodes and the vault/failing-vault scripts as held resources. Evidence is builds/verify/gate-vault-leak-verbose.log in the real tree; no human save was accessed.

The new _test_continue_txn_atomicity and _test_prepare_receipt_move functions create temporary normal and failing Vault Nodes without matching frees, including the malformed-journal loop. Other functions explicitly free their temporary nodes. Inspect the evidence and all new fixtures rather than blindly suppressing output.

## Do
- Correct ownership/teardown of the temporary test nodes in test_vault.gd, including loop instances and both normal/failing fixtures. Preserve all behavioral assertions, isolation guard, save rollback and atomicity scenarios.
- Add a meaningful runtime teardown guard (for example orphan-node baseline equality around these fixture groups) so intentionally omitting a free makes the registered test fail. Do not merely check that source contains free calls.
- Independently run the actual registered Vault command with its isolated user-path environment, including verbose diagnostics. Allbehavioral assertions must remain and output must contain no leaked instances/resources or Godot errors/warnings. Verify a deliberately omitted cleanup fails, then restore and rerun clean.
- Run relevant adjacent defeat/paid-continue regressions and report precise results. The director runs root full verification afterward.

## Do not
Do not change production game/native/cloud/asset behavior, remove tests, weaken the strict ERROR/leak detection or runner, change versions, touch secrets or real saves, build device packages or recapture marketing screenshots. No protected paths need editing. Do not edit director briefs or review notes.

## Acceptance
Root registered Vault regression succeeds with381 existing behavioral checks retained (new teardown assertions may add to count), no teardown diagnostics, and a meaningful negative cleanup control. Production game bytes stay unchanged.

## Deliverables
Narrow fixture-lifetime correction and registered teardown guard, accurate report and optional author-only build-log entry. No production workaround.
