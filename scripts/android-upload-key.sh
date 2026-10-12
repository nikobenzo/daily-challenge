#!/bin/bash
# Creates the Google Play upload key for the Android app, once, outside this repository.
# Owner-run: see docs/play-release.md. Google re-signs every release with the app signing key
# it keeps (Play App Signing); this upload key only proves an upload came from the owner, and
# Google can reset it if it is ever lost.
#
#   bash scripts/android-upload-key.sh [keystore path]
#
# The default path is ~/.android-keys/daily-challenge-upload.jks. keytool asks for the password
# itself, so it never appears in the shell history or the process list. The script refuses a
# path inside the repository and never overwrites an existing keystore.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
STORE="${1:-$HOME/.android-keys/daily-challenge-upload.jks}"
ALIAS=upload

if ! command -v keytool >/dev/null; then
  echo 'keytool was not found. Install a JDK first (docs/android.md, Toolchain).' >&2
  exit 1
fi

refuse_inside_repository() {
  case "$1/" in
    "$ROOT"/*) echo "Refusing to create the upload key inside the repository ($1). Choose a path outside it." >&2; exit 1 ;;
  esac
}
case "$STORE" in /*) ;; *) STORE="$PWD/$STORE" ;; esac
refuse_inside_repository "$(dirname "$STORE")"
mkdir -p "$(dirname "$STORE")"
DIR="$(cd "$(dirname "$STORE")" && pwd -P)"
STORE="$DIR/$(basename "$STORE")"
refuse_inside_repository "$DIR"
if [[ -e "$STORE" ]]; then
  echo "$STORE already exists; not overwriting it. Keep using it, or choose another path." >&2
  exit 1
fi
chmod 700 "$DIR"

echo "Creating the upload key in $STORE"
echo 'Choose a strong password (at least 6 characters) and save it in your password manager first.'
umask 077
keytool -genkeypair -v \
  -keystore "$STORE" -storetype PKCS12 \
  -alias "$ALIAS" -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Mykola Yakovetskyi, O=Daily Challenge"
chmod 600 "$STORE"

cat <<EOF

Done: $STORE (alias "$ALIAS").

Back it up now: copy the file to an encrypted backup (for example your password manager's
file attachments) and keep the password next to it. Without both you cannot upload updates
until Google resets the upload key, which takes days.

So Gradle can sign release builds, add these lines to ~/.gradle/gradle.properties (outside the
repository) and run chmod 600 ~/.gradle/gradle.properties:

DC_UPLOAD_STORE_FILE=$STORE
DC_UPLOAD_KEY_ALIAS=$ALIAS
DC_UPLOAD_STORE_PASSWORD=<the password you just chose>

Or export the same three names as environment variables in the shell that builds.
EOF
