#!/usr/bin/env bash
set -euo pipefail

FLUTTER_HOME="${HOME}/flutter"

if [ -z "${API_BASE_URL:-}" ]; then
  echo "API_BASE_URL is required. Set it in Vercel to your Render backend URL." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  git clone https://github.com/flutter/flutter.git --branch stable --depth 1 "${FLUTTER_HOME}"
  export PATH="${FLUTTER_HOME}/bin:${PATH}"
else
  export PATH="${PATH}:${FLUTTER_HOME}/bin"
fi

flutter --version
flutter config --enable-web
flutter precache --web
flutter pub get
flutter build web \
  --release \
  --pwa-strategy=offline-first \
  --dart-define=API_BASE_URL="${API_BASE_URL}"

test -f build/web/index.html
