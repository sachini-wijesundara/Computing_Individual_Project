#!/usr/bin/env bash
# One-time: create extra Firebase Hosting sites for admin + delivery web apps.
# Targets in .firebaserc already point to these site IDs — only the sites must exist.
# Usage:  firebase login   then   ./scripts/setup_firebase_hosting_sites.sh
set -euo pipefail
PROJECT="finalyearproject-45e32"

echo "Creating Hosting sites (errors OK if sites already exist)…"
firebase hosting:sites:create "${PROJECT}-admin" --project "$PROJECT" || true
firebase hosting:sites:create "${PROJECT}-delivery" --project "$PROJECT" || true

echo "Done. Deploy with:  ./scripts/deploy_firebase_hosting.sh"
