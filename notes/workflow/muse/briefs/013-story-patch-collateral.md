# Brief 013: Drop already-integrated generated UID collateral

This is a narrow integration correction to brief 008. The director's accept preflight refuses
two added files because they have already been committed independently on the real branch:
`apps/game/tests/test_play_bot_modes.gd.uid` and `apps/game/tools/bot_modes.gd.uid`.
The director compared the bytes; both are identical to the copy. Remove these two untracked
generated files from your delivered patch, after all engine operations, and do not regenerate
them afterward. The real tree keeps the already-committed originals. Do not change any other
deliverable, reapply the reference, change production behavior, or rerun the long suite.

The director already independently passed the 951 place cases, 135 result-layout cases,
55 depth cases, 331 choice cases and 695 structure cases; rendered all five locales with the
new harness; validated 221 staging cases; and removed the actual discovery guard to observe
four failures, restored the bytes and repeated all 951 passing cases. The two unrelated
flaky tests are being corrected in separate copies. No engine process is running here now.

Update the report only to record this integration-only removal and preserved evidence.
The patch must retain every other brief-008 file and apply cleanly onto the real tree.
No git history, network, devices, stores or protected files.
