#!/bin/bash
# Owner/developer reproduction on a DISPOSABLE iPhone 17 / iOS 27 simulator only.
# UI is driven solely by SpringBoard XCUITest. No auth/Keychain/network is used.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
: "${WIDGET_SIMULATOR_ID:?Supply the UDID of a disposable iPhone 17 / iOS 27 simulator}"
APPEARANCE="${APPEARANCE:-light}"
OUT="$ROOT/docs/screenshots/ios/widgets"
MODE="${WIDGET_CAPTURE_MODE:-placement}"
case "$MODE" in
  placement) SCHEME=WidgetCapture; METHOD=testPlaceWidgets ;;
  # Phase 4: place three kinds, terminate the app, tap widget controls, relaunch.
  actions) SCHEME=WidgetCapture; METHOD=testWidgetActionsOffline ;;
  gallery) SCHEME=WidgetGalleryCapture; METHOD=testCaptureGalleryOnly ;;
  # Phase 5: optionally place layout a|b (WIDGET_PLACE=1), then relaunch each fixture
  # variant in WIDGET_VARIANTS and capture the placed widgets. Text size and Increase
  # Contrast are simulator settings applied here; WIDGET_HOME_STYLE=tinted|clear is
  # switched through SpringBoard's Customize sheet.
  phase5) SCHEME=WidgetCapture; METHOD=testPhase5Home
    export TEST_RUNNER_WIDGET_LAYOUT="${WIDGET_LAYOUT:-a}" TEST_RUNNER_WIDGET_PLACE="${WIDGET_PLACE:-0}"
    export TEST_RUNNER_WIDGET_VARIANTS="${WIDGET_VARIANTS:-partial}"
    [[ -n "${WIDGET_TAG:-}" ]] && export TEST_RUNNER_WIDGET_TAG="$WIDGET_TAG"
    [[ -n "${WIDGET_HOME_STYLE:-}" ]] && export TEST_RUNNER_WIDGET_HOME_STYLE="$WIDGET_HOME_STYLE"
    xcrun simctl ui "$WIDGET_SIMULATOR_ID" content_size "${CONTENT_SIZE:-large}"
    xcrun simctl ui "$WIDGET_SIMULATOR_ID" increase_contrast "${INCREASE_CONTRAST:-disabled}" ;;
  # Phase 5 Lock Screen: add the water ring to the Cover Sheet and capture WIDGET_VARIANTS.
  lock) SCHEME=WidgetCapture; METHOD=testPhase5LockScreen
    export TEST_RUNNER_WIDGET_VARIANTS="${WIDGET_VARIANTS:-partial}" ;;
  *) echo "Expected WIDGET_CAPTURE_MODE=placement|actions|gallery|phase5|lock" >&2; exit 2 ;;
esac
RESULT="$ROOT/.build/widget-$MODE-$APPEARANCE-$(date +%s).xcresult"
mkdir -p "$OUT"
xcrun simctl ui "$WIDGET_SIMULATOR_ID" appearance "$APPEARANCE"
# Failure is retained as evidence; do not automatically retry placement indefinitely.
xcodebuild test -project iOS/DailyChallenge.xcodeproj -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$WIDGET_SIMULATOR_ID" \
  -derivedDataPath "$ROOT/.build/widget-capture-derived" \
  -only-testing:"DailyChallengeUITests/WidgetPlacementUITests/$METHOD" \
  -collect-test-diagnostics never -resultBundlePath "$RESULT" || result=$?
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$RESULT-attachments" >/dev/null
python3 iOS/scripts/export-widget-attachments.py "$RESULT-attachments" "$OUT" "$APPEARANCE"
exit "${result:-0}"
