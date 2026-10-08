#!/usr/bin/env bash
# Stages a built, notarized build/DailyChallenge.zip as a Sparkle update and
# regenerates releases/appcast.xml. It uploads nothing: afterwards, upload
# releases/appcast.xml and the new zip to the feed host (docs/releases.md).
#   --download-url-prefix <url>  where the zip will be downloadable, if not next to
#                                the appcast (for example a GitHub release's URL)
#   --ed-key-file <file>         sign with a private EdDSA key file instead of the
#                                login Keychain item generate_keys created (testing)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APPCAST_ARGS=()
while (( $# )); do
  case "$1" in
    --download-url-prefix|--ed-key-file)
      [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 2; }
      APPCAST_ARGS+=("$1" "$2"); shift 2 ;;
    *) echo "Unknown option: $1 (expected --download-url-prefix <url> or --ed-key-file <file>)" >&2; exit 2 ;;
  esac
done
ZIP="$ROOT/build/DailyChallenge.zip"
RELEASES="$ROOT/releases"
GENERATE_APPCAST="$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -f "$ZIP" ]]; then
  echo 'Missing build/DailyChallenge.zip. Run scripts/build-proof.sh (without --adhoc) first.' >&2
  exit 1
fi
if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "Missing $GENERATE_APPCAST. Run swift package resolve to fetch Sparkle's tools." >&2
  exit 1
fi
# Inspect the app inside the zip: it must be the notarized build of this VERSION,
# with an update feed, or friends' copies would refuse or never see it.
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
ditto -x -k "$ZIP" "$CHECK"
APP="$CHECK/Daily Challenge.app"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null || true; }
SHORT="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
version_file() { sed -n "s/^[[:space:]]*$1=//p" VERSION | tail -n 1 | tr -d '[:space:]'; }
if [[ "$SHORT" != "$(version_file CFBundleShortVersionString)" || "$BUILD" != "$(version_file CFBundleVersion)" ]]; then
  echo "The zip holds version $SHORT ($BUILD), but VERSION says otherwise. Rebuild with scripts/build-proof.sh." >&2
  exit 1
fi
if [[ -z "$(plist SUFeedURL)" || -z "$(plist SUPublicEDKey)" ]]; then
  echo 'The zipped app has no SUFeedURL/SUPublicEDKey, so it could not update itself. Rebuild without --adhoc.' >&2
  exit 1
fi
if ! xcrun stapler validate "$APP" >/dev/null; then
  echo 'The zipped app is not notarized and stapled. Rebuild with scripts/build-proof.sh (not --adhoc or --skip-notarize).' >&2
  exit 1
fi
mkdir -p "$RELEASES"
# Sparkle compares CFBundleVersion, so a shipped number must never be reused.
TARGET="$RELEASES/DailyChallenge-$SHORT-$BUILD.zip"
for existing in "$RELEASES"/*.zip "$RELEASES"/old_updates/*.zip; do
  [[ -f "$existing" && "$existing" != "$TARGET" ]] || continue
  if [[ "$(basename "$existing" .zip)" == *"-$BUILD" ]]; then
    echo "CFBundleVersion $BUILD is already staged as $(basename "$existing"). Raise it in VERSION and rebuild." >&2
    exit 1
  fi
done
if [[ -f "$TARGET" ]] && ! cmp -s "$ZIP" "$TARGET"; then
  echo "$(basename "$TARGET") is already staged with different contents; raise CFBundleVersion in VERSION and rebuild." >&2
  exit 1
fi
cp "$ZIP" "$TARGET"
# No delta updates: each release is then just one zip plus appcast.xml to upload.
"$GENERATE_APPCAST" --maximum-deltas 0 ${APPCAST_ARGS[@]+"${APPCAST_ARGS[@]}"} "$RELEASES"
printf '\nStaged version %s (%s).\nUpload these two files to the feed host:\n  %s\n  %s\n' \
  "$SHORT" "$BUILD" "$RELEASES/appcast.xml" "$TARGET"
