# Brief 078: lock the requested 4.0.0 display and build identifiers

## The ask
The user explicitly said “이렇게하고 4.0.0으로 해보자”. The director is building the local 4.0.0 renewal with login, persistent gate journeys, Hall, loading and original painted art. No upload or release is authorized by this brief.

## Exact change
Change only six assignment values in `apps/game/export_presets.cfg`: both Android `version/name` become `4.0.0` and both `version/code` become `17`; iOS `application/short_version` becomes `4.0.0` and `application/version` becomes `12`. The game project display version will be handled in final integration. Preserve every other byte, including package/bundle identity, renderer, icons, signing, plugins and presets.

## Narrow version-lock exception
This exact six-assignment change is the user's explicit 4.0.0 request, using the next unique Android/iOS identifiers after 3.0.0 (16)/(11). Follow the existing release configuration exception: the director inspects the patch then uses the normal `muse accept --allow apps/game/export_presets.cfg` path. Do not edit guards, rules, runner state, signing keys or any unrelated protected file. If the implementer cannot make this explicitly scoped configuration change, report the limitation and leave it untouched.

## Acceptance
Exactly one changed file, exactly six old/new assignment pairs. The director substitutes the six old values back and compares the result byte-for-byte to baseline. No asset regeneration, capture, export, network, publication or device work; no other deliverable except the ignored report.
