#!/bin/bash
# Xcode build phase for the iPhone app. Writes the public Supabase configuration from
# ../.env.local into the app as Configuration.json (as scripts/build-proof.sh does for the
# Mac) and the version from ../VERSION into the built Info.plist. Nothing here is committed
# or hard-coded. Debug builds without .env.local still build and show "Configuration
# unavailable"; Release builds (archives) refuse.
set -euo pipefail
ROOT="$(cd "$SRCROOT/.." && pwd)"
RESOURCES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
PLIST="$TARGET_BUILD_DIR/$INFOPLIST_PATH"

python3 - "$ROOT" "$RESOURCES" "$PLIST" "$CONFIGURATION" "${1:-}" <<'PY'
import json, plistlib, sys
from pathlib import Path
root, resources, plist, configuration = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4]

def values(path):
    """KEY=value lines; '#' starts a comment; the last value wins; quotes are stripped."""
    result = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        result[key.strip()] = value.strip().strip('"').strip("'")
    return result

def fail_or_warn(message):
    if configuration == 'Release':
        print(f'error: {message}')
        sys.exit(1)
    print(f'warning: {message} The app will show "Configuration unavailable".')

target = resources / 'Configuration.json'
env = root / '.env.local'
if sys.argv[5] == '--version-only':
    target.unlink(missing_ok=True)
elif env.exists():
    settings = values(env)
    url = settings.get('SUPABASE_URL', '')
    key = settings.get('SUPABASE_PUBLISHABLE_KEY', '')
    if url.startswith('https://') and key.startswith('sb_publishable_'):
        target.write_text(json.dumps({'supabaseURL': url, 'publishableKey': key}, indent=2) + '\n')
    else:
        target.unlink(missing_ok=True)
        fail_or_warn('.env.local needs an HTTPS SUPABASE_URL and a public sb_publishable_ key; never an admin key.')
else:
    target.unlink(missing_ok=True)
    fail_or_warn('Missing .env.local at the repository root (copy .env.example).')

version = values(root / 'VERSION')
for name in ('CFBundleShortVersionString', 'CFBundleVersion'):
    if not version.get(name):
        print(f'error: VERSION must set {name}.')
        sys.exit(1)
with open(plist, 'rb') as handle:
    info = plistlib.load(handle)
info['CFBundleShortVersionString'] = version['CFBundleShortVersionString']
info['CFBundleVersion'] = version['CFBundleVersion']
with open(plist, 'wb') as handle:
    plistlib.dump(info, handle, fmt=plistlib.FMT_BINARY)
PY
