#!/usr/bin/env bash
# Bumps versionCode (androidApp/build.gradle.kts) then builds a debug APK, mirroring the
# iOS archive scripts' "bump build number on every build" convention.
#
# Requires a JDK — Android Studio's bundled JBR works and needs no separate install:
#   export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
#
# Usage (from repo root):
#   ./scripts/build_android.sh
#
# Output: androidApp/build/outputs/apk/debug/androidApp-debug.apk

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GRADLE_FILE="androidApp/build.gradle.kts"
CURRENT=$(grep -oE 'versionCode = [0-9]+' "$GRADLE_FILE" | grep -oE '[0-9]+')
NEXT=$((CURRENT + 1))

echo "==> Bumping versionCode ($CURRENT -> $NEXT)…"
sed -i '' "s/versionCode = $CURRENT/versionCode = $NEXT/" "$GRADLE_FILE"

echo "==> Building debug APK…"
./gradlew :androidApp:assembleDebug

APK="androidApp/build/outputs/apk/debug/androidApp-debug.apk"
echo "Done. APK: $APK"
echo "versionCode bumped to $NEXT in $GRADLE_FILE — commit it if you want that tracked."
