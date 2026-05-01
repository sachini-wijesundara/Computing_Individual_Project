#!/usr/bin/env bash
set -euo pipefail
# Debug build + install + attach. Prefer USB: wireless iOS debug is slow and can stall “Installing and launching…”.
# Usage: ./ios_quick_run.sh   or   ./ios_quick_run.sh <device_udid>
# Faster iteration after first launch: use ./ios_fast_dev.sh (attach-first).
# After `flutter pub get`, `--no-pub` skips dependency resolution each run (~10–30s). Drop it if you changed pubspec.yaml.
#
# Secrets: copy `.env.example` → `.env` in this folder (gitignored). This script
# sources `.env` and passes values as --dart-define.
#   GEMINI_API_KEY     — Google AI / Gemini (chat + skin & hair vision)
#   OPENROUTER_API_KEY — Hair Style Matcher
#   OPENROUTER_MODEL   — optional
#
# If install/launch sits many minutes or ends with “Connection closed” / service protocol errors:
#   • iPhone: Settings → Developer → turn off Wireless Debugging; keep the phone unlocked during install.
#   • Xcode: Window → Devices → your iPhone → uncheck “Connect via network”.
#   • Mac: System Settings → Privacy & Security → Local Network → allow Xcode / Terminal / Cursor.
#   • See where time goes: IOS_FLUTTER_VERBOSE=1 ./ios_quick_run.sh   (adds flutter -v)
#   • Faster when Flutter sees USB: FLUTTER_DEVICE_CONNECTION=attached ./ios_quick_run.sh
cd "$(dirname "$0")"
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
  # Strip Windows CRLF so values don’t include a trailing $'\r'
  GEMINI_API_KEY="${GEMINI_API_KEY%$'\r'}"
  OPENROUTER_API_KEY="${OPENROUTER_API_KEY%$'\r'}"
  OPENROUTER_MODEL="${OPENROUTER_MODEL%$'\r'}"
fi
DEVICE="${1:-${IOS_DEVICE_ID:-00008140-001474961113801C}}"
# Stops Runner if still running so Xcode / tooling won’t keep asking to “Replace Runner?”
bash "$(dirname "$0")/ios/kill_runner_on_device.sh" "$DEVICE" || true
# Default `both` so a phone that only appears as wireless still works; use `attached` if your device shows as USB.
CONN="${FLUTTER_DEVICE_CONNECTION:-both}"
DART_DEFINES=()
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  DART_DEFINES+=(--dart-define="GEMINI_API_KEY=${GEMINI_API_KEY}")
fi
if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
  DART_DEFINES+=(--dart-define="OPENROUTER_API_KEY=${OPENROUTER_API_KEY}")
fi
if [[ -n "${OPENROUTER_MODEL:-}" ]]; then
  DART_DEFINES+=(--dart-define="OPENROUTER_MODEL=${OPENROUTER_MODEL}")
fi
# Avoid "${array[@]}" with set -u when empty (bash treats it as unbound).
if [[ "${IOS_FLUTTER_VERBOSE:-}" == "1" ]]; then
  exec flutter run -d "$DEVICE" --no-pub --device-connection "$CONN" -v "${DART_DEFINES[@]}"
else
  exec flutter run -d "$DEVICE" --no-pub --device-connection "$CONN" "${DART_DEFINES[@]}"
fi
