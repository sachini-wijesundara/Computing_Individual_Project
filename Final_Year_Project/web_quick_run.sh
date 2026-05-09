#!/usr/bin/env bash
set -euo pipefail
# Quick web run for local testing (including /admin route).
# Usage:
#   ./web_quick_run.sh
#   WEB_PORT=3001 ./web_quick_run.sh
#   WEB_DEVICE=edge ./web_quick_run.sh
#
# Optional .env in project root:
#   GEMINI_API_KEY
#   OPENROUTER_API_KEY
#   OPENROUTER_MODEL

cd "$(dirname "$0")"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
  GEMINI_API_KEY="${GEMINI_API_KEY%$'\r'}"
  OPENROUTER_API_KEY="${OPENROUTER_API_KEY%$'\r'}"
  OPENROUTER_MODEL="${OPENROUTER_MODEL%$'\r'}"
fi

WEB_DEVICE="${WEB_DEVICE:-chrome}"
WEB_PORT="${WEB_PORT:-3000}"
WEB_TARGET="${WEB_TARGET:-lib/main_admin_web.dart}"

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

exec flutter run \
  -t "$WEB_TARGET" \
  -d "$WEB_DEVICE" \
  --web-port "$WEB_PORT" \
  --no-pub \
  "${DART_DEFINES[@]}"
