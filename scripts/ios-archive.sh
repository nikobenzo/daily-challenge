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
#   --check      archive and ad-hoc sign to prove the Release build compiles and carries its
#                entitlements; needs no credentials, contacts nothing and uploads nothing.
#   --app-store  export a build that can be submitted for App Review. Without it the export is
#                marked TestFlight internal testing only and can never be submitted.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/ios"
ARCHIVE="$OUT/DailyChallenge.xcarchive"
EXPORT="$OUT/export"
PROJECT=iOS/DailyChallenge.xcodeproj
TEAM_ID=L644Y3WX5T
APP_GROUP=group.app.daily-challenge.ios

check=0
app_store=0
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    --app-store) app_store=1 ;;
    *) echo "Unknown option: $arg (expected --check or --app-store)" >&2; exit 2 ;;
  esac
done
if [[ "$check" == 1 && "$app_store" == 1 ]]; then
  echo '--check uploads nothing, so --app-store does not apply to it.' >&2
  exit 2
fi

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

# Builds the Release archive without a development profile, then ad-hoc signs the widget extension
# and the app with their entitlements files. Signing at archive time would need a development
# profile, and a development profile needs at least one registered device, which an upload-only
# team has no reason to have; Xcode also refuses its own ad-hoc signing for App Group entitlements
# ("requires a provisioning profile"). The export signs the app for App Store Connect with the
# distribution profiles that -allowProvisioningUpdates obtains, and it keeps only the entitlements
# the archived code already carries, so an unsigned archive would ship without the App Group.
archive() {
  rm -rf "$ARCHIVE"
  xcodebuild archive -project "$PROJECT" -scheme DailyChallenge -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "$@"
  local app="$ARCHIVE/Products/Applications/Daily Challenge.app"
  codesign --force --sign - --timestamp=none --generate-entitlement-der \
    --entitlements iOS/DailyChallengeWidgets/DailyChallengeWidgets.entitlements \
    "$app/PlugIns/DailyChallengeWidgets.appex"
  codesign --force --sign - --timestamp=none --generate-entitlement-der \
    --entitlements iOS/DailyChallenge/DailyChallenge.entitlements "$app"
  require_app_group "$app"
}

# Refuses unless the signed app and its embedded widget extension both carry the App Group.
require_app_group() {
  local bundle groups entitlements="$OUT/entitlements.plist"
  for bundle in "$1" "$1/PlugIns/DailyChallengeWidgets.appex"; do
    rm -f "$entitlements"
    # PlistBuddy, not plutil: plutil key paths split the dotted entitlement name.
    groups="$(codesign -d --entitlements "$entitlements" --xml "$bundle" 2>/dev/null &&
      /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$entitlements" 2>/dev/null)" ||
      groups=none
    if ! grep -qxF "    $APP_GROUP" <<<"$groups"; then
      echo "Refusing: $bundle is not signed with App Group $APP_GROUP (application groups: $groups)." >&2
      return 1
    fi
    echo "${bundle##*/}: signed with App Group $APP_GROUP"
  done
}

if [[ ! -f .env.local ]]; then
  echo 'Missing .env.local. Copy .env.example and supply the public URL/publishable key.' >&2
  exit 1
fi

mkdir -p "$OUT"
if [[ "$check" == 1 ]]; then
  archive -quiet
  app="$ARCHIVE/Products/Applications/Daily Challenge.app"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' -c 'Print :CFBundleShortVersionString' \
    -c 'Print :CFBundleVersion' "$app/Info.plist"
  [[ -f "$app/Configuration.json" ]] || { echo 'Configuration.json missing from the archive.' >&2; exit 1; }
  if find "$app" -iname '*sparkle*' | grep -q .; then echo 'Sparkle must not be in the iPhone app.' >&2; exit 1; fi
  extension="$app/PlugIns/DailyChallengeWidgets.appex"
  [[ -d "$extension" ]] || { echo 'Widget extension missing.' >&2; exit 1; }
  python3 - "$app" "$extension" "$ROOT/.env.local" <<'PY'
import plistlib, sys
from pathlib import Path
app, extension, env = map(Path, sys.argv[1:])
a = plistlib.loads((app / 'Info.plist').read_bytes())
e = plistlib.loads((extension / 'Info.plist').read_bytes())
assert e['CFBundleIdentifier'] == 'app.daily-challenge.ios.widgets'
assert e['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
    assert a[key] == e[key], f'Mismatched {key}'
assert not (extension / 'Configuration.json').exists(), 'Extension must not contain server configuration'
# Widget App Intents run in the extension only; the app target ships none.
import json
actions = json.loads((extension / 'Metadata.appintents' / 'extract.actionsdata').read_text())['actions']
assert sorted(actions) == ['PourWaterIntent', 'SetDietIntent', 'ToggleExtraIntent', 'ToggleHabitIntent', 'UndoWaterIntent'], sorted(actions)
assert not any(action.get('isDiscoverable') for action in actions.values()), 'Widget intents must not be discoverable'
assert not (app / 'Metadata.appintents').exists(), 'Widget intents must not be compiled into the app'
# The extension never networks: no configuration, credentials or keys among its resources or in
# its binary. The configured values are compared without being printed.
secrets = [line.split('=', 1)[1].strip().strip('"').encode() for line in env.read_text().splitlines()
           if '=' in line and not line.lstrip().startswith('#') and line.split('=', 1)[1].strip()]
# Key shapes, not bare prefixes: the linked supabase-swift SDK names the `sb_secret_` prefix itself.
import re
shapes = [re.compile(rb'sb_secret_[A-Za-z0-9_-]{16,}'), re.compile(rb'eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}'),
          re.compile(rb'service_role'), re.compile(rb'BEGIN [A-Z ]*PRIVATE KEY')]
markers = [b'SUPABASE_URL', b'SUPABASE_PUBLISHABLE_KEY'] + secrets
for item in extension.rglob('*'):
    name = item.name.lower()
    assert not (name.startswith('.env') or name.endswith(('.p8', '.p12', '.mobileprovision')) or name == 'configuration.json'), \
        f'Unexpected configuration or credential file in the extension: {item.relative_to(extension)}'
    if item.is_file() and not item.is_symlink():
        data = item.read_bytes()
        found = [index for index, marker in enumerate(markers) if marker and marker in data]
        found += [f'shape {index}' for index, shape in enumerate(shapes) if shape.search(data)]
        assert not found, f'{item.relative_to(extension)} contains configuration or credential text (marker {found})'
print(f'Extension resources scanned: no configuration, credentials or {len(secrets)} configured values')
print('Embedded WidgetKit extension ID, extension point, matching versions and extension-only widget intents verified')
PY
  echo "Ad-hoc signed Release archive OK (not uploadable): $ARCHIVE"
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
  upload=key
elif [[ -n "${ASC_APPLE_ID:-}" && -n "${ASC_KEYCHAIN_ITEM:-}" ]]; then
  upload=password
else
  owner_steps
  exit 1
fi

# The build number must be new for every upload: raise CFBundleVersion in VERSION.
version="$(sed -n 's/^CFBundleShortVersionString=//p' VERSION) ($(sed -n 's/^CFBundleVersion=//p' VERSION))"
if [[ "$app_store" == 1 ]]; then
  echo "Archiving Daily Challenge for iPhone $version as an App Store build (can be submitted for review)"
else
  echo "Archiving Daily Challenge for iPhone $version as an internal TestFlight build"
fi

rm -rf "$EXPORT"
archive

# Internal-only is the default: it keeps a build out of external testing and review by mistake.
# --app-store omits the key, which is the only difference in the export.
internal_only=""
if [[ "$app_store" == 0 ]]; then
  internal_only="  <key>testFlightInternalTestingOnly</key><true/>"
fi

options="$OUT/ExportOptions.plist"
cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
$internal_only
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$options" \
  -allowProvisioningUpdates "${auth[@]}"

# Export to disk first so the exact distribution-signed IPA is inspected before it is uploaded.
ipa="$(find "$EXPORT" -name '*.ipa' -maxdepth 1 | head -n 1)"
[[ -n "$ipa" ]] || { echo "No .ipa was exported to $EXPORT" >&2; exit 1; }
unpacked="$OUT/ipa-check"
rm -rf "$unpacked"
ditto -x -k "$ipa" "$unpacked"
require_app_group "$unpacked/Payload/Daily Challenge.app" || { echo "Not uploading $ipa." >&2; exit 1; }

if [[ "$upload" == key ]]; then
  xcrun altool --upload-app -f "$ipa" -t ios --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID" \
    --p8-file-path "$ASC_KEY_PATH"
else
  xcrun altool --upload-app -f "$ipa" -t ios -u "$ASC_APPLE_ID" -p "@keychain:$ASC_KEYCHAIN_ITEM"
fi
if [[ "$app_store" == 1 ]]; then
  echo "Uploaded $version. In App Store Connect, choose it under the app version's Build section once processing finishes, then submit for review."
else
  echo "Uploaded $version. In App Store Connect > TestFlight, add it to the internal group once processing finishes."
fi
