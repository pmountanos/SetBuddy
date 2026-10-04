#!/usr/bin/env bash
# Builds the React Native app (mobile/) for a real iPhone: regenerates the native iOS project, archives a
# Release build, and exports an ad-hoc signed .ipa — the same kind of file the native app's
# archive_and_export_production_ipa.sh produced, installable on devices registered with the team.
#
# The build number is `expo.ios.buildNumber` in mobile/app.json. Bump it by hand before running when you want
# a new build number (it must only ever go up; the native app's last build was 14).
#
# Requires Node (for Expo), CocoaPods, and Xcode signed in to the team in mobile/app.json (`ios.appleTeamId`).
#
# Usage (from repo root):
#   ./scripts/archive_mobile_ios.sh
#
# Output: build/ipa-mobile/Set Buddy <version> (<build>) ad-hoc.ipa
# Install on a connected iPhone with:
#   xcrun devicectl device install app --device <device id> "<that .ipa>"

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$ROOT/build/SetBuddy_mobile.xcarchive"
EXPORT="$ROOT/build/ipa-mobile"
PLIST="$ROOT/build/ExportOptions-AdHoc.plist"

cd "$ROOT/mobile"

echo "==> Generating the native iOS project…"
npx expo prebuild --platform ios

echo "==> Archiving (Release, iOS device)…"
xcodebuild archive \
  -workspace ios/SetBuddy.xcworkspace \
  -scheme SetBuddy \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  -quiet

echo "==> Exporting ad-hoc .ipa…"
rm -rf "$EXPORT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist")"
IPA_ORIGINAL="$(find "$EXPORT" -maxdepth 1 -name '*.ipa' | head -1)"
IPA_VERSIONED="$EXPORT/Set Buddy $VERSION ($BUILD) ad-hoc.ipa"
mv "$IPA_ORIGINAL" "$IPA_VERSIONED"

echo "Done. IPA: $IPA_VERSIONED"
