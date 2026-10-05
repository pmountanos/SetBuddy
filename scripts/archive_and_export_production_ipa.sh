#!/usr/bin/env bash
# Build a Release archive and export a production-signed .ipa (paid Apple Developer Program).
# Bumps the build number (CURRENT_PROJECT_VERSION, via agvtool, all targets) in the Xcode
# project first. Commit the project.pbxproj bump if you want the build number change tracked.
#
# Default mode is **ad-hoc** (distribution-signed IPA for registered devices). Use **app-store**
# when App Store Connect is ready (upload only, not for drag-install).
#
# Modes:
#   ad-hoc (default) — Export method **release-testing** (replaces deprecated “ad-hoc” in
#                Export Options). Apple Distribution + Ad Hoc–style profile; installs on
#                devices registered for App ID net.mountanos.Set-Buddy.
#   app-store  — Exports for App Store Connect (method app-store-connect). IPA is for
#                Transporter / Xcode Organizer upload (TestFlight / App Store).
#
# Prerequisites:
#   • **Paid** Apple Developer Program (Personal Team / free accounts cannot use Ad Hoc distribution).
#   • Xcode → Settings → Accounts → your team → Manage Certificates: create **Apple Distribution**
#     if you do not already have one (required for Release archive + this export).
#   • Xcode → Settings → Accounts: signed in to your team (its ID goes in signing.local.env — see below).
#   • Identifiers: App ID **net.mountanos.Set-Buddy** matches the Xcode target.
# Ad-hoc: register each iPhone under https://developer.apple.com → Devices (or plug in
#   once and build/run so Xcode registers it). Automatic signing then provisions an Ad Hoc–style profile.
#   If export says **No profiles for 'net.mountanos.Set-Buddy'**: open the project in Xcode, select the
#   **Set Buddy** target → Signing & Capabilities (Release), ensure **Automatically manage signing** is on
#   and your paid team is selected; or **Product → Archive** once and use Organizer → Distribute to refresh
#   distribution profiles, then re-run this script.
# App-store: App record in App Store Connect + accepted agreements + provider access on the Apple ID.
#
# Usage (from repo root):
#   ./scripts/archive_and_export_production_ipa.sh          # ad-hoc → build/ipa-adhoc/Set Buddy <version> (<build>) ad-hoc.ipa
#   ./scripts/archive_and_export_production_ipa.sh ad-hoc
#   ./scripts/archive_and_export_production_ipa.sh app-store  # → build/ipa-appstore/Set Buddy <version> (<build>) app-store.ipa
#
# Team ID is read from signing.local.env at the repo root (gitignored — copy signing.local.env.example)
# or the APPLE_TEAM_ID variable; it is deliberately not stored in the project or the ExportOptions plists.

set -euo pipefail

METHOD="${1:-ad-hoc}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ_DIR="$ROOT"
ARCHIVE="$ROOT/build/Set_Buddy.xcarchive"

case "$METHOD" in
	app-store)
		PLIST="$ROOT/build/ExportOptions-AppStore.plist"
		EXPORT="$ROOT/build/ipa-appstore"
		;;
	ad-hoc)
		PLIST="$ROOT/build/ExportOptions-AdHoc.plist"
		EXPORT="$ROOT/build/ipa-adhoc"
		;;
	*)
		echo "Usage: $0 app-store|ad-hoc" >&2
		exit 1
		;;
esac

if [[ ! -f "$PLIST" ]]; then
	echo "Missing $PLIST" >&2
	exit 1
fi

source "$ROOT/scripts/apple_team.sh"
require_apple_team
PLIST="$(export_options_with_team "$PLIST")"

mkdir -p "$ROOT/build"
cd "$PROJ_DIR"

echo "==> Bumping build number (CURRENT_PROJECT_VERSION, all targets)…"
# The trailing "Cannot find ... YES" line below is a known-harmless agvtool quirk on projects
# with no physical Info.plist (GENERATE_INFOPLIST_FILE = YES) — it still fails to find a plist
# to hand-edit for that step, but the actual project.pbxproj build-setting bump (what this
# project's synthesized Info.plist and this script both read from) already succeeded above it.
xcrun agvtool -noscm next-version -all

echo "==> Archiving (Release, generic iOS, production signing)…"
xcodebuild archive \
	-scheme "Set Buddy" \
	-project "Set Buddy.xcodeproj" \
	-configuration Release \
	-archivePath "$ARCHIVE" \
	-destination 'generic/platform=iOS' \
	-allowProvisioningUpdates \
	DEVELOPMENT_TEAM="$APPLE_TEAM_ID"

echo "==> Exporting ($METHOD) .ipa…"
rm -rf "$EXPORT"
xcodebuild -exportArchive \
	-archivePath "$ARCHIVE" \
	-exportPath "$EXPORT" \
	-exportOptionsPlist "$PLIST"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist")"
IPA_ORIGINAL="$(find "$EXPORT" -maxdepth 1 -name '*.ipa' | head -1)"
IPA_VERSIONED="$EXPORT/Set Buddy $VERSION ($BUILD) $METHOD.ipa"
mv "$IPA_ORIGINAL" "$IPA_VERSIONED"

echo "Done. IPA: $IPA_VERSIONED"
ls -la "$EXPORT"
echo
echo "Build number bumped to $BUILD in the Xcode project — commit \"Set Buddy.xcodeproj/project.pbxproj\" if you want that tracked."
