#!/usr/bin/env bash
# Build `.env` from values already in Keychain.
#
#     ./scripts/secrets-materialize.sh
#
# `scripts/secrets.sh` only exports into the current shell, so every new
# terminal needed another source. `scripts/lib/load-env.mjs` now reads
# `.env`, so one materialize makes `pnpm` commands work. This script does
# the copy, and **values never appear on screen or in shell history.**
#
# If Keychain is still empty, fill it with `scripts/secrets-bootstrap.sh` first.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=.env

if [ -e "$OUT" ]; then
  printf '%s already exists. Overwrite? [y/N] ' "$OUT"
  read -r reply
  case "$reply" in
    y|Y) ;;
    *) echo 'Leaving it unchanged'; exit 0 ;;
  esac
fi

kc() {                                # service account → value (empty if missing)
  security find-generic-password -s "$1" -a "$2" -w 2>/dev/null || true
}

# Create an empty mode-600 file first. Lock it before writing so nothing
# else can read a half-written secret.
umask 177
: >"$OUT"

emit() {                              # name value — keep the name even if value is empty
  if [ -n "$2" ]; then
    printf '%s=%s\n' "$1" "$2" >>"$OUT"
  else
    printf '%s=\n' "$1" >>"$OUT"
    missing+=("$1")
  fi
}

missing=()

{
  echo '# File created from Keychain by scripts/secrets-materialize.sh.'
  echo '# Not committed (.gitignore). Names and descriptions live in .env.example.'
} >>"$OUT"

emit GODOT_ANDROID_KEYSTORE_RELEASE_PATH \
  "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$HOME/Library/Application Support/MoonlitBeacon/signing/moonlit-beacon-upload.jks}"
emit GODOT_ANDROID_KEYSTORE_RELEASE_USER \
  "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-moonlitbeacon-upload}"
emit GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD \
  "$(kc dev.moonlitbeacon.android-signing moonlitbeacon-upload)"

emit MOONLIT_ASC_KEY_ID    "$(kc dev.apple.asc.moonlitbeacon 'ASC Key ID')"
emit MOONLIT_ASC_ISSUER_ID "$(kc dev.apple.asc.moonlitbeacon 'ASC Issuer ID')"
emit MOONLIT_ASC_PRIVATE_KEY "${MOONLIT_ASC_PRIVATE_KEY:-$HOME/.secrets/AuthKey.p8}"
emit GOOGLE_APPLICATION_CREDENTIALS \
  "${GOOGLE_APPLICATION_CREDENTIALS:-$HOME/.secrets/play-service-account.json}"

emit IAPKIT_API_KEY   "$(kc dev.openiap.kit.moonlitbeacon 'MoonlitBeacon Mobile')"
emit IAPKIT_ADMIN_KEY "$(kc dev.openiap.kit.moonlitbeacon 'MoonlitBeacon Admin')"
emit LUDO_API_KEY     "$(kc dev.ludo.ai MoonlitBeacon)"

chmod 600 "$OUT"

if [ ${#missing[@]} -eq 0 ]; then
  echo "Wrote $OUT — 10 entries, mode 600"
else
  echo "Wrote $OUT — mode 600"
  echo "Still empty: ${missing[*]}"
  echo 'Fill with: scripts/secrets-bootstrap.sh'
fi
