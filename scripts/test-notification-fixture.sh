#!/bin/bash
# Explicit opt-in OS integration probe; not part of swift test.
# May show a native permission prompt and one clearly labelled fixture notification.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="$PWD/build/notification-fixture"
app="$fixture/Daily Challenge Notification FIXTURE.app"
mkdir -p "$app/Contents/MacOS"
/usr/bin/swiftc scripts/notification-fixture.swift -o "$app/Contents/MacOS/NotificationFixture"
rm -f "$app/Contents/Info.plist"
/usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string app.daily-challenge.notification-fixture.r1 "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string 'Daily Challenge Notification FIXTURE' "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string 'Daily Challenge Notification FIXTURE' "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string NotificationFixture "$app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
/usr/bin/plutil -insert LSUIElement -bool YES "$app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/sw_vers > "$fixture/result.txt"
/usr/bin/codesign -dvv "$app" 2>> "$fixture/result.txt"
/usr/bin/codesign --verify --strict --verbose=2 "$app" 2>> "$fixture/result.txt"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
/usr/bin/open -n -W --stdout "$fixture/gui.txt" --stderr "$fixture/gui-errors.txt" "$app"
# GUI logs stay inside this isolated build directory.
