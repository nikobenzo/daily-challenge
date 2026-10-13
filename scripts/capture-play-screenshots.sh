#!/bin/sh
# Capture the Google Play phone screenshots' sources into docs/screenshots/android/play/ from the
# Debug fixtures (docs/android.md, Debug fixtures and screenshots) on an Android emulator, then
# render them with scripts/render-play-assets.py.
#
# The fixtures are offline: personalised goals (customGoals) and an in-memory server (synced), so
# nothing signs in or reaches the hosted server. Use the Android 10 (API 29) emulator at 1080 x 2280
# and 440 dpi, the geometry render-play-assets.py crops:
#
#   emulator -avd dc-api29 -no-window -no-audio -read-only &
#   (cd android && ./gradlew assembleDebug) && adb -s emulator-NNNN install -r android/app/build/outputs/apk/debug/app-debug.apk
#   ANDROID_SERIAL=emulator-NNNN scripts/capture-play-screenshots.sh
set -eu

case "${ANDROID_SERIAL:-}" in
    emulator-*) ;;
    *) echo "Set ANDROID_SERIAL to an emulator (emulator-NNNN); never capture on a phone." >&2; exit 1 ;;
esac
size=$(adb shell wm size | tr -d '\r')
case "$size" in
    *1080x2280) ;;
    *) echo "Expected a 1080 x 2280 emulator, got: $size" >&2; exit 1 ;;
esac

out="$(cd "$(dirname "$0")/.." && pwd)/docs/screenshots/android/play"
mkdir -p "$out"
for setting in window_animation_scale transition_animation_scale animator_duration_scale; do
    adb shell settings put global "$setting" 0
done
# The listing is en-GB: 24-hour times on Account, as on the sync chip.
adb shell settings put system time_12_24 24

# capture NAME SWIPE-FROM SWIPE-TO EXTRAS...: launch the fixture, optionally scroll with a slow
# swipe (no fling), and save the screen.
capture() {
    name=$1 from=$2 to=$3
    shift 3
    adb shell am start -S -W -n app.dailychallenge.android/.MainActivity --ez customGoals true --ez synced true "$@" >/dev/null
    sleep 4
    if [ "$from" != - ]; then
        adb shell input swipe 540 "$from" 540 "$to" 2000
        sleep 2
    fi
    adb exec-out screencap -p > "$out/$name.png"
    echo "$name"
}

capture today-light - - --es fixture todayRepeating --es appearance light
capture daily-goals-light - - --es fixture account --ez dailyGoals true --es appearance light
capture repeat-light 1800 800 --es fixture todayRepeating --ez manageExtras true --es editExtra 'Call\ family' --es appearance light
capture history-light - - --es fixture history --es appearance light
capture setup-light - - --es fixture setup --es appearance light
capture today-complete-light - - --es fixture todayComplete --es appearance light
capture account-light - - --es fixture account --es appearance light
capture today-dark 1600 1250 --es fixture todayRepeating --es appearance dark
# Leave the emulator on the real app's launch screen rather than a fixture.
adb shell am force-stop app.dailychallenge.android
