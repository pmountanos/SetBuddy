#!/usr/bin/env bash
# Builds a release-signed Android APK (net.mountanos.setbuddy), bumping versionCode first —
# mirrors the iOS production script's "bump build number on every build" convention.
#
# Requires keystore/setbuddy-release.jks + keystore.properties (gitignored) — run
# ./scripts/generate_release_keystore.sh once first if you don't have them yet. Without them
# the underlying Gradle build still succeeds but produces an *unsigned* APK, which Android
# refuses to install.
#
# Requires a JDK — Android Studio's bundled JBR works and needs no separate install:
#   export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
#
# Usage (from repo root):
#   ./scripts/build_android_release.sh
#
# Output: androidApp/build/outputs/apk/release/androidApp-release.apk

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f "$ROOT/keystore.properties" ]]; then
  echo "Warning: keystore.properties not found — the release APK will be built unsigned and" >&2
  echo "will not install on a device. Run ./scripts/generate_release_keystore.sh first." >&2
fi

GRADLE_FILE="androidApp/build.gradle.kts"
CURRENT=$(grep -oE 'versionCode = [0-9]+' "$GRADLE_FILE" | grep -oE '[0-9]+')
NEXT=$((CURRENT + 1))

echo "==> Bumping versionCode ($CURRENT -> $NEXT)…"
sed -i '' "s/versionCode = $CURRENT/versionCode = $NEXT/" "$GRADLE_FILE"

echo "==> Building release APK…"
./gradlew :androidApp:assembleRelease

APK="androidApp/build/outputs/apk/release/androidApp-release.apk"
echo "Done. APK: $APK"
echo "versionCode bumped to $NEXT in $GRADLE_FILE — commit it if you want that tracked."
