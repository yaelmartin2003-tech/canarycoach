#!/usr/bin/env bash
set -euo pipefail

# scripts/deploy_web.sh
# Uso:
#   ./scripts/deploy_web.sh [FIREBASE_PROJECT]
# Requisitos: flutter, firebase-tools en PATH. Para CI exportar FIREBASE_TOKEN.

FIREBASE_PROJECT=${1:-}
SKIP_BUILD=${SKIP_BUILD:-false}

echo "Starting Flutter web deploy..."

if [ "$SKIP_BUILD" != "true" ]; then
  echo "flutter pub get"
  flutter pub get
  echo "flutter build web --release"
  flutter build web --release
else
  echo "Skipping build (SKIP_BUILD=true)"
fi

if [ -n "$FIREBASE_PROJECT" ]; then
  echo "Deploying to Firebase Hosting (project: $FIREBASE_PROJECT)"
  firebase deploy --only hosting --project "$FIREBASE_PROJECT"
else
  echo "Deploying to Firebase Hosting (default project)"
  firebase deploy --only hosting
fi

echo "Deploy finished."
