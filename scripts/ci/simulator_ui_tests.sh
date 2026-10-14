#!/bin/bash
# Two isolated, disposable simulator runs. NEVER requests deletion of PhotoKit assets.
# Run after build-for-testing; only Google's public test ad IDs from project.yml.
set -euo pipefail
udid="$1"
derived="$2"
out="$3"
mkdir -p "$out"
app="$derived/Build/Products/Debug-iphonesimulator/PhotoMaid.app"

reset_simulator() {
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  xcrun simctl erase "$udid"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override --time '9:41' --batteryState charged --batteryLevel 100
  xcrun simctl install "$udid" "$app"
  xcrun simctl privacy "$udid" grant photos com.mrdevn4ever.photomaid
}

run_tests() {
  local mode="$1"
  shift
  set +e
  TEST_RUNNER_SCREENSHOT_DIR="$out/$mode/screenshots" xcodebuild \
    -project PhotoMaid.xcodeproj -scheme PhotoMaid \
    -destination "id=$udid" -derivedDataPath "$derived" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -resultBundlePath "$out/$mode.xcresult" \
    -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO "$@" test-without-building 2>&1 | tee "$out/$mode.log"
  local status=${PIPESTATUS[0]}
  set -e
  echo "$status" > "$out/$mode.exit"
  mkdir -p "$out/$mode/attachments"
  xcrun xcresulttool export attachments --path "$out/$mode.xcresult" \
    --output-path "$out/$mode/attachments" || true
  xcrun xcresulttool get test-results summary --path "$out/$mode.xcresult" \
    > "$out/$mode-summary.json" || true
  xcrun xcresulttool get test-results tests --path "$out/$mode.xcresult" \
    > "$out/$mode-tests.json" || true
}

reset_simulator
swift scripts/qa_media.swift "$out/qa-media"
xcrun simctl addmedia "$udid" "$out/qa-media"/*
run_tests fixtures -only-testing:PhotoMaidUITests/PhotoMaidUITests -only-testing:PhotoMaidUITests/ScreenshotTests

reset_simulator
xcrun simctl io "$udid" screenshot "$out/simulator-source.png"
python3 scripts/ci/real_test_media.py "$out/real-media" --screenshot "$out/simulator-source.png"
find "$out/real-media" -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.mp4' \) -print0 |
  xargs -0 xcrun simctl addmedia "$udid"
# Allow Photos to finish indexing before launch (no mocked permission or library).
xcrun simctl spawn "$udid" log show --last 1s --style compact > "$out/seed.log" || true
run_tests real -only-testing:PhotoMaidUITests/RealLibraryTests
xcrun simctl spawn "$udid" log show --last 2h --style compact \
  --predicate 'process == "PhotoMaid"' > "$out/app.log" || true
# xcresult remains available in the artifact, alongside exported PNG attachments.
ditto -c -k --keepParent "$out/fixtures.xcresult" "$out/fixtures.xcresult.zip"
ditto -c -k --keepParent "$out/real.xcresult" "$out/real.xcresult.zip"
rm -rf "$out/fixtures.xcresult" "$out/real.xcresult" "$out/qa-media"
[ "$(cat "$out/fixtures.exit")" = 0 ] && [ "$(cat "$out/real.exit")" = 0 ]
