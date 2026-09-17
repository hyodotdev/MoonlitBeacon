#!/usr/bin/env bash
# Seed credentials on a new machine in one pass. Values are never printed.
#
#     scripts/secrets-bootstrap.sh
#
# Paste each value from the password manager when prompted. They go into
# Keychain. After that, `source scripts/secrets.sh` is enough.
#
# Press Enter on an empty value to skip that item.
set -euo pipefail

ask() {                               # label service account
  local label="$1" svc="$2" acct="$3" val
  printf '%s: ' "$label"
  read -r -s val; echo
  if [ -z "$val" ]; then
    echo "  skipped"
    return 0
  fi
  security add-generic-password -U -s "$svc" -a "$acct" -w "$val"
  echo "  stored in Keychain"
}

echo "Typed values are hidden. Press Enter to skip."
echo
ask "Ludo API key"            dev.ludo.ai                   MoonlitBeacon
ask "IAPKit publishable key"  dev.openiap.kit.moonlitbeacon 'MoonlitBeacon Mobile'
ask "IAPKit admin key"        dev.openiap.kit.moonlitbeacon 'MoonlitBeacon Admin'
ask "App Store Connect key id"    dev.apple.asc.moonlitbeacon 'ASC Key ID'
ask "App Store Connect issuer id" dev.apple.asc.moonlitbeacon 'ASC Issuer ID'

echo
echo "Place these two files yourself (mode 600):"
echo "  ~/.secrets/AuthKey.p8                  App Store Connect private key"
echo "  ~/.secrets/play-service-account.json   Play upload service account"
echo
echo "The Android keystore file is itself a credential."
echo "Download it from the admin attachment and put it where export_credentials.cfg points."
echo "If this password leaks it cannot be rotated — do not copy it into a file."
echo
echo "Verify: source scripts/secrets.sh"
