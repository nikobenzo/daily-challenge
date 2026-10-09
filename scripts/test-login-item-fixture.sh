#!/bin/bash
# Explicit native integration probe, never part of swift test.
# Registers only this isolated fixture, then unregisters it; no approval/settings changes.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="$PWD/build/login-item-fixture"
app="$fixture/Daily Challenge Login FIXTURE.app"
mkdir -p "$app/Contents/MacOS"
/usr/bin/swiftc -parse-as-library Sources/DailyChallengeProof/{LaunchAtLogin,Theme,Components,PopupVisibility}.swift \
  scripts/login-item-fixture.swift -o "$app/Contents/MacOS/LoginFixture"
rm -f "$app/Contents/Info.plist"
/usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string app.daily-challenge.login-fixture "$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleName -string 'Daily Challenge Login FIXTURE' "$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleExecutable -string LoginFixture "$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundlePackageType -string APPL "$app/Contents/Info.plist"
/usr/bin/plutil -replace LSUIElement -bool YES "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/sw_vers > "$fixture/result.txt"
"$app/Contents/MacOS/LoginFixture" | tee -a "$fixture/result.txt"
