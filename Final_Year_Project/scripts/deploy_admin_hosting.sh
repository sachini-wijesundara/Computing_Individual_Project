#!/usr/bin/env bash
# Build and deploy ONLY the admin web panel to Firebase Hosting.
# URL: https://finalyearproject-45e32-admin.web.app
# Usage:  cd Final_Year_Project && ./scripts/deploy_admin_hosting.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

echo "==> flutter build web (admin) → build/web_admin"
flutter build web -t lib/main_admin_web.dart --release -o build/web_admin

echo "==> firebase deploy --only hosting:admin"
firebase deploy --only hosting:admin

echo "Admin panel: https://finalyearproject-45e32-admin.web.app"
