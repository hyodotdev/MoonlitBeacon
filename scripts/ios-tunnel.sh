#!/usr/bin/env bash
# Keep an iOS 17+ RemoteXPC tunnel up for device capture.
#
#     sudo ./scripts/ios-tunnel.sh
#
# From iOS 17 onward screenshotr lives behind RemoteXPC, so a live tunnel is
# required to screenshot a physical device. Creating the tunnel makes a TUN
# interface, which **needs root** — a person must run this with sudo.
#
# Why a bare `pymobiledevice3 remote start-tunnel` keeps dying:
#
#   1. It is a one-shot command, so closing the terminal or Ctrl-C kills it.
#   2. If the iPad locks or USB blips, it exits and does not come back.
#   3. Failures print one line and exit quietly, so capture runs against a
#      tunnel you thought was still up.
#
# This script restarts on death, logs to a file, and keeps the current RSD
# address and port visible on screen.

set -uo pipefail

PMD="${PMD:-$HOME/.local/bin/pymobiledevice3}"
LOG_DIR="${TMPDIR:-/tmp}/moonlit-ios-tunnel"
LOG="$LOG_DIR/tunnel.log"

if [ "$(id -u)" -ne 0 ]; then
  echo "Root is required. Run it like this:"
  echo "  sudo $0"
  exit 1
fi

if [ ! -x "$PMD" ]; then
  echo "Could not find pymobiledevice3: $PMD"
  echo "Set the PMD environment variable to the binary path."
  exit 1
fi

mkdir -p "$LOG_DIR"

cleanup() {
  echo ""
  echo "Bringing the tunnel down."
  exit 0
}
trap cleanup INT TERM

echo "Starting the RemoteXPC tunnel. Leave this window open while capturing."
echo "Log: $LOG"
echo "Stop with Ctrl-C."
echo ""

# `tunneld` is daemon mode. It finds devices itself and reattaches after
# unplug/replug. Unlike `start-tunnel` it can serve several devices at once,
# so switching between iPad and iPhone does not need a restart.
while true; do
  echo "[$(date '+%H:%M:%S')] tunneld start" | tee -a "$LOG"
  "$PMD" remote tunneld 2>&1 | tee -a "$LOG"
  code=$?
  echo "[$(date '+%H:%M:%S')] tunneld exit (code=$code) — restarting in 3s" | tee -a "$LOG"
  sleep 3
done
