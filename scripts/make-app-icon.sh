#!/usr/bin/env bash
# Regenerates the app icon master, the committed iconset and the iPhone icon from source.
# build-proof.sh only packs the committed iconset; run this after editing render-app-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
master=Resources/AppIcon/icon_1024.png
iconset=Resources/AppIcon.iconset
mkdir -p "$(dirname "$master")"
swift scripts/render-app-icon.swift "$master"
rm -rf "$iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$master" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  if [[ $double -eq 1024 ]]; then
    cp "$master" "$iconset/icon_${size}x${size}@2x.png"
  else
    sips -z "$double" "$double" "$master" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  fi
done
# Prove the iconset packs before anyone commits it.
check="$(mktemp -d)"
trap 'rm -rf "$check"' EXIT
iconutil -c icns "$iconset" -o "$check/AppIcon.icns"
# The iPhone icon: the same tile full-bleed and opaque, in the iOS app's asset catalog.
ios_icon=iOS/DailyChallenge/Assets.xcassets/AppIcon.appiconset/icon_1024.png
swift scripts/render-app-icon.swift --ios "$ios_icon"
echo "wrote $master, $iconset and $ios_icon"
