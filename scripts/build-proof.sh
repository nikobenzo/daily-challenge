#!/usr/bin/env bash
# Builds build/Daily Challenge.app. By default it is Developer ID signed with the
# hardened runtime, notarized, stapled and zipped to build/DailyChallenge.zip for sharing.
#   --adhoc          ad-hoc sign for local development only (never shareable)
#   --skip-notarize  Developer ID sign and verify, but do not notarize or zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ADHOC=0
NOTARIZE=1
for arg in "$@"; do
  case "$arg" in
    --adhoc) ADHOC=1; NOTARIZE=0 ;;
    --skip-notarize) NOTARIZE=0 ;;
    *) echo "Unknown option: $arg (expected --adhoc or --skip-notarize)" >&2; exit 2 ;;
  esac
done
if [[ ! -f .env.local ]]; then
  echo 'Missing .env.local. Copy .env.example and supply the public URL/publishable key.' >&2
  exit 1
fi
# Last KEY= value in .env.local, trimmed and unquoted. The environment takes precedence.
env_local() {
  sed -n "s/^[[:space:]]*$1=//p" .env.local | tail -n 1 |
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}
SIGNING_IDENTITY="${SIGNING_IDENTITY:-$(env_local SIGNING_IDENTITY)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-$(env_local NOTARY_PROFILE)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-dc-notary}"
if (( ! ADHOC )); then
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo 'No SIGNING_IDENTITY set (environment or .env.local), so this build cannot be shared.' >&2
    echo 'Set SIGNING_IDENTITY="Developer ID Application: <Name> (<TEAMID>)", or pass --adhoc for a local development build.' >&2
    exit 1
  fi
  if ! security find-identity -v -p codesigning | grep -F "\"$SIGNING_IDENTITY\"" >/dev/null; then
    echo "Signing identity not found in the keychain: $SIGNING_IDENTITY" >&2
    echo 'Check `security find-identity -v -p codesigning`, or pass --adhoc for a local development build.' >&2
    exit 1
  fi
fi
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
# Retain the bundle identifier and Keychain service, but give the functional app
# its product name. The running older proof bundle is left untouched.
APP="$ROOT/build/Daily Challenge.app"
ZIP="$ROOT/build/DailyChallenge.zip"
# Start from a clean bundle so no stale signature or stapled ticket survives, and
# never leave a shareable zip that does not match this build.
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/DailyChallengeProof" "$APP/Contents/MacOS/DailyChallengeProof"
# Pack the committed iconset (regenerate it with scripts/make-app-icon.sh). Never ship without the icon.
if ! iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"; then
  echo 'iconutil failed to pack Resources/AppIcon.iconset; refusing to build a bundle without the app icon.' >&2
  exit 1
fi
# SwiftPM dependencies may contain resource bundles; preserve them next to the executable.
for bundle in "$BIN"/*.bundle; do
  [[ -d "$bundle" ]] || continue
  ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
python3 - "$ROOT" "$APP" <<'PY'
from pathlib import Path
import json, plistlib, sys
root, app = map(Path, sys.argv[1:])
values = dict(line.split('=', 1) for line in (root / '.env.local').read_text().splitlines()
              if line.strip() and not line.lstrip().startswith('#'))
url = values['SUPABASE_URL'].strip()
key = values['SUPABASE_PUBLISHABLE_KEY'].strip()
if not url.startswith('https://') or not key.startswith('sb_publishable_'):
    raise SystemExit('Expected an HTTPS URL and public sb_publishable_ key; never supply an admin key.')
(app / 'Contents/Resources/Configuration.json').write_text(
    json.dumps({'supabaseURL': url, 'publishableKey': key}, indent=2) + '\n')
version = dict(line.split('=', 1) for line in (root / 'VERSION').read_text().splitlines()
               if line.strip() and not line.lstrip().startswith('#'))
version = {name: value.strip() for name, value in version.items()}
for name in ('CFBundleShortVersionString', 'CFBundleVersion'):
    if not version.get(name):
        raise SystemExit(f'VERSION must set {name}.')
info = {
    'CFBundleIdentifier': 'app.daily-challenge.proof',
    'CFBundleName': 'Daily Challenge',
    'CFBundleDisplayName': 'Daily Challenge',
    'CFBundleExecutable': 'DailyChallengeProof',
    'CFBundlePackageType': 'APPL',
    'CFBundleIconFile': 'AppIcon',
    'CFBundleIconName': 'AppIcon',
    'CFBundleShortVersionString': version['CFBundleShortVersionString'],
    'CFBundleVersion': version['CFBundleVersion'],
    'LSMinimumSystemVersion': '14.0',
    'LSUIElement': True,
    'NSHighResolutionCapable': True,
}
with (app / 'Contents/Info.plist').open('wb') as file:
    plistlib.dump(info, file)
PY
if (( ADHOC )); then
  codesign --force --sign - "$APP"
  codesign --verify --strict "$APP"
  printf '\nBuilt: %s\nLaunch: open "%s"\n' "$APP" "$APP"
  echo '!!! AD-HOC BUILD: for this Mac only, NOT shareable; Gatekeeper blocks it on other Macs. Omit --adhoc to build a notarized copy. !!!' >&2
  exit 0
fi
# Nested code first (SwiftPM resource bundles, any frameworks), then the app itself.
# No entitlements: the app uses no JIT, camera, microphone or sandbox.
sign() { codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$1"; }
for nested in "$APP"/Contents/Resources/*.bundle "$APP"/Contents/Frameworks/*.framework; do
  [[ -e "$nested" ]] || continue
  sign "$nested"
done
sign "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"
if (( ! NOTARIZE )); then
  printf '\nBuilt (Developer ID signed, NOT notarized; do not share): %s\n' "$APP"
  exit 0
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
  echo "Notarization credential profile \"$NOTARY_PROFILE\" is missing or invalid." >&2
  echo "Store it once with: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id <TEAMID>" >&2
  echo 'Or pass --skip-notarize to stop after signing.' >&2
  exit 1
fi
SUBMIT_ZIP="$ROOT/build/DailyChallenge-submit.zip"
rm -f "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
SUBMIT_LOG="$(mktemp)"
trap 'rm -f "$SUBMIT_LOG" "$SUBMIT_ZIP"' EXIT
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$SUBMIT_LOG" || true
SUBMISSION_ID="$(sed -n 's/^[[:space:]]*id: //p' "$SUBMIT_LOG" | head -n 1)"
if ! grep -q '^[[:space:]]*status: Accepted' "$SUBMIT_LOG"; then
  echo 'Notarization was not accepted. Read the log with:' >&2
  echo "  xcrun notarytool log ${SUBMISSION_ID:-<submission-id>} --keychain-profile $NOTARY_PROFILE" >&2
  exit 1
fi
# A zip cannot be stapled; staple the app, then zip the stapled app for sharing.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"
ASSESSMENT="$(spctl --assess --type execute -vv "$APP" 2>&1)" || true
echo "$ASSESSMENT"
if ! grep -q ': accepted' <<<"$ASSESSMENT" || ! grep -q 'source=Notarized Developer ID' <<<"$ASSESSMENT"; then
  echo 'Gatekeeper did not accept the app as Notarized Developer ID; do not share it.' >&2
  exit 1
fi
printf '\nBuilt (Developer ID signed, notarized, stapled): %s\nShare: %s\nLaunch: open "%s"\n' "$APP" "$ZIP" "$APP"
