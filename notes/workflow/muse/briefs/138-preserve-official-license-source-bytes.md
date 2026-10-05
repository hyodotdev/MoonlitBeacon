# Brief 138: preserve official license source bytes

## The ask
"/loop-review돌리고 메인 다 클린한상태로 둔 다음 할까"

Finish the reviewed 4.0.0 local Git cleanup without corrupting its retained source provenance.

## Where things stand
The final stock integrated verification passes, and game/public-doc changes have local commits. Author notes are staged. The director's actual index-versus-working-byte comparison found exactly one mismatch: `notes/workflow/muse/donors/official-signin-110/OFL.txt`. Its original CRLF bytes have SHA-256 `2b75ef20f13d83a7514aee452c4782c20cdc9ff2dee17600f44d37a06d4fb958`, exactly the donor manifest. Existing `* text=auto eol=lf` normalizes the staged blob to SHA-256 `65ca17f235e1d9adaf2e25fd14d0929c75521ac1e063a48d6824a8e7b7e4466a`. A fresh clone therefore contradicts the adjacent source manifest.

## Do
- Add the narrowest explicit Git attribute needed to preserve this exact upstream source license as bytes. Use the existing binary-source convention, with a short explanatory comment if useful.
- Preserve the source license and the donor manifest byte-for-byte. Preserve global line-ending rules for every other path.

## Do not
- Change the license content, source hash, other assets, game, docs, tests, runtime values, guards, Git history, stores or remote configuration.
- Add a broad exception for all text/license files. Do not relax any runner.

## Acceptance
- The exact path has `text: unset` (or equivalent no-normalization contract).
- Director stages it using an isolated temporary index, then `git show :<path>` has the original SHA above; deleting the attribute temporarily must reproduce the normalized mismatch.
- No other deliverable changes. Repo hygiene and existing vendor/source-byte checks remain green.

## Deliverables
`.gitattributes` only.

## How the director will judge
Read the one-path attribute diff, prove a real staged blob's byte equality with both source and manifest, negative-test the attribute in an isolated copy/index, and verify all staged files have no unexplained byte differences. A report alone is not evidence.
