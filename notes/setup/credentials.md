# Credentials — what is needed and how to fill them on a new machine

**Do not write values in this document.** Record only names, uses, storage
locations, and recovery steps. Keep values in a password manager (1Password
and similar) and put them on a new machine in the place the "Storage" column
points to. When pasting into Notion, copy this table only and attach values
as manager links.

## Table

| Name | Used for | Storage | If missing |
| --- | --- | --- | --- |
| Ludo API key | Sprite/audio generation MCP | Keychain `dev.ludo.ai` / `MoonlitBeacon` | AI asset tools do not attach |
| `IAPKIT_API_KEY` (publishable) | `pnpm android:bundle`, iOS export | Env var → Keychain `dev.openiap.kit.moonlitbeacon` / `MoonlitBeacon Mobile` | Store builds fail |
| IAPKit admin key | `${IAPKIT_ADMIN_KEY}` in `.mcp.json` | Env var only (do not put it in a file) | IAP admin MCP does not connect |
| Android keystore + password | Signing release APK/AAB | Keystore `~/Library/Application Support/MoonlitBeacon/signing/moonlit-beacon-upload.jks` (mode 600) · password Keychain `dev.moonlitbeacon.android-signing` / `moonlitbeacon-upload` | Signed builds impossible |
| `MOONLIT_ASC_KEY_ID` / `MOONLIT_ASC_ISSUER_ID` | App Store Connect API | Env vars | `ios:validate` · `ios:upload` impossible |
| `MOONLIT_ASC_PRIVATE_KEY` (absolute `.p8` path) | App Store Connect API | File **outside** the repo, mode `600` | Same as above |
| Google Play service-account JSON | Play upload/review scripts | File outside the repo pointed to by `GOOGLE_APPLICATION_CREDENTIALS` | Play automation impossible |

## Android signing does not require exporting env vars

`scripts/lib/android-release-signing.mjs` finds macOS defaults itself.
A release build is still signed if all three variables are unset.

| Variable | Value used when not exported |
| --- | --- |
| `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` | `~/Library/Application Support/MoonlitBeacon/signing/moonlit-beacon-upload.jks` |
| `GODOT_ANDROID_KEYSTORE_RELEASE_USER` | alias `moonlitbeacon-upload` |
| `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` | Keychain `dev.moonlitbeacon.android-signing` / `moonlitbeacon-upload` |

If you set env vars, those win. Linux and CI have no default paths, so all
three must be provided.

**`apps/game/.godot/export_credentials.cfg` is unrelated to this path.**
Signing still works without that file. It is where the Godot editor stores
credentials for a direct export — AGENTS.md's "do not commit" rule still
applies.

Check:

```bash
node -e "import('./scripts/lib/android-release-signing.mjs').then(m=>{
  const r = m.resolveAndroidReleaseSigning({ root: process.cwd() });
  console.log(r.GODOT_ANDROID_KEYSTORE_RELEASE_USER,
              r.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD ? 'password OK' : 'password missing');
});"
```

**This keystore is the most dangerous credential in this repository.** The
file and the password live only on the signing machine. If they leak, someone
else can ship signed updates under this app's name; if they are lost, this
app can never be updated. Play treats the signing key as the app's identity,
so neither side can be undone — back it up in the password manager as a
**file attachment**.

## Load in one line

```bash
source scripts/secrets.sh
```

Reads from Keychain every time and exports env vars. **Do not create a
plaintext file.** Missing items report the name only and never print the
value.

It is tempting to collect everything in one `.env`. Do not. That file
spreads through backups, cloud sync, and editor indexes, and it mixes in
**secrets that cannot be revoked if leaked** (the Android keystore password).
Other keys can be revoked and reissued; the signing key is Play's app
identity, so it cannot be undone.

`.gitignore` blocks `.env` · `.env.*` · `.secrets/` · `*.p8` · `*.jks` ·
`*.keystore` · `*service-account*.json`. Previously only `.env.local` was
blocked, so creating `.env` could have been committed as-is.

## New-machine setup

```bash
scripts/secrets-bootstrap.sh
```

Copy values from the password manager and paste when prompted; they go into
Keychain. Input is not shown on screen, and Enter on an empty value skips.
Place the two files (`AuthKey.p8` · `play-service-account.json`) yourself in
`~/.secrets/` with mode 600.

### By hand

```bash
# 1) Ludo (AI asset generation)
security add-generic-password -U -s dev.ludo.ai -a MoonlitBeacon -w '<LUDO_API_KEY>'

# 2) IAPKit publishable
security add-generic-password -U -s dev.openiap.kit.moonlitbeacon \
  -a 'MoonlitBeacon Mobile' -w '<IAPKIT_API_KEY>'

# 3) App Store Connect (in the shell profile)
export MOONLIT_ASC_KEY_ID=...
export MOONLIT_ASC_ISSUER_ID=...
export MOONLIT_ASC_PRIVATE_KEY="$HOME/.secrets/AuthKey_XXXX.p8"   # chmod 600

# 4) Play service account
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.secrets/play-service-account.json"
```

The keystore file itself is the credential. Keep it as a **document
attachment** in the password manager, and on a new machine download it to the
path `apps/game/.godot/export_credentials.cfg` points to. Do not commit
`.godot/`.

## MCP connection (shared by three tools)

Do not write keys in a config file. The `~/.local/bin/ludo-mcp` wrapper reads
Keychain and passes them to `mcp-remote` as env vars — the value does not
appear in `ps` either.

```toml
# ~/.grok/config.toml, ~/.codex/config.toml
# TOML does not expand $HOME or ~. Put the absolute path of the wrapper.
[mcp_servers.ludo]
command = "/absolute/path/to/ludo-mcp"
```

```bash
# Claude Code
claude mcp add ludo "$HOME/.local/bin/ludo-mcp"
```

On Linux/CI, where there is no Keychain, set `LUDO_API_KEY` and the wrapper
uses that first.

## Rules

- Do not paste values into Notion, Slack, issues, or commits. Treat a secret
  that has been posted once as remaining in caches and indexes even after
  deletion.
- New-machine setup should finish with only this document and the password
  manager.
- If a key may have leaked, revoke (rotate) it at the issuer first, then
  overwrite the slots in this table with the new values.
