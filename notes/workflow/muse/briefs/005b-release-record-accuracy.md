# Correction 005b: Remove stale narrative counts and describe the current scope

The director read both new files in full. Their diff is within scope, but two statements copied from old build-log
prose are already false on your baseline: the Chronicle has 34 entries (the UI says 8/34 and the registered story
test expects 34), not 28; the locale checker reports 535 translations, not the 458 rows in your architecture prose.
The narrative is being expanded by a separately briefed game round after the user's latest request, so another
fixed count would become stale again. Remove those incidental hardcoded prose counts; say what the Chronicle
stores and that all five languages are supported. Keep counts only in dated reproduced check outputs.

Also correct the following:
- Firestore rules are committed on the feature branch, not merely modified in an uncommitted working tree.
  Deployment is still not done; do not claim it is deployed.
- Rename the verification table's "Result on the final tree" column to "Result on this preparation snapshot".
  This run is not the final tree. Preserve explicit historical labels and pending final checks.
- Mention that the user has now requested a stronger world and narrative tied to restoring places; mark that work
  as in progress, never implemented in this snapshot. The final record will be reconciled again after judging it.
- Do not list tagging as an operation the director may do automatically after submission. It remains a separate
  user-authorized release operation, as AGENTS.md requires.

Only edit `notes/plans/release-3.0.0.md`, the new 3.0.0 prep section in `notes/release/checklist.md` and your report.
Re-read the output of the locale and store-graphics checks where you reproduce them. Repo hygiene's six known
bullet-script failures are outside your brief; identify them as baseline failures rather than trying to fix them.
No new long test battery is needed for these note corrections. Confirm links and diff scope.
