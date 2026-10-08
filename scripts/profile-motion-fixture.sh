#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Everything stays in this checkout; never install, launch, or stop the real app.
fixture="$PWD/.build/motion-fixture"
app="$fixture/Daily Challenge Motion FIXTURE.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$fixture/data"
xcrun swiftc -swift-version 6 -O -parse-as-library -emit-library -emit-module \
  -module-name ChallengeCore Sources/ChallengeCore/*.swift \
  -emit-module-path "$fixture/ChallengeCore.swiftmodule" \
  -Xlinker -install_name -Xlinker @rpath/libChallengeCore.dylib \
  -o "$app/Contents/Frameworks/libChallengeCore.dylib"
xcrun swiftc -swift-version 6 -O -parse-as-library -I "$fixture" \
  -L "$app/Contents/Frameworks" -lChallengeCore \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  Sources/DailyChallengeProof/{JerseyDates,TrackerMotion,PopupVisibility,WaterJugView,CompletionEffect}.swift \
  scripts/motion-fixture-visibility.swift scripts/motion-fixture.swift -o "$app/Contents/MacOS/MotionFixture"
/usr/bin/plutil -create xml1 "$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string app.daily-challenge.motion-fixture "$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleExecutable -string MotionFixture "$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleName -string 'Daily Challenge Motion FIXTURE' "$app/Contents/Info.plist"
/usr/bin/plutil -replace LSUIElement -bool YES "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
for mode in motion baseline; do
  args=(--motion)
  if [[ "$mode" == baseline ]]; then args=(--no-motion); fi
  /usr/bin/sw_vers > "$fixture/$mode-results.txt"
  "$app/Contents/MacOS/MotionFixture" "${args[@]}" >> "$fixture/$mode-results.txt" 2>&1 &
  pid=$!
  # Sample only the process we launched. These decaying ps percentages are
  # supplementary; acceptance uses the fixture's cumulative CPU-time deltas.
  printf 'timestamp pid cpu-percent\n' > "$fixture/$mode-ps-samples.txt"
  while kill -0 "$pid" 2>/dev/null; do
    printf '%s ' "$(date +%s)" >> "$fixture/$mode-ps-samples.txt"
    ps -p "$pid" -o pid=,%cpu= >> "$fixture/$mode-ps-samples.txt" || true
    sleep 1
  done
  wait "$pid"
done
printf 'Evidence: %s/{motion,baseline}-results.txt and *-ps-samples.txt\n' "$fixture"
