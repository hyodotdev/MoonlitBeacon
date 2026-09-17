#!/usr/bin/env bash
# Export every credential this repo uses into the current environment.
#
#     source scripts/secrets.sh
#
# **Do not write a plaintext file.** Values are read from Keychain each time.
# A dropped file rides backups, sync, and editor indexes, and this set
# includes a secret that cannot be rotated (the Android keystore).
#
# On Linux and CI, where there is no Keychain, leave already-exported values.
#
# Missing items are named only. Values are never printed.

_moonlit_kc() {                       # service account → value (empty if missing)
  security find-generic-password -s "$1" -a "$2" -w 2>/dev/null || true
}

_moonlit_set() {                      # variable-name service account
  local var="$1" svc="$2" acct="$3" cur val
  cur="$(eval "printf '%s' \"\${$var:-}\"")"
  [ -n "$cur" ] && return 0           # do not overwrite an existing value
  val="$(_moonlit_kc "$svc" "$acct")"
  [ -z "$val" ] && return 1
  export "$var=$val"
}

_moonlit_missing=()

_moonlit_set LUDO_API_KEY   dev.ludo.ai                     MoonlitBeacon            || _moonlit_missing+=("LUDO_API_KEY")
_moonlit_set IAPKIT_API_KEY dev.openiap.kit.moonlitbeacon   'MoonlitBeacon Mobile'   || _moonlit_missing+=("IAPKIT_API_KEY")
_moonlit_set IAPKIT_ADMIN_KEY dev.openiap.kit.moonlitbeacon 'MoonlitBeacon Admin'    || _moonlit_missing+=("IAPKIT_ADMIN_KEY")
_moonlit_set MOONLIT_ASC_KEY_ID    dev.apple.asc.moonlitbeacon 'ASC Key ID'          || _moonlit_missing+=("MOONLIT_ASC_KEY_ID")
_moonlit_set MOONLIT_ASC_ISSUER_ID dev.apple.asc.moonlitbeacon 'ASC Issuer ID'       || _moonlit_missing+=("MOONLIT_ASC_ISSUER_ID")

# The two file paths are locations, not secrets. Set defaults and only check
# that the files exist.
: "${MOONLIT_ASC_PRIVATE_KEY:=$HOME/.secrets/AuthKey.p8}"
: "${GOOGLE_APPLICATION_CREDENTIALS:=$HOME/.secrets/play-service-account.json}"
export MOONLIT_ASC_PRIVATE_KEY GOOGLE_APPLICATION_CREDENTIALS
[ -f "$MOONLIT_ASC_PRIVATE_KEY" ]        || _moonlit_missing+=("MOONLIT_ASC_PRIVATE_KEY(file)")
[ -f "$GOOGLE_APPLICATION_CREDENTIALS" ] || _moonlit_missing+=("GOOGLE_APPLICATION_CREDENTIALS(file)")

if [ ${#_moonlit_missing[@]} -eq 0 ]; then
  echo "Credentials ready — 5 values + 2 files"
else
  echo "Missing: ${_moonlit_missing[*]}"
  echo "Fill with: scripts/secrets-bootstrap.sh"
fi
unset _moonlit_missing
