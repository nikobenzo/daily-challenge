#!/bin/bash
# Captures every iPhone screen in Light and Dark from the iOS Simulator into
# docs/screenshots/ios/. The app runs on Debug fixtures (-fixture): no account,
# Keychain, network or notification permission is used.
#   DEVICE   simulator name (default "iPhone 17")
#   CAPTURE_WAIT   settling seconds after each launch (default 3)
#   CAPTURE_PHASE2_ONLY=1   capture shared Today + recovery only
#   CAPTURE_PHASE5_ONLY=1   capture the Manage extras screens only (design field fill)
#   CAPTURE_EXTRAS_ONLY=1   capture the extras screens only (carry-over fixtures)
#   CAPTURE_DELETION_ONLY=1   capture Delete account (both confirmation steps) only
#   CAPTURE_GOALS_ONLY=1   capture custom daily goals and repeating extras only
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

# Phase 5 recaptures only the Manage extras screens whose fields changed.
if [[ "${CAPTURE_PHASE5_ONLY:-0}" == 1 ]]; then
  for appearance in light dark; do
    capture manage-extras todayExtras "$appearance" -manage-extras
    capture manage-extras-empty today "$appearance" -manage-extras
    capture manage-extras-large-text todayExtras "$appearance" -manage-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  done
  xcrun simctl status_bar "$udid" clear
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  echo "Phase 5 screenshots: $OUT"
  exit 0
fi

# Custom daily goals (setup rows and editors, Today, History, Account) and repeating extras.
capture_goals() {
  capture goals-setup setup "$1"
  capture goals-setup-water setup "$1" -edit-goal water
  capture goals-setup-walk setup "$1" -edit-goal walk
  capture goals-setup-diet setup "$1" -edit-goal diet
  capture goals-setup-reading setup "$1" -edit-goal bibleReading
  capture goals-today todayGoals "$1"
  capture goals-history-today historyGoals "$1" -fixture-scroll-to fixture-history-day
  capture goals-history-before historyGoalsBefore "$1" -fixture-scroll-to fixture-history-day
  capture goals-account accountGoals "$1" -fixture-scroll-to fixture-account-goals
  capture goals-daily accountGoals "$1" -daily-goals
  capture goals-daily-walk accountGoals "$1" -daily-goals -edit-goal walk
  capture goals-unmigrated goalsUnmigrated "$1" -daily-goals
  capture goals-recurring-today todayRecurring "$1" -fixture-scroll-to fixture-extras
  capture goals-manage-extras todayRecurring "$1" -manage-extras
  capture goals-repeat todayRecurring "$1" -manage-extras -repeat-extra
  capture goals-setup-large-text setup "$1" -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture goals-editor-large-text setup "$1" -edit-goal walk -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture goals-today-large-text todayGoals "$1" -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture goals-recurring-large-text todayRecurring "$1" -fixture-scroll-to fixture-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
}
if [[ "${CAPTURE_GOALS_ONLY:-0}" == 1 ]]; then
  for appearance in light dark; do capture_goals "$appearance"; done
  xcrun simctl status_bar "$udid" clear
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  echo "Custom goals screenshots: $OUT"
  exit 0
fi

# Delete account: step one (the sheet) and step two (the final alert).
capture_deletion() {
  capture account-delete-row account "$1" -fixture-scroll-to fixture-account-delete
  capture delete-account account "$1" -delete-account
  capture delete-account-confirm account "$1" -delete-account-confirm
  capture delete-account-large-text account "$1" -delete-account -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
}
if [[ "${CAPTURE_DELETION_ONLY:-0}" == 1 ]]; then
  for appearance in light dark; do capture_deletion "$appearance"; done
  xcrun simctl status_bar "$udid" clear
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  echo "Delete account screenshots: $OUT"
  exit 0
fi

for appearance in light dark; do
  if [[ "${CAPTURE_EXTRAS_ONLY:-0}" != 1 ]]; then
    capture_deletion "$appearance"
    capture_goals "$appearance"
    for screen in sharedToday storageRecovery signIn createAccount confirmCode forgotPassword resetPassword checking setup today todayComplete history account; do
      capture "$screen" "$screen" "$appearance"
    done
  fi
  for screen in todayExtras extrasCap accountExtras; do
    capture "$screen" "$screen" "$appearance"
  done
  capture today-extras-detail todayExtras "$appearance" -fixture-scroll-to fixture-extras
  capture historyExtras historyExtras "$appearance" -fixture-scroll-to fixture-history-day
  capture historyExtrasEditing historyExtrasEditing "$appearance" -fixture-scroll-to fixture-history-day
  capture historyCarryOver historyCarryOver "$appearance" -fixture-scroll-to fixture-history-day
  capture manage-extras todayExtras "$appearance" -manage-extras
  [[ "${CAPTURE_EXTRAS_ONLY:-0}" == 1 ]] || capture manage-extras-empty today "$appearance" -manage-extras
  capture manage-extras-cap extrasCap "$appearance" -manage-extras
  capture manage-extras-large-text todayExtras "$appearance" -manage-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture manage-extras-actions-large-text todayExtras "$appearance" -manage-extras -fixture-scroll-to fixture-extra-actions -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture history-extras-large-text historyExtras "$appearance" -fixture-scroll-to fixture-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture today-extras-large-text todayExtras "$appearance" -fixture-scroll-to fixture-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture account-extras-large-text accountExtras "$appearance" -fixture-scroll-to fixture-account-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  capture history-carryover-large-text historyCarryOver "$appearance" -fixture-scroll-to fixture-extras -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  [[ "${CAPTURE_EXTRAS_ONLY:-0}" == 1 ]] || capture today-large-text today "$appearance" -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
done
xcrun simctl status_bar "$udid" clear
xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
echo "Screenshots: $OUT"
