# 4.0 iOS manual distribution-profile export

When automatic `xcodebuild` export picks the wrong cached App Store profile,
pin the validated installed profile for one `export-appstore` run. Automatic
signing stays the default; setting both variables below selects manual mode.

## Variables

| Variable | Value |
| --- | --- |
| `MOONLIT_IOS_APP_STORE_PROFILE` | Installed profile **name** (as shown in Xcode/Organizer) or its **UUID** (the `.mobileprovision` file basename). Never a file path. Prefer the UUID: one name shared by different profiles is rejected as ambiguous. |
| `MOONLIT_IOS_APP_STORE_SIGNING_IDENTITY` | Installed distribution identity in either form: the full name exactly as `security find-identity -v -p codesigning` prints it, for example `Apple Distribution: <name> (<team>)`, or the bare 40-character SHA-1 fingerprint. Use the fingerprint when the keychain holds several certificates under one common name, including a revoked older one. `Apple Development` and malformed hashes are rejected. |

Find the values with the standard macOS tools (`security find-identity`,
the installed provisioning-profile list, `security cms -D` plus `plutil`).
Do not paste real names, UUIDs, fingerprints, or team IDs into this note or
into chat.

## Local use

```bash
export MOONLIT_IOS_APP_STORE_PROFILE="<profile UUID>"
export MOONLIT_IOS_APP_STORE_SIGNING_IDENTITY="<40-character SHA-1 fingerprint>"
pnpm ios:export-appstore
pnpm ios:validate:dry-run
unset MOONLIT_IOS_APP_STORE_PROFILE MOONLIT_IOS_APP_STORE_SIGNING_IDENTITY
```

Manual mode searches the modern Xcode provisioning-profile directory first
with the legacy MobileDevice directory as fallback, and validates the
installed profile before invoking `xcodebuild`. It writes a manual
`ExportOptions.plist` that maps exactly the expected bundle ID to the
verified profile UUID with the pinned identity or fingerprint, and exports
without `-allowProvisioningUpdates` or App Store Connect auth arguments. The
normal archive freshness, bundle/version/team, IPA distribution, and
failure-cleanup checks still run. Unsetting both variables returns to
automatic export byte for byte.

## What validation rejects

Partial configuration (only one variable set), a profile value that looks
like a path or a malformed UUID, a non-distribution identity or malformed
fingerprint, an expired or missing installed profile, an ambiguous name
shared by different profiles, bundle/team mismatch, provisioned devices or
`get-task-allow` true, a profile whose currently valid certificates do not
include the pinned identity or fingerprint, and a missing Apple sign-in
grant when the archive requires it. Errors name the variable, never the
value.
