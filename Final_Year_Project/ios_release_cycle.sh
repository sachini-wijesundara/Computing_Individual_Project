#!/usr/bin/env bash
set -euo pipefail

# One-command iOS release cycle:
# 1) Build Release
# 2) Install to device
# 3) Launch app
#
# Usage:
#   ./ios_release_cycle.sh
#   ./ios_release_cycle.sh <device_udid>
#
# For faster Debug runs while iterating, use: ./ios_quick_run.sh
#
# Defaults are set for this project/device and can be overridden by args/env.

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$PROJECT_ROOT/ios"

DEVICE_ID="${1:-${IOS_DEVICE_ID:-00008140-001474961113801C}}"
BUNDLE_ID="${IOS_BUNDLE_ID:-com.example.virtualTryonMakeup}"
SCHEME="${IOS_SCHEME:-Runner}"
WORKSPACE="${IOS_WORKSPACE:-Runner.xcworkspace}"
CONFIG="${IOS_CONFIG:-Release}"

echo "==> Building $SCHEME ($CONFIG) for device: $DEVICE_ID"
cd "$IOS_DIR"

# Clear stale xcodebuilds to avoid build-db locks.
pkill -f xcodebuild 2>/dev/null || true
sleep 1

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  build

APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/Runner-bnuaiugucdqexrhlfdgupfihdehm/Build/Products/${CONFIG}-iphoneos/Runner.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Built app not found at: $APP_PATH"
  exit 1
fi

echo "==> Installing app"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "==> Launching app"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ID" "$BUNDLE_ID"

echo "==> Done"
