# Brief 014: Retry only the recognized stale-session error

This branch adds the implementer runner. During whole-branch review the director found that
`scripts/muse.mjs` retries every quick failed continuation without its session id, while
claiming the CLI rejected an old session. The condition checks only failure/time, not the
error. Thus an approval/classifier refusal can be launched again, contrary to AGENTS.md's
explicit stop rule. The existing fake-CLI test covers `session already exists` only and has
no refusal regression. This is a narrow correction to the new branch tooling, not game work.

Change only `scripts/muse.mjs`, `scripts/lib/muse-cli.test.mjs` and necessary muse test
collateral. This brief explicitly permits these protected runner paths for director review.
Keep fresh-session recovery for the precise recognized `session already exists` error. Do
not infer it from an exit code, elapsed time or a broad word like `session`. Unknown failures
and permission/approval/classifier refusals must stop after one launch, remain failed, not
write a successful report, and never be accepted. Include an end-to-end fake refusal that
would succeed without a session id so a wrong fallback is detected, with exact launch count.
Preserve no-secret copy/environment, safe approval/sandbox flags, explicit fresh-session
option, timeout and all existing acceptance/revert/protected-path checks. No real provider
refusal, network, devices, game, docs, other guards, approval files, history or protected
rule edits. Run the complete muse tests, report the scope and exact outcomes. The director
will inspect both files, repeat the tests and read the failure-state evidence before accepting.
