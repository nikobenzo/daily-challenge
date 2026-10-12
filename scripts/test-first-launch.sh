#!/usr/bin/env bash
# First-launch regression check and welcome-window captures (docs/tracker-interface.md#first-launch).
# Build first:
#   scripts/build-proof.sh --adhoc        # a placeholder .env.local is enough
#
# 1. Opens an isolated copy of build/Daily Challenge.app with `open`, as site/install.sh
#    does, and fails if the launch shows any window other than the expected one: before
#    the fix, a SwiftUI Settings scene opened an empty 900 x 450 "Daily Challenge Settings"
#    window at every launch. The copy has its own bundle ID, no Configuration.json (so no
#    Supabase client, Keychain or network) and no update feed. It still lists the real
#    challenge folder's file names, as the app does to recognise an existing user: with a
#    challenge file there it must open no window, otherwise only the welcome window.
# 2. Runs the welcome screens of the developer probe (PopupProbe.swift) on offline
#    fixtures in Light and Dark and checks each launch's windows: a new person and someone
#    signed in without a challenge get the welcome window only; an existing user and an
#    upgraded install get no window; starting the challenge celebrates, stores that setup
#    is done and closes the window by itself.
# Never touches the installed app, a real account, the Keychain or real challenge files.
#   --docs   also copy the captures and reports into docs/screenshots/onboarding/
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
[[ -d "$SOURCE" ]] || { echo "Missing $SOURCE; run scripts/build-proof.sh --adhoc first." >&2; exit 1; }
WORK="$ROOT/.build/first-launch"
APP="$WORK/Daily Challenge FIRSTRUN.app"
OUT="$WORK/out"
BUNDLE_ID=app.daily-challenge.first-launch-probe
EXE="$APP/Contents/MacOS/DailyChallengeProof"
rm -rf "$WORK"
mkdir -p "$OUT"
ditto "$SOURCE" "$APP"
rm -f "$APP/Contents/Resources/Configuration.json"
plist="$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$plist"
/usr/bin/plutil -replace CFBundleName -string 'Daily Challenge FIRSTRUN' "$plist"
/usr/bin/plutil -replace CFBundleDisplayName -string 'Daily Challenge FIRSTRUN' "$plist"
/usr/bin/plutil -remove SUFeedURL "$plist" 2>/dev/null || true
/usr/bin/plutil -remove SUPublicEDKey "$plist" 2>/dev/null || true
codesign --force --sign - "$APP" 2>/dev/null
cleanup() {
  pkill -f "$EXE" 2>/dev/null || true
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  defaults delete app.daily-challenge.popup-probe.defaults >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
}
trap cleanup EXIT
cleanup
FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

# --- 1. The installer's launch path: `open` on a fresh copy, no saved state.
LISTER="$WORK/list-windows"
cat > "$WORK/list-windows.swift" <<'SWIFT'
import CoreGraphics
import Foundation
// The on-screen, normal-level windows of one process. Names need Screen Recording
// permission for the terminal; without it they read as "?".
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in list where (window[kCGWindowOwnerPID as String] as? Int32) == pid && (window[kCGWindowLayer as String] as? Int) == 0 {
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    print("\(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0))\t\(window[kCGWindowName as String] as? String ?? "?")")
}
SWIFT
swiftc -O "$WORK/list-windows.swift" -o "$LISTER" 2>/dev/null
if compgen -G "$HOME/Library/Application Support/DailyChallenge/ujyvvyrugenknhjodfhc/challenge-*.json" >/dev/null; then
  expected=0; who="existing user on this Mac"
else
  expected=1; who="new person"
fi
open -n "$APP"
pid=""
for _ in $(seq 1 20); do pid="$(pgrep -f "$EXE" | head -n 1 || true)"; [[ -n "$pid" ]] && break; sleep 0.25; done
[[ -n "$pid" ]] || { echo "The copy did not start." >&2; exit 1; }
sleep 4
"$LISTER" "$pid" > "$OUT/open-launch-windows.txt"
kill "$pid" 2>/dev/null || true
count="$(grep -c . "$OUT/open-launch-windows.txt" || true)"
echo "open launch ($who): $count window(s) on screen"; sed 's/^/  /' "$OUT/open-launch-windows.txt"
grep -q 'Settings' "$OUT/open-launch-windows.txt" && fail "a Settings window opened at launch"
grep -q '^900x450' "$OUT/open-launch-windows.txt" && fail "an empty 900 x 450 window (the Settings scene's size) opened at launch"
[[ "$count" == "$expected" ]] || fail "expected $expected window(s) for this launch ($who), saw $count"
if (( expected == 1 )) && ! grep -q -E 'Welcome to Daily Challenge|\?$' "$OUT/open-launch-windows.txt"; then
  fail "the window that opened is not the welcome window"
fi
sleep 1

# --- 2. Welcome screens on offline fixtures.
run() { # screen appearance [reduce-motion]
  local name="$1-$2${3:+-reduce-motion}" pid
  rm -f "$OUT/$name.json" "$OUT/$name"*.png
  DAILY_CHALLENGE_POPUP_PROBE="$OUT" DAILY_CHALLENGE_POPUP_PROBE_SCREEN="$1" \
    DAILY_CHALLENGE_POPUP_PROBE_APPEARANCE="$2" DAILY_CHALLENGE_POPUP_PROBE_REDUCE_MOTION="${3:-}" \
    "$EXE" >"$OUT/$name.log" 2>&1 &
  pid=$!
  for _ in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; fail "timed out: $name"; fi
  wait "$pid" 2>/dev/null || true
  sleep 1
  [[ -f "$OUT/$name.json" ]] || { fail "no report for $name (see $OUT/$name.log)"; return; }
  python3 - "$OUT/$name.json" "$1" <<'PY' || FAILED=1
import json, sys
report, screen = json.load(open(sys.argv[1])), sys.argv[2]
shown = [w for w in report["launchWindows"] if w["visible"] and w["class"] != "NSStatusBarWindow"]
names = [f'{w["class"]} "{w["title"]}"' for w in shown]
problems = []
if any("Settings" in w["title"] for w in report["launchWindows"]):
    problems.append("a Settings window exists")
if screen in ("welcome-existing", "welcome-upgraded"):
    if shown: problems.append(f"expected no window, saw {names}")
elif [w["class"] for w in shown] != ["DailyChallengeProof.WelcomeWindow"]:
    problems.append(f"expected only the welcome window, saw {names}")
if screen == "welcome-done":
    if not report.get("popupOpened"): problems.append("the welcome button did not open the popup")
    if not report.get("closedItself"): problems.append("the welcome window did not close itself")
    if report.get("firstRunAfter") != "finished": problems.append(f'first run is {report.get("firstRunAfter")} after setup')
    if [w for w in report.get("windowsAfter", []) if w["visible"] and w["class"] == "DailyChallengeProof.WelcomeWindow"]:
        problems.append("the welcome window is still visible")
print(f'{screen}: {report["firstRun"]}; windows {names or "none"}' + (f'; capture {report["capture"]}' if "capture" in report else ""))
for problem in problems: print(f"FAIL: {screen}: {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
}
for appearance in light dark; do
  for screen in welcome welcome-signed-in welcome-done welcome-existing welcome-upgraded; do run "$screen" "$appearance"; done
done
# Reduce Motion: the celebration without confetti.
run welcome-done light 1
sw_vers > "$OUT/macos.txt"

if (( DOCS )); then
  DEST=docs/screenshots/onboarding
  mkdir -p "$DEST"
  rm -f "$DEST"/welcome*
  # The welcome-done launch's first capture is the same screen as welcome-signed-in.
  for file in "$OUT"/welcome*.png "$OUT"/welcome*.json "$OUT/macos.txt"; do
    case "$(basename "$file")" in welcome-done-light.png|welcome-done-dark.png|welcome-done-light-reduce-motion.png) continue ;; esac
    cp "$file" "$DEST/"
  done
fi
printf 'First-launch reports and captures: %s\n' "$OUT"
if (( FAILED )); then echo "First-launch check FAILED." >&2; exit 1; fi
echo "First-launch check passed."
