#!/usr/bin/env bash
# Generates the Android release signing keystore (keystore/setbuddy-release.jks) and its
# keystore.properties (both gitignored — never commit either). Safe to re-run: refuses to
# overwrite an existing keystore, since regenerating changes the app's signing identity and
# a device can't upgrade-install a differently-signed APK over an existing install without
# uninstalling first.
#
# Back up keystore/setbuddy-release.jks and keystore.properties somewhere safe outside this
# repo (password manager attachment, external drive) — losing them means future release builds
# can't be signed to match earlier ones, and anyone who installed a release build would need to
# uninstall before installing a re-signed one.
#
# Usage (from repo root):
#   ./scripts/generate_release_keystore.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYSTORE_DIR="$ROOT/keystore"
KEYSTORE_FILE="$KEYSTORE_DIR/setbuddy-release.jks"
PROPERTIES_FILE="$ROOT/keystore.properties"
KEYTOOL="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"

if [[ -f "$KEYSTORE_FILE" ]]; then
  echo "Keystore already exists at $KEYSTORE_FILE — not overwriting." >&2
  echo "Delete it first if you really want a new signing identity (this breaks upgrade installs)." >&2
  exit 1
fi

if [[ ! -x "$KEYTOOL" ]]; then
  echo "keytool not found at $KEYTOOL — pass a different JDK's keytool path or install Android Studio." >&2
  exit 1
fi

mkdir -p "$KEYSTORE_DIR"

STORE_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"

"$KEYTOOL" -genkeypair -v \
  -keystore "$KEYSTORE_FILE" \
  -alias setbuddy \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$STORE_PASSWORD" \
  -dname "CN=Set Buddy, OU=net.mountanos.setbuddy, O=Set Buddy, L=Unknown, ST=Unknown, C=US"

cat > "$PROPERTIES_FILE" <<EOF
storeFile=keystore/setbuddy-release.jks
storePassword=$STORE_PASSWORD
keyAlias=setbuddy
keyPassword=$STORE_PASSWORD
EOF
chmod 600 "$PROPERTIES_FILE" "$KEYSTORE_FILE"

echo
echo "Done. Keystore: $KEYSTORE_FILE"
echo "Credentials:    $PROPERTIES_FILE (gitignored — back both files up somewhere safe)"
