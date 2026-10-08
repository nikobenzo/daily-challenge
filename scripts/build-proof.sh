#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ ! -f .env.local ]]; then
  echo 'Missing .env.local. Copy .env.example and supply the public URL/publishable key.' >&2
  exit 1
fi
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
# Retain the bundle identifier and Keychain service, but give the functional app
# its product name. The running older proof bundle is left untouched.
APP="$ROOT/build/Daily Challenge.app"
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
# Ad-hoc signing is for local development, not Developer ID signing or notarization.
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf '\nBuilt: %s\nLaunch: open "%s"\n' "$APP" "$APP"
