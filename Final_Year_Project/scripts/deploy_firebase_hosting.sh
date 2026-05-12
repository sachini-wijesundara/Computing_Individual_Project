#!/usr/bin/env bash
# Build admin + delivery Flutter web apps and deploy only those Firebase Hosting targets.
# Requires: firebase CLI, `firebase login`, and Hosting sites (see docs/HOSTING.md).
# Usage:  cd Final_Year_Project && ./scripts/deploy_firebase_hosting.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
  GEMINI_API_KEY="${GEMINI_API_KEY%$'\r'}"
  OPENROUTER_API_KEY="${OPENROUTER_API_KEY%$'\r'}"
  OPENROUTER_MODEL="${OPENROUTER_MODEL%$'\r'}"
fi

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

echo "==> Admin web (lib/main_admin_web.dart) → build/web_admin"
flutter build web -t lib/main_admin_web.dart --release "${DART_DEFINES[@]}" -o build/web_admin

echo "==> Delivery staff web (lib/main_delivery_staff.dart) → build/web_delivery"
flutter build web -t lib/main_delivery_staff.dart --release "${DART_DEFINES[@]}" -o build/web_delivery

echo "==> firebase deploy --only hosting:admin,hosting:delivery"
firebase deploy --only hosting:admin,hosting:delivery

echo "Done. Check the Hosting URLs in the output above."
