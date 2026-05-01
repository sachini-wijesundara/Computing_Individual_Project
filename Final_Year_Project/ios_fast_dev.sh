#!/usr/bin/env bash
set -euo pipefail

# Fast iOS dev loop:
# 1) Try `flutter attach` first (no reinstall/build, usually seconds).
# 2) If attach fails, fall back to full `ios_quick_run.sh`.
#
# Usage:
#   ./ios_fast_dev.sh
#   ./ios_fast_dev.sh <device_udid>
# Env:
#   FLUTTER_DEVICE_CONNECTION=attached|both|wireless   (default: both)
#   IOS_ATTACH_TIMEOUT=8                                (seconds)
#   IOS_FLUTTER_VERBOSE=1                               (verbose attach/run)

cd "$(dirname "$0")"
DEVICE="${1:-${IOS_DEVICE_ID:-00008140-001474961113801C}}"
CONN="${FLUTTER_DEVICE_CONNECTION:-both}"
ATTACH_TIMEOUT="${IOS_ATTACH_TIMEOUT:-8}"

if [[ -f .env ]]; then
  echo "ℹ️  Changed .env (API keys)? Quit the app on the device and run ./ios_quick_run.sh —"
  echo "   flutter attach does not reinstall or refresh --dart-define values."
fi

echo "==> Fast path: trying flutter attach to device $DEVICE ..."
if [[ "${IOS_FLUTTER_VERBOSE:-}" == "1" ]]; then
  if flutter attach -d "$DEVICE" --device-connection "$CONN" --device-timeout "$ATTACH_TIMEOUT" -v; then
    exit 0
  fi
else
  if flutter attach -d "$DEVICE" --device-connection "$CONN" --device-timeout "$ATTACH_TIMEOUT"; then
    exit 0
  fi
fi

echo "==> Attach failed or app not running. Falling back to full flutter run ..."
exec ./ios_quick_run.sh "$DEVICE"
