#!/bin/bash
# Explicit native Sparkle probe, never part of swift test. It builds two versions of an
# isolated fixture (its own bundle ID, the app's SoftwareUpdates code, Sparkle embedded
# and signed as scripts/build-proof.sh does), serves a signed appcast from 127.0.0.1,
# and checks that version 1.0 finds 1.1 (user-initiated, window shown) and then
# downloads, verifies, installs and relaunches as 1.1 (silent mode). Finally a 1.2
# signed with a different key must be refused, leaving 1.1 installed.
# It never launches the real app or touches its account, Keychain items or data.
#   --ed-key-file <file>  required: a throwaway private EdDSA key file (never the
#                         owner's Keychain item); its public key is derived here.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "${1:-}" == --ed-key-file && -f "${2:-}" ]] || { echo 'Usage: test-update-fixture.sh --ed-key-file <throwaway-private-key>' >&2; exit 2; }
KEY_FILE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
FIXTURE_ID=app.daily-challenge.update-fixture
PORT="${UPDATE_FIXTURE_PORT:-8765}"
fixture="$PWD/build/update-fixture"
feed="$fixture/feed"
install="$fixture/installed"
app="$install/Daily Challenge Update FIXTURE.app"
env_local() {
  [[ -f .env.local ]] || return 0
  sed -n "s/^[[:space:]]*$1=//p" .env.local | tail -n 1 |
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}
IDENTITY="${SIGNING_IDENTITY:-$(env_local SIGNING_IDENTITY)}"
IDENTITY="${IDENTITY:--}"
derive="$(mktemp -d)/public-key.swift"
cat > "$derive" <<'SWIFT'
import CryptoKit
import Foundation
let seed = Data(base64Encoded: try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines))!
print(try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey.rawRepresentation.base64EncodedString())
SWIFT
PUBLIC_KEY="$(swift "$derive" "$KEY_FILE")"
rm -rf "$(dirname "$derive")"
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)"
rm -rf "$fixture"
mkdir -p "$feed" "$install"
cleanup() {
  if [[ -n "${server:-}" ]]; then kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi
  pkill -f "$fixture/.*/UpdateFixture" 2>/dev/null || true
  # Remove only this fixture's own preferences and caches.
  defaults delete "$FIXTURE_ID" >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Caches/$FIXTURE_ID" "$HOME/Library/HTTPStorages/$FIXTURE_ID"
}
trap cleanup EXIT
defaults delete "$FIXTURE_ID" >/dev/null 2>&1 || true
executable="$fixture/UpdateFixture"
/usr/bin/swiftc -parse-as-library -O -target "$(uname -m)-apple-macos14.0" -F "$BIN" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  Sources/DailyChallengeProof/SoftwareUpdates.swift scripts/update-fixture.swift -o "$executable"

# make_bundle <path> <short version> <build>
make_bundle() {
  local bundle="$1" sparkle="$1/Contents/Frameworks/Sparkle.framework" plist="$1/Contents/Info.plist"
  mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Frameworks"
  cp "$executable" "$bundle/Contents/MacOS/UpdateFixture"
  ditto "$BIN/Sparkle.framework" "$sparkle"
  rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
  /usr/bin/plutil -create xml1 "$plist"
  /usr/bin/plutil -replace CFBundleIdentifier -string "$FIXTURE_ID" "$plist"
  /usr/bin/plutil -replace CFBundleName -string 'Daily Challenge Update FIXTURE' "$plist"
  /usr/bin/plutil -replace CFBundleExecutable -string UpdateFixture "$plist"
  /usr/bin/plutil -replace CFBundlePackageType -string APPL "$plist"
  /usr/bin/plutil -replace CFBundleShortVersionString -string "$2" "$plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$3" "$plist"
  /usr/bin/plutil -replace LSMinimumSystemVersion -string 14.0 "$plist"
  /usr/bin/plutil -replace LSUIElement -bool YES "$plist"
  /usr/bin/plutil -replace SUFeedURL -string "http://127.0.0.1:$PORT/appcast.xml" "$plist"
  /usr/bin/plutil -replace SUPublicEDKey -string "$PUBLIC_KEY" "$plist"
  /usr/bin/plutil -replace SUEnableAutomaticChecks -bool YES "$plist"
  /usr/bin/plutil -replace SUScheduledCheckInterval -integer 86400 "$plist"
  # Fixture-only: plain HTTP to 127.0.0.1. The shipped app requires an https:// feed.
  /usr/bin/plutil -replace NSAppTransportSecurity -json '{"NSAllowsLocalNetworking":true}' "$plist"
  local options=()
  [[ "$IDENTITY" == - ]] || options=(--options runtime --timestamp)
  for nested in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle" "$bundle"; do
    /usr/bin/codesign --force ${options[@]+"${options[@]}"} --sign "$IDENTITY" "$nested"
  done
  /usr/bin/codesign --verify --strict --deep "$bundle"
}

make_bundle "$app" 1.0 1
make_bundle "$fixture/build-1.1/Daily Challenge Update FIXTURE.app" 1.1 2
ditto -c -k --keepParent "$fixture/build-1.1/Daily Challenge Update FIXTURE.app" "$feed/UpdateFixture-1.1-2.zip"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --maximum-deltas 0 --ed-key-file "$KEY_FILE" \
  --download-url-prefix "http://127.0.0.1:$PORT/" "$feed" >/dev/null
/usr/bin/python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$feed" >"$fixture/http.log" 2>&1 &
server=$!
sleep 1

run_fixture() {
  echo "$1" > "$install/mode"
  "$app/Contents/MacOS/UpdateFixture" || true
}
# 1. User-initiated check: Sparkle must find 1.1 and put its window on screen.
run_fixture interactive
# 2. Silent install: download, EdDSA + code signature checks, install, relaunch as 1.1.
run_fixture silent
for _ in $(seq 1 60); do
  grep -q 'launched 1.1 (2)' "$install/result.log" 2>/dev/null && grep -q 'no-update' "$install/result.log" && break
  sleep 1
done
{ /usr/bin/sw_vers; echo "signing identity: $IDENTITY"; echo; cat "$install/result.log"; echo; echo 'HTTP requests:'; grep -E '"GET ' "$fixture/http.log"; } |
  tee "$fixture/result.txt"
installed="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
grep -q 'found-update 1.1 (2)' "$install/result.log" &&
  grep -Eq 'onscreen-windows=\[[0-9]+.*visible-titles=\["Software Update"\].*dockIcon=false' "$install/result.log" &&
  grep -q 'installing 2' "$install/result.log" && grep -q 'launched 1.1 (2)' "$install/result.log" && [[ "$installed" == 1.1 ]] ||
  { echo 'FAIL: the fixture did not find, show and install version 1.1.' >&2; exit 1; }
/usr/bin/codesign --verify --strict --deep "$app"

# 3. A 1.2 signed with any other key must be rejected before installation.
make_bundle "$fixture/build-1.2/Daily Challenge Update FIXTURE.app" 1.2 3
ditto -c -k --keepParent "$fixture/build-1.2/Daily Challenge Update FIXTURE.app" "$feed/UpdateFixture-1.2-3.zip"
head -c 32 /dev/urandom | base64 > "$fixture/wrong-ed-key"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast --maximum-deltas 0 --ed-key-file "$fixture/wrong-ed-key" \
  --download-url-prefix "http://127.0.0.1:$PORT/" "$feed" >/dev/null
: > "$install/result.log"
run_fixture silent
{ echo; echo 'Wrong-key 1.2:'; cat "$install/result.log"; } | tee -a "$fixture/result.txt"
installed="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
grep -q 'found-update 1.2 (3)' "$install/result.log" && grep -q 'aborted SUSparkleErrorDomain 4005' "$install/result.log" &&
  ! grep -q 'installing 3' "$install/result.log" && [[ "$installed" == 1.1 ]] ||
  { echo 'FAIL: a 1.2 signed with the wrong key was not refused.' >&2; exit 1; }
echo "PASS: 1.0 found, showed and installed 1.1; a wrongly signed 1.2 was refused (installed: $installed)"
