# Brief 170: correct Android resume identity-byte scope

## The ask
“이어서 플레이가 잘 되는지 겜 종료하고 나서도 체크해줘야해”

## Confirmed correction
The Android paragraph currently says identity bytes are equal even after the
resumed arena runs. That overstates the director evidence. The record explicitly
says `created_utc` in `player_identity.cfg` changes through `_save_id` while the
public ID remains the same. Before and immediately after launch the identity
bytes did match, but after Resume only the public ID is equal. Checkpoint,
revision and binding bytes remain equal at all measured boundaries. Journey,
route, seed, hero, cycle, zone and growth also match.

## Do
Correct only that Android status paragraph in
`notes/release/player-identity-setup.md`. State each equality scope precisely,
including the harmless rewritten identity timestamp. Preserve every other
accepted paragraph and all 15 unchecked requirements. No code changes.

## Acceptance and judgment
Diff scope remains only the setup note. The Android paragraph must agree with
`notes/workflow/muse/apple-auth-and-cold-resume-validation.md`, without claiming
byte-identical identity after Resume. Hygiene passes. No credentials, personal
IDs or local private paths are added.
