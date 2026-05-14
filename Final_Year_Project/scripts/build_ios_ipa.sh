#!/usr/bin/env bash
# Build a release IPA for App Store Connect / TestFlight.
# One-time in Xcode: open ios/Runner.xcworkspace → Signing & Capabilities → Team + bundle id.
# Usage:  cd Final_Year_Project && ./scripts/build_ios_ipa.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> flutter build ipa --release"
flutter build ipa --release

echo ""
echo "IPA output (upload with Transporter or Xcode Organizer):"
ls -la build/ios/ipa/*.ipa 2>/dev/null || echo "(no ipa found — fix signing in Xcode and retry)"
