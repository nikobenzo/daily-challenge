#!/usr/bin/env bash
# Installs the latest Daily Challenge for Mac from GitHub Releases:
#   curl -fsSL https://nikobenzo.github.io/daily-challenge/install.sh | bash
#
# It downloads the release zip, checks that the app is signed by the owner's
# Developer ID and notarized by Apple (a curl download skips the quarantine
# check Gatekeeper does for browser downloads, so this script does it),
# installs it to /Applications (or ~/Applications if that is not writable),
# and opens it. Nothing is installed if any check fails. It never uses sudo.
#
# Testing overrides (not for normal use):
#   DC_INSTALL_DIR  install here instead; the running app is not quit or opened
#   DC_ZIP_URL      use this zip (https:// or file://) instead of the latest release
set -euo pipefail

REPO="nikobenzo/daily-challenge"
TEAM_ID="L644Y3WX5T"
MIN_MACOS_MAJOR=14
APP_NAME="Daily Challenge.app"

die() { echo "Error: $*" >&2; exit 1; }
say() { echo "$*"; }

[ "$(uname -s)" = "Darwin" ] || die "Daily Challenge for Mac only installs on macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge "$MIN_MACOS_MAJOR" ] || die "Daily Challenge needs macOS $MIN_MACOS_MAJOR or newer (this Mac has $(sw_vers -productVersion))."
[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ] || die "Daily Challenge for Mac needs an Apple silicon Mac."

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dailychallenge-install.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fetch() { curl --proto '=https' --tlsv1.2 -fsSL "$@"; }

ZIP_URL="${DC_ZIP_URL:-}"
if [ -z "$ZIP_URL" ]; then
  say "Finding the latest release..."
  # The releases/latest API needs no token and skips drafts and prereleases.
  # The zip is the asset named DailyChallenge-<version>-<build>.zip for the latest tag.
  json="$(fetch "https://api.github.com/repos/$REPO/releases/latest")" || die "Could not reach GitHub to find the latest release."
  tag="$(printf '%s\n' "$json" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
  version="${tag#v}"
  [ -n "$version" ] || die "Could not read the latest release version from GitHub."
  ZIP_URL="$(printf '%s\n' "$json" | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p' \
    | grep -E "^https://github\.com/$REPO/releases/download/[^/]+/DailyChallenge-${version}-[0-9]+\.zip$" | head -n 1 || true)"
  [ -n "$ZIP_URL" ] || die "The latest release ($tag) has no Mac download."
elif [ -n "${DC_ZIP_URL:-}" ]; then
  case "$ZIP_URL" in https://*|file://*) ;; *) die "DC_ZIP_URL must start with https:// or file://." ;; esac
fi

say "Downloading $(basename "$ZIP_URL")..."
if [ "${ZIP_URL#file://}" != "$ZIP_URL" ]; then
  cp "${ZIP_URL#file://}" "$TMP/app.zip" || die "Could not read the zip."
else
  fetch -o "$TMP/app.zip" "$ZIP_URL" || die "Download failed."
fi

# ditto keeps the symlinks inside frameworks intact; unzip would break the signature.
mkdir "$TMP/extract"
ditto -x -k "$TMP/app.zip" "$TMP/extract" || die "Could not unpack the download."
APP="$TMP/extract/$APP_NAME"
[ -d "$APP" ] || die "The download does not contain $APP_NAME."

say "Checking the signature and notarization..."
codesign --verify --deep --strict "$APP" 2>/dev/null || die "The app's signature is not valid. Nothing was installed."
team="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[ "$team" = "$TEAM_ID" ] || die "The app is not signed by the Daily Challenge developer (team '${team:-none}'). Nothing was installed."
assessment="$(spctl --assess --type execute -vv "$APP" 2>&1)" || die "macOS Gatekeeper does not accept the app. Nothing was installed."
case "$assessment" in *"source=Notarized Developer ID"*) ;; *) die "The app is not notarized by Apple. Nothing was installed." ;; esac
say "  Signed by team $team, notarized by Apple."

if [ -n "${DC_INSTALL_DIR:-}" ]; then
  DEST_DIR="$DC_INSTALL_DIR"
  mkdir -p "$DEST_DIR"
elif [ -w /Applications ]; then
  DEST_DIR="/Applications"
else
  DEST_DIR="$HOME/Applications"
  mkdir -p "$DEST_DIR"
fi
[ -w "$DEST_DIR" ] || die "Cannot write to $DEST_DIR."

if [ -z "${DC_INSTALL_DIR:-}" ]; then
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  bid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  if [ -n "$exe" ] && [ -n "$bid" ] && pgrep -x "$exe" >/dev/null 2>&1; then
    say "Quitting the running Daily Challenge..."
    osascript -e "tell application id \"$bid\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      pgrep -x "$exe" >/dev/null 2>&1 || break
      sleep 0.5
    done
    pgrep -x "$exe" >/dev/null 2>&1 && die "Daily Challenge is still running. Quit it and run this again."
  fi
fi

# Stage next to the target, then swap, so a failed copy never removes a working install.
STAGE="$DEST_DIR/.Daily Challenge.install.$$"
rm -rf "$STAGE"
ditto "$APP" "$STAGE" || { rm -rf "$STAGE"; die "Could not copy the app to $DEST_DIR."; }
if ! codesign --verify --deep --strict "$STAGE" 2>/dev/null; then rm -rf "$STAGE"; die "The copied app failed verification. Nothing was installed."; fi
rm -rf "$DEST_DIR/$APP_NAME"
mv "$STAGE" "$DEST_DIR/$APP_NAME"
say "Installed to $DEST_DIR/$APP_NAME"

if [ -z "${DC_INSTALL_DIR:-}" ]; then
  open "$DEST_DIR/$APP_NAME"
  say "Opened Daily Challenge. Look for it in the menu bar."
fi
