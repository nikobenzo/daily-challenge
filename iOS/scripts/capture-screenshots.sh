#!/bin/bash
# Captures every iPhone screen in Light and Dark from the iOS Simulator into
# docs/screenshots/ios/. The app runs on Debug fixtures (-fixture): no account,
# Keychain, network or notification permission is used.
#   DEVICE   simulator name (default "iPhone 17")
#   CAPTURE_WAIT   settling seconds after each launch (default 3)
#   CAPTURE_PHASE2_ONLY=1   capture shared Today + recovery only
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
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items() if "iOS-27-" in runtime for d in ds]
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
  sleep "${CAPTURE_WAIT:-3}"
  xcrun simctl io "$udid" screenshot --type=png "$OUT/$name-$appearance.png" >/dev/null 2>&1
  echo "captured $name-$appearance"
}

# Phase 2 review evidence can be refreshed without recapturing prior phases.
if [[ "${CAPTURE_PHASE2_ONLY:-0}" == 1 ]]; then
  for appearance in light dark; do
    capture sharedToday sharedToday "$appearance"
    capture storageRecovery storageRecovery "$appearance"
  done
  xcrun simctl status_bar "$udid" clear
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  echo "Phase 2 screenshots: $OUT"
  exit 0
fi

for appearance in light dark; do
  for screen in sharedToday storageRecovery signIn createAccount confirmCode forgotPassword resetPassword checking setup today todayComplete history account; do
    capture "$screen" "$screen" "$appearance"
  done
  for screen in todayExtras extrasCap accountExtras; do
    capture "$screen" "$screen" "$appearance"
  done
  capture today-extras-detail todayExtras "$appearance" -fixture-scroll-to fixture-extras
  capture historyExtras historyExtras "$appearance" -fixture-scroll-to fixture-history-day
  capture historyExtrasEditing historyExtrasEditing "$appearance" -fixture-scroll-to fixture-history-day
  capture manage-extras todayExtras "$appearance" -manage-extras
  capture manage-extras-empty today "$appearance" -manage-extras
  capture manage-extras-cap extrasCap "$appearance" -manage-extras
  capture manage-extras-large-text todayExtras "$appearance" -manage-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture manage-extras-actions-large-text todayExtras "$appearance" -manage-extras -fixture-scroll-to fixture-extra-actions -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture history-extras-large-text historyExtras "$appearance" -fixture-scroll-to fixture-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture today-extras-large-text todayExtras "$appearance" -fixture-scroll-to fixture-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture account-extras-large-text accountExtras "$appearance" -fixture-scroll-to fixture-account-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture today-large-text today "$appearance" -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
done
xcrun simctl status_bar "$udid" clear
xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
echo "Screenshots: $OUT"
