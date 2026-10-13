# Brief 247: trim the confirmed audit whitespace

## The ask
One-line cleanup only. Preserve every current staged deliverable exactly.
The director's final git diff --cached --check found trailing whitespace at
notes/course/followability-audit-20261013.md line593, after the `lesson-01`
through ... text in the B2 item. Remove only that trailing space.

## Acceptance
The file has no trailing whitespace; the diff changes only that one line.
Do not alter prose, source code, dates, metrics, links, or any other file.
No network, installs, Git history, protected-path changes, source mutation,
full re-test or unrelated edits. Report the one-line change and exact check.
