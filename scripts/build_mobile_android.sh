#!/usr/bin/env bash
# Builds a release-signed Android APK of the React Native app (mobile/), signed with the project's release
# keystore so it installs as an upgrade over the Kotlin app.
#
# The version code is `expo.android.versionCode` in mobile/app.json. Bump it by hand before running when you
# want a new one (it must only ever go up; the Kotlin app's last release was 3).
#
# Requires keystore/setbuddy-release.jks + keystore.properties at the repo root (both gitignored). Without
# them the build still succeeds but is signed with the debug key, which will NOT install over a released app —
# this script stops in that case rather than hand you the wrong file.
#
# Requires a JDK — Android Studio's bundled one works:
#   export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
#
# Usage (from repo root):
#   ./scripts/build_mobile_android.sh
#
# Output: build/apk-mobile/Set Buddy <version> (<versionCode>).apk

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/apk-mobile"

if [[ ! -f "$ROOT/keystore.properties" ]]; then
  echo "keystore.properties not found at the repo root — a release build would be signed with the debug key." >&2
  echo "Restore keystore/setbuddy-release.jks and keystore.properties, then run this again." >&2
  exit 1
fi

: "${JAVA_HOME:=/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
export JAVA_HOME ANDROID_HOME

cd "$ROOT/mobile"

echo "==> Generating the native Android project…"
npx expo prebuild --platform android --no-install

echo "==> Building the release APK…"
(cd android && ./gradlew :app:assembleRelease --console=plain -q)

VERSION="$(node -p "require('./app.json').expo.version")"
CODE="$(node -p "require('./app.json').expo.android.versionCode")"
mkdir -p "$OUT"
APK="$OUT/Set Buddy $VERSION ($CODE).apk"
cp android/app/build/outputs/apk/release/app-release.apk "$APK"

echo "Done. APK: $APK"
