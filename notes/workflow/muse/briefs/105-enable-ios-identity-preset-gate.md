# Brief 105: connect the real iOS preset to the existing identity entitlement gate

## Confirmed integration gap
Keep completed Brief 101 registration unchanged. Your report correctly identifies a real wrapper dependency: identityPluginEnabledForPreset in scripts/lib/identity-export.mjs returns false unless the iOS preset explicitly has plugins/MoonlitIdentity=true. With the missing key, the existing shouldStageAppleEntitlement gate can NEVER stage a legitimately configured Apple sign-in grant. This is required integration for the user's Google/Apple/guest request, not activation of any external provider.

## Exact narrow authorization
You may change the otherwise protected apps/game/export_presets.cfg for EXACTLY ONE added line: plugins/MoonlitIdentity=true immediately below plugins/GodotIap=true in the iOS options section. Keep every version/build/package/signing/locked preset value and both Android presets byte-identical. The director will read the diff and normal accept with --allow apps/game/export_presets.cfg. No bypass or general preset edits. Do not set any provider readiness flag, add a credential, stage a grant unconditionally, or change signing.

## Focused verification
Add meaningful actual-repository preset coverage to the existing identity-export Node suite: the real iOS preset opts in; with genuinely incomplete Apple config shouldStageAppleEntitlement still returns false; the existing fully configured fixture can stage only through all existing readiness checks. Keep all prior assertions and byte-restore tests. Update the distinct native registration release note and its current author-log entry to reflect the one opt-in, no remaining missing-preset claim. Run that focused suite, hygiene and the registration scene once; no repeated full suite, no UI change, no SDK rebuild. Produce finite report.
