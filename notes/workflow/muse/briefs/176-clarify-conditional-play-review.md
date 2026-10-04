# Correct the documented Play post-apply sequence

The director independently ran both changed Play Node suites: 136 tests
passed (the package suite imports publisher cases). The new delegate and
token/receipt checks are acceptable. One operator-facing defect remains in
`notes/release/google-play-publisher-apply.md`: the command block always
promotes, then submits review, but the promotion can already return
`IN_REVIEW` or `PUBLISHED`. The existing review implementation correctly
refuses those states. Saying it refuses any versionCode production already
carries is also inaccurate: a matching `NOT_SENT_FOR_REVIEW` release is an
explicitly supported staged case.

Correct the runbook and CLI help to state that the final review command is
conditional on the exact replacement still needing review: use it when the
readback is `NOT_SENT_FOR_REVIEW`, or the supported not-on-production fallback.
If promotion readback is already `IN_REVIEW` or `PUBLISHED`, record that state
as success and do not submit again. Describe the refusal specifically as
already in review or published; retain the staged case. Do not change the
working implementations or contracts. No new tests are needed for this text
correction; run existing related Node suites only if code changes, plus help
rendering/hygiene/diff check.

Keep all round-1 work and all five changed files intact. Only correct these
operator instructions; no game/counter/asset/network/store/git/protected
changes. Rewrite the report accurately.
