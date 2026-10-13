#!/bin/bash
# Captures the App Store screenshots (6.9-inch class: iPhone 17 Pro Max, 1320 x 2868) and
# the all-complete screen on medium iPhone (iPhone 17, 1206 x 2622) from the iOS
# Simulator into docs/screenshots/app-store/raw/ (raw captures only; marketing layouts are composed elsewhere). The app runs on Debug fixtures (-fixture): no account,
# Keychain, network or notification permission is used. Light mode is primary; Dark is captured too.
#   DEVICE         simulator name (default "iPhone 17 Pro Max")
#   MEDIUM_DEVICE  medium simulator name (default "iPhone 17")
#   RUNTIME        runtime identifier fragment (default "iOS-26-", the iOS 26.4 simulator)
#   CAPTURE_WAIT   settling seconds after each launch (default 4)
#   CAPTURE_COMPLETE_ONLY=1  capture only all-complete, on both sizes, preserving existing raw files
# The Home Screen widget screenshots come from iOS/scripts/capture-widgets.sh (see docs/app-store-listing.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
DEVICE="${DEVICE:-iPhone 17 Pro Max}"
MEDIUM_DEVICE="${MEDIUM_DEVICE:-iPhone 17}"
RUNTIME="${RUNTIME:-iOS-26-}"
OUT="$ROOT/docs/screenshots/app-store/raw"
DERIVED="$ROOT/.build/ios-derived"
BUNDLE_ID=app.daily-challenge.ios

device_id() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items() if sys.argv[2] in runtime for d in ds]
match = [d for d in devices if d["name"] == name]
print(next((d["udid"] for d in match if d["state"] == "Booted"), match[0]["udid"] if match else ""))
' "$1" "$RUNTIME"
}
udid="$(device_id "$DEVICE")"
[[ -n "$udid" ]] || { echo "No available simulator named $DEVICE" >&2; exit 1; }
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null

xcodebuild -project iOS/DailyChallenge.xcodeproj -scheme DailyChallenge -configuration Debug \
  -destination "id=$udid" -derivedDataPath "$DERIVED" build -quiet
xcrun simctl install "$udid" "$DERIVED/Build/Products/Debug-iphonesimulator/Daily Challenge.app"
xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

mkdir -p "$OUT"
xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" -fixture signIn >/dev/null
sleep 6
capture() { # name fixture appearance [extra launch arguments…]
  local name="$1" fixture="$2" appearance="$3"
  shift 3
  xcrun simctl ui "$udid" appearance "$appearance"
  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" \
    -fixture "$fixture" -appearance "$appearance" "$@" >/dev/null
  sleep "${CAPTURE_WAIT:-4}"
  xcrun simctl io "$udid" screenshot --type=png "$OUT/$name-$appearance.png" >/dev/null 2>&1
  echo "captured $name-$appearance"
}

for appearance in light dark; do
  if [[ "${CAPTURE_COMPLETE_ONLY:-0}" != 1 ]]; then
    capture 01-today todayExtras "$appearance"
    capture 02-history historyCarryOver "$appearance"
    capture 03-account account "$appearance"
    # 1.1: personalised goals (Gym, Yoga, No sugar, Audiobook, 3,000 ml in 330 ml glasses)
    # and repeating extras beside a late to-do.
    capture 01-today-goals todayGoals "$appearance"
    capture 02-history-goals historyGoals "$appearance"
    capture 07-today-recurring todayRecurring "$appearance"
  fi
  capture 06-today-complete todayComplete "$appearance"
done
# Only strip alpha from the images written by this run, never re-encode other raw captures.
strip_alpha() {
python3 - "$OUT" "$@" <<'PY'
import subprocess, sys
from pathlib import Path
for name in sys.argv[2:]:
    png = Path(sys.argv[1]) / name
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "100", str(png), "--out", str(png.with_suffix(".jpg"))],
                   check=True, capture_output=True)
    subprocess.run(["sips", "-s", "format", "png", str(png.with_suffix(".jpg")), "--out", str(png)], check=True, capture_output=True)
    png.with_suffix(".jpg").unlink()
PY
}
if [[ "${CAPTURE_COMPLETE_ONLY:-0}" != 1 ]]; then
  strip_alpha 01-today-light.png 01-today-dark.png 02-history-light.png 02-history-dark.png \
    03-account-light.png 03-account-dark.png 01-today-goals-light.png 01-today-goals-dark.png \
    02-history-goals-light.png 02-history-goals-dark.png 07-today-recurring-light.png 07-today-recurring-dark.png
fi
strip_alpha 06-today-complete-light.png 06-today-complete-dark.png
xcrun simctl ui "$udid" appearance light
xcrun simctl status_bar "$udid" clear
xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true

# Same built Debug fixture app and runtime on the medium display. No screenshot resizing.
udid="$(device_id "$MEDIUM_DEVICE")"
[[ -n "$udid" ]] || { echo "No available simulator named $MEDIUM_DEVICE" >&2; exit 1; }
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$DERIVED/Build/Products/Debug-iphonesimulator/Daily Challenge.app"
xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
OUT="$OUT/iphone-medium"
mkdir -p "$OUT"
xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" -fixture signIn >/dev/null
sleep 6
for appearance in light dark; do
  capture 06-today-complete todayComplete "$appearance"
done
strip_alpha 06-today-complete-light.png 06-today-complete-dark.png
xcrun simctl ui "$udid" appearance light
xcrun simctl status_bar "$udid" clear
xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
echo "App Store screenshots: $OUT"
