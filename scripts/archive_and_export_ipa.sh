#!/usr/bin/env bash
# Development signing — Apple Development certificate + development provisioning.
#
# **Simplest path (no IPA):** Open `Set Buddy.xcodeproj` in Xcode, connect your
# iPhone, choose it as the run destination, **Product → Run** (⌘R). Signing &
# Capabilities should show **Automatically manage signing** and your team
# (paid team or **Personal Team** while enrollment is pending). If Xcode shows
# signing errors, fix them there first. The team ID is not stored in the project:
# this script reads it from signing.local.env (gitignored — copy
# signing.local.env.example) or the APPLE_TEAM_ID variable.
#
# **This script:** bumps the build number (`CURRENT_PROJECT_VERSION`, via `agvtool`,
# all targets) in the Xcode project, archives **Debug**, and exports a **development**
# .ipa (same signing type as Run-to-device). Use when you want a file to sideload
# instead of running from Xcode. Commit the project.pbxproj bump if you want the
# build number change tracked in git.
#
# Prerequisite: device registered with your team (plug in USB → trust → build
# once with the device selected, or add UDID under developer.apple.com → Devices).
#
# Usage (from repo root):
#   ./scripts/archive_and_export_ipa.sh
#
# Output: build/ipa/Set Buddy <version> (<build>).ipa — Xcode Devices window
# (drag .ipa), Apple Configurator 2, etc. Version/build come from the archive
# (MARKETING_VERSION / CURRENT_PROJECT_VERSION in the Xcode project).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ_DIR="$ROOT"
ARCHIVE="$ROOT/build/Set_Buddy.xcarchive"
EXPORT="$ROOT/build/ipa"
source "$ROOT/scripts/apple_team.sh"
require_apple_team
PLIST="$(export_options_with_team "$ROOT/build/ExportOptions-Development.plist")"

mkdir -p "$ROOT/build"
cd "$PROJ_DIR"

echo "==> Bumping build number (CURRENT_PROJECT_VERSION, all targets)…"
# The trailing "Cannot find ... YES" line below is a known-harmless agvtool quirk on projects
# with no physical Info.plist (GENERATE_INFOPLIST_FILE = YES) — it still fails to find a plist
# to hand-edit for that step, but the actual project.pbxproj build-setting bump (what this
# project's synthesized Info.plist and this script both read from) already succeeded above it.
xcrun agvtool -noscm next-version -all

echo "==> Archiving (Debug, iOS device, development signing)…"
xcodebuild archive \
  -scheme "Set Buddy" \
  -project "Set Buddy.xcodeproj" \
  -configuration Debug \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID"

echo "==> Exporting Development .ipa…"
rm -rf "$EXPORT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$PLIST"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist")"
IPA_ORIGINAL="$(find "$EXPORT" -maxdepth 1 -name '*.ipa' | head -1)"
IPA_VERSIONED="$EXPORT/Set Buddy $VERSION ($BUILD).ipa"
mv "$IPA_ORIGINAL" "$IPA_VERSIONED"

echo "Done. IPA: $IPA_VERSIONED"
ls -la "$EXPORT"
echo
echo "Build number bumped to $BUILD in the Xcode project — commit \"Set Buddy.xcodeproj/project.pbxproj\" if you want that tracked."
