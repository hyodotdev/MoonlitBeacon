# Brief 048: Bind public IDs to their real authenticated owner

## The ask
The user requires a unique stable player ID and a Hall of Fame showing that player's character and score. Continue the cloud data copy and repair ownership before UI integration.

## Confirmed evidence
The director ran all 20 real Firestore emulator tests successfully using official Firebase SDK/rules-unit-testing dependencies. A separate real-emulator probe then reproduced an ID takeover:
1. Owner creates profile, matching reservation and Hall score 10.
2. A different authenticated UID creates its own private profile with the owner's already-reserved public ID. Rules accept it.
3. That impostor overwrites the owner's Hall score with 11. Rules accept it.
Probe output: `impostor_profile_accepted: true`, `other_player_record_overwrite_accepted: true`.

ownsPublicId() currently checks the requester's profile but not the reservation owner. Profile creation also does not enforce the paired reservation. Immutable fields do not establish ownership when the initial claim is unchecked.

## Do
Enforce the UID/profile/reservation relationship in the rules, including atomic registration via getAfter where appropriate. No incomplete or mismatched pair should acquire ownership. Hall create/update/delete must verify the reservation and canonical profile belong to the caller. Preserve legitimate batch registration, collision handling and atomic owned-data deletion. Inspect deletion ordering so a removed reservation cannot be used to hijack or delete an existing Hall row. Use strict stable ownership; do not rely on IDs being hard to guess.

Add actual emulator cases for a private profile pointing to another player's reserved ID; subsequent Hall overwrite/delete; mismatched and incomplete registration; multi-write final-state bypass; authorized registration, cloud restore and complete deletion. Fix client commit construction if necessary. Run a negative control of reservation enforcement and demonstrate the new takeover test fails.

The checkpoint rules only bound an opaque string and its brace shape; that regex does not prove valid JSON. Correct any documentation or tests claiming server JSON validation. Keep downloaded JSON and Journey validation mandatory before application; demonstrate malformed payload rejection on the client. Do not invent an unsupported Firestore JSON parser.

## Do not
Do not alter legacy rules/contracts, gameplay/identity/art/UI, project/presets, package/runner/credentials or deploy anything. Retain additive rule/index artifacts for subsequent integration. No fake production/cloud claims.

## Acceptance and judgment
Real emulator tests allow a valid owner's atomic operations and deny all cross-owner ID/Hall writes and deletes, including the director's exact reproduction. Focused cloud client tests pass, stale account callbacks remain isolated, and malformed checkpoint data cannot be applied. Report exact commands and counts separately from mocks. The director reruns the takeover probe and the emulator suite before accepting.
