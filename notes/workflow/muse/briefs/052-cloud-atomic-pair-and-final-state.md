# Brief 052: Keep the ID pair intact through registration and deletion

## The ask
Finish the owned-cloud foundation for unique stable player IDs. Continue the cloud copy with the director's real-emulator results.

## Confirmed evidence
The real Firestore emulator now passes 31/32 cases. The failing test is `same-batch reservation delete cannot smuggle a profile`, second.commit at test line 475. That second batch sets then deletes the same previously absent profile and leaves no document. This harmless no-op is permitted by the missing-row deletion contract; expecting denial is wrong. Correct that expectation and verify the final absent state. Do not weaken the actual foreign-ID, mismatched pair or final-state orphan assertions. The director's separate owner/impostor replay is being repeated independently.

The revised rules still allow lone reservations and reservation-first sequential registration. The client registers atomically, but the server does not enforce the same complete pair. More concretely, after deleting one's Hall and reservation, an existing immutable profile can still point to that freed public ID; the client fetch_canonical_id trusts that profile as cloud-owned, and another UID can reserve/re-register the freed ID before the original profile is deleted. Your delete_account_data performs four sequential HTTP deletes, so a process kill after the reservation delete creates exactly that partial state. Fix the paired identity contract rather than relying on randomness or the deletion finishing.

## Do
Require profile and reservation consistency in the final state for creation of both halves. Make legitimate client registration one atomic commit and tests use that contract. Prevent either living pair half from being removed by itself; make complete account cloud deletion one authenticated atomic commit before Firebase Auth deletion. Check Hall ownership in the relevant pre/final states so full deletion is allowed while final orphan creation or conflicting live ownership is denied. Interrupted or repeated deletion remains safe: missing rows may be no-ops without assigning another player's ownership. Retain explicit failure reporting and never delete Auth until the cloud commit is acknowledged.

Update focused client deletion tests and real emulator tests: lone reservation denied; both mismatched pair variants denied; canonical profile cannot coexist with a missing or another owner's reservation after a commit; full atomic registration and deletion allowed; foreign player Hall cannot be changed or deleted; harmless set/delete no-op leaves no new document. Correct runbook and rule comments. Use a genuine enforcement negative control; a rules-disabled smoke test alone is not sufficient to prove the new ownership assertion exercises the guard.

## Do not
Do not touch legacy rules/contracts, native/UI/journey/art/project/presets/package/runner/stores/credentials or deploy. No server JSON-parser claims. Keep downloaded Journey validation mandatory.

## Acceptance and judgment
Director repeats all real-emulator cases with zero failures and the takeover probe remains denied with owner score unchanged. Registration/deletion requests are actually atomic Firestore commits, and malformed/stale/offline/cross-account client tests remain green. A crash cannot leave a canonical profile claiming an ID that is now owned by another account. Report exact commands/counts and the negative control.
