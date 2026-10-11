#!/bin/bash
# Captures the App Store screenshots (6.9-inch class: iPhone 17 Pro Max, 1320 x 2868) from the iOS
# Simulator into docs/screenshots/app-store/raw/ (raw captures only; marketing layouts are composed elsewhere). The app runs on Debug fixtures (-fixture): no account,
# Keychain, network or notification permission is used. Light mode is primary; Dark is captured too.
#   DEVICE         simulator name (default "iPhone 17 Pro Max")
#   RUNTIME        runtime identifier fragment (default "iOS-26-", the iOS 26.4 simulator)
#   CAPTURE_WAIT   settling seconds after each launch (default 4)
# The Home Screen widget screenshots come from iOS/scripts/capture-widgets.sh (see docs/app-store-listing.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
DEVICE="${DEVICE:-iPhone 17 Pro Max}"
RUNTIME="${RUNTIME:-iOS-26-}"
OUT="$ROOT/docs/screenshots/app-store/raw"
DERIVED="$ROOT/.build/ios-derived"
BUNDLE_ID=app.daily-challenge.ios

udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items() if sys.argv[2] in runtime for d in ds]
match = [d for d in devices if d["name"] == name]
print(next((d["udid"] for d in match if d["state"] == "Booted"), match[0]["udid"] if match else ""))
' "$DEVICE" "$RUNTIME")"
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
  capture 01-today todayExtras "$appearance"
  capture 02-history historyCarryOver "$appearance"
  capture 03-account account "$appearance"
done
# App Store Connect rejects screenshots with an alpha channel; simulator PNGs carry one.
python3 - "$OUT" <<'PY'
import subprocess, sys
from pathlib import Path
for png in Path(sys.argv[1]).glob("0*.png"):
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "100", str(png), "--out", str(png.with_suffix(".jpg"))],
                   check=True, capture_output=True)
    subprocess.run(["sips", "-s", "format", "png", str(png.with_suffix(".jpg")), "--out", str(png)], check=True, capture_output=True)
    png.with_suffix(".jpg").unlink()
PY
xcrun simctl ui "$udid" appearance light
xcrun simctl status_bar "$udid" clear
xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
echo "App Store screenshots: $OUT"
