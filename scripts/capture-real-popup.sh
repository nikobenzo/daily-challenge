#!/usr/bin/env bash
# Opens the REAL menu-bar popup of an isolated copy of build/Daily Challenge.app and
# writes the popup window's own rendering and geometry for every screen in Light and Dark
# (docs/appearance-verification.md#real-popup-probe). Build first:
#   scripts/build-proof.sh --adhoc --skip-notarize
# The copy gets its own bundle ID, no Configuration.json and no update feed, and runs on
# offline fixtures inside .build/real-popup-probe: never the installed app, a real
# account, the Keychain or ~/Library/Application Support/DailyChallenge*.
#   --docs   also copy the PNGs, their geometry reports and the resize traces into
#            docs/screenshots/real-popup/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DOCS=0
for arg in "$@"; do
  case "$arg" in
    --docs) DOCS=1 ;;
    *) echo "Unknown option: $arg (expected --docs)" >&2; exit 2 ;;
  esac
done
SOURCE="$ROOT/build/Daily Challenge.app"
[[ -d "$SOURCE" ]] || { echo "Missing $SOURCE; run scripts/build-proof.sh --adhoc --skip-notarize first." >&2; exit 1; }
WORK="$ROOT/.build/real-popup-probe"
APP="$WORK/Daily Challenge PROBE.app"
OUT="$WORK/out"
BUNDLE_ID=app.daily-challenge.popup-probe
rm -rf "$WORK"
mkdir -p "$OUT"
ditto "$SOURCE" "$APP"
rm -f "$APP/Contents/Resources/Configuration.json"
plist="$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$plist"
/usr/bin/plutil -replace CFBundleName -string 'Daily Challenge PROBE' "$plist"
/usr/bin/plutil -replace CFBundleDisplayName -string 'Daily Challenge PROBE' "$plist"
/usr/bin/plutil -remove SUFeedURL "$plist" 2>/dev/null || true
/usr/bin/plutil -remove SUPublicEDKey "$plist" 2>/dev/null || true
codesign --force --sign - "$APP" 2>/dev/null
cleanup() {
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  defaults delete "$BUNDLE_ID.defaults" >/dev/null 2>&1 || true
}
trap cleanup EXIT
run() { # screen appearance [steps]
  local pid
  rm -f "$OUT/$1-$2.png" "$OUT/$1-$2-FAILED.txt"
  DAILY_CHALLENGE_POPUP_PROBE="$OUT" DAILY_CHALLENGE_POPUP_PROBE_SCREEN="$1" \
    DAILY_CHALLENGE_POPUP_PROBE_APPEARANCE="$2" DAILY_CHALLENGE_POPUP_PROBE_STEPS="${3:-}" \
    "$APP/Contents/MacOS/DailyChallengeProof" >"$OUT/$1-$2.log" 2>&1 &
  pid=$!
  # The probe quits itself; never wait on it forever.
  for _ in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "Timed out: $1 $2" >&2; fi
  wait "$pid" 2>/dev/null || true
  # Let the system settle activation after the quit: another app activating closes the
  # popup, as it should, and would close the next copy's popup mid-capture.
  sleep 1
  if [[ -f "$OUT/$1-$2-FAILED.txt" || ! -f "$OUT/$1-$2.png" ]]; then
    echo "Probe failed for $1 $2: $(cat "$OUT/$1-$2-FAILED.txt" 2>/dev/null || echo "no capture, see $OUT/$1-$2.log")" >&2
    return 1
  fi
}
for appearance in light dark; do
  for screen in setup today history account sign-in; do run "$screen" "$appearance"; done
  run today "$appearance" history,account,today
done
sw_vers > "$OUT/macos.txt"
if (( DOCS )); then
  DEST=docs/screenshots/real-popup
  mkdir -p "$DEST"
  for appearance in light dark; do
    for screen in setup today history account sign-in; do
      cp "$OUT/$screen-$appearance.png" "$OUT/$screen-$appearance.json" "$DEST/"
    done
    cp "$OUT"/today-"$appearance"-*-to-*.json "$DEST/"
  done
  cp "$OUT/macos.txt" "$DEST/"
fi
printf 'Real-popup captures and geometry: %s\n' "$OUT"
