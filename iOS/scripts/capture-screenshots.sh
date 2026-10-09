#!/bin/bash
# Captures every iPhone screen in Light and Dark from the iOS Simulator into
# docs/screenshots/ios/. The app runs on Debug fixtures (-fixture): no account,
# Keychain, network or notification permission is used.
#   DEVICE   simulator name (default "iPhone 17")
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
DEVICE="${DEVICE:-iPhone 17}"
OUT="$ROOT/docs/screenshots/ios"
DERIVED="$ROOT/.build/ios-derived"
BUNDLE_ID=app.daily-challenge.ios

udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in ds]
match = [d for d in devices if d["name"] == name]
print(next((d["udid"] for d in match if d["state"] == "Booted"), match[0]["udid"] if match else ""))
' "$DEVICE")"
[[ -n "$udid" ]] || { echo "No available simulator named $DEVICE" >&2; exit 1; }
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null

xcodebuild -project iOS/DailyChallenge.xcodeproj -scheme DailyChallenge -configuration Debug \
  -destination "id=$udid" -derivedDataPath "$DERIVED" build -quiet
xcrun simctl install "$udid" "$DERIVED/Build/Products/Debug-iphonesimulator/Daily Challenge.app"
# A fixed status bar keeps captures comparable.
xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

mkdir -p "$OUT"
# The first launch after an install is slow; warm up so the first capture is not a blank frame.
xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" -fixture signIn >/dev/null
sleep 6
capture() { # name fixture appearance [extra launch arguments…]
  local name="$1" fixture="$2" appearance="$3"
  shift 3
  xcrun simctl ui "$udid" appearance "$appearance"
  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" \
    -fixture "$fixture" -appearance "$appearance" "$@" >/dev/null
  sleep 3
  xcrun simctl io "$udid" screenshot --type=png "$OUT/$name-$appearance.png" >/dev/null 2>&1
  echo "captured $name-$appearance"
}

for appearance in light dark; do
  for screen in signIn createAccount confirmCode forgotPassword resetPassword checking setup today todayComplete history account; do
    capture "$screen" "$screen" "$appearance"
  done
  capture today-large-text today "$appearance" -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
done
xcrun simctl status_bar "$udid" clear
xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
echo "Screenshots: $OUT"
