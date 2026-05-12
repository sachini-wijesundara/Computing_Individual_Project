#!/usr/bin/env bash
# Run from repo root: ./scripts/qa_automated.sh
# Or: bash scripts/qa_automated.sh
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
