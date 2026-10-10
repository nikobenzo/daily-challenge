#!/bin/bash
# Archives the iPhone app (iOS/DailyChallenge.xcodeproj) for App Store Connect with automatic
# signing and uploads the build for TestFlight. Owner-run: see docs/ios-testflight.md.
#
# Credentials come only from the environment, never from this repository:
#   App Store Connect API key (recommended; signs and uploads without an Xcode login):
#     ASC_KEY_PATH   path to the AuthKey_XXXXXXXXXX.p8 file (keep it outside the repository)
#     ASC_KEY_ID     the key's ID
#     ASC_ISSUER_ID  the issuer ID shown above the keys list
#   or Xcode's signed-in account for signing plus an app-specific password in the keychain:
#     ASC_APPLE_ID        the Apple Account email
#     ASC_KEYCHAIN_ITEM   keychain item created with
#                         xcrun altool --store-password-in-keychain-item <item> -u <email> -p <app-specific password>
#
#   --check   archive unsigned to prove the Release build compiles; needs no credentials,
#             contacts nothing and uploads nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/ios"
ARCHIVE="$OUT/DailyChallenge.xcarchive"
EXPORT="$OUT/export"
PROJECT=iOS/DailyChallenge.xcodeproj
TEAM_ID=L644Y3WX5T

check=0
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    *) echo "Unknown option: $arg (expected --check)" >&2; exit 2 ;;
  esac
done

owner_steps() {
  cat >&2 <<'STEPS'
Refusing to archive: no App Store Connect credentials in the environment.

Owner steps (once; full guide in docs/ios-testflight.md):
  1. App Store Connect > Users and Access > Integrations > App Store Connect API >
     Team Keys: generate a key with the App Manager role. Download AuthKey_<KEYID>.p8
     once and keep it outside this repository, for example
     ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 (chmod 600).
  2. Then run, in this terminal:
       export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
       export ASC_KEY_ID=<KEYID>
       export ASC_ISSUER_ID=<issuer ID shown above the keys list>
       bash scripts/ios-archive.sh
  Or, signed in to Xcode (Settings > Accounts) with an app-specific password stored once:
       xcrun altool --store-password-in-keychain-item dc-asc -u <apple id> -p <app-specific password>
       export ASC_APPLE_ID=<apple id> ASC_KEYCHAIN_ITEM=dc-asc
       bash scripts/ios-archive.sh
STEPS
}

if [[ ! -f .env.local ]]; then
  echo 'Missing .env.local. Copy .env.example and supply the public URL/publishable key.' >&2
  exit 1
fi

mkdir -p "$OUT"
if [[ "$check" == 1 ]]; then
  rm -rf "$ARCHIVE"
  xcodebuild archive -project "$PROJECT" -scheme DailyChallenge -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet
  app="$ARCHIVE/Products/Applications/Daily Challenge.app"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' -c 'Print :CFBundleShortVersionString' \
    -c 'Print :CFBundleVersion' "$app/Info.plist"
  [[ -f "$app/Configuration.json" ]] || { echo 'Configuration.json missing from the archive.' >&2; exit 1; }
  if find "$app" -iname '*sparkle*' | grep -q .; then echo 'Sparkle must not be in the iPhone app.' >&2; exit 1; fi
  extension="$app/PlugIns/DailyChallengeWidgets.appex"
  [[ -d "$extension" ]] || { echo 'Widget extension missing.' >&2; exit 1; }
  python3 - "$app" "$extension" <<'PY'
import plistlib, sys
from pathlib import Path
app, extension = map(Path, sys.argv[1:])
a = plistlib.loads((app / 'Info.plist').read_bytes())
e = plistlib.loads((extension / 'Info.plist').read_bytes())
assert e['CFBundleIdentifier'] == 'app.daily-challenge.ios.widgets'
assert e['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
    assert a[key] == e[key], f'Mismatched {key}'
assert not (extension / 'Configuration.json').exists(), 'Extension must not contain server configuration'
print('Embedded WidgetKit extension ID, extension point and matching versions verified')
PY
  echo "Unsigned Release archive OK (not uploadable): $ARCHIVE"
  exit 0
fi

auth=()
upload=""
if [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  [[ -f "$ASC_KEY_PATH" ]] || { echo "ASC_KEY_PATH does not exist: $ASC_KEY_PATH" >&2; exit 1; }
  case "$(cd "$(dirname "$ASC_KEY_PATH")" && pwd)/" in
    "$ROOT"/*) echo 'Keep the .p8 key outside this repository.' >&2; exit 1 ;;
  esac
  auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  upload=xcodebuild
elif [[ -n "${ASC_APPLE_ID:-}" && -n "${ASC_KEYCHAIN_ITEM:-}" ]]; then
  upload=altool
else
  owner_steps
  exit 1
fi

# The build number must be new for every upload: raise CFBundleVersion in VERSION.
version="$(sed -n 's/^CFBundleShortVersionString=//p' VERSION) ($(sed -n 's/^CFBundleVersion=//p' VERSION))"
echo "Archiving Daily Challenge for iPhone $version"

rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild archive -project "$PROJECT" -scheme DailyChallenge -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
# The archive is left unsigned on purpose: signing it at archive time would need a development
# profile, and a development profile needs at least one registered device, which an upload-only
# team has no reason to have. The export step below signs the app for App Store Connect with the
# distribution profile that -allowProvisioningUpdates obtains.

options="$OUT/ExportOptions.plist"
cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$([[ "$upload" == xcodebuild ]] && echo upload || echo export)</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>testFlightInternalTestingOnly</key><true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$options" \
  -allowProvisioningUpdates "${auth[@]}"

if [[ "$upload" == altool ]]; then
  ipa="$(find "$EXPORT" -name '*.ipa' -maxdepth 1 | head -n 1)"
  [[ -n "$ipa" ]] || { echo "No .ipa was exported to $EXPORT" >&2; exit 1; }
  xcrun altool --upload-app -f "$ipa" -t ios -u "$ASC_APPLE_ID" -p "@keychain:$ASC_KEYCHAIN_ITEM"
fi
echo "Uploaded $version. In App Store Connect > TestFlight, add it to the internal group once processing finishes."
