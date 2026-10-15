#!/bin/bash
# Two isolated, disposable simulator runs. NEVER requests deletion of PhotoKit assets.
# Run after build-for-testing; only Google's public test ad IDs from project.yml.
set -euo pipefail
udid="$1"
derived="$2"
out="$3"
phase="${4:-all}"
case "$phase" in all|fixtures|real|real-start|real-rest|real-case) ;; *) echo "Unknown UI phase: $phase" >&2; exit 2 ;; esac
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
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES "$@" test-without-building 2>&1 | tee "$out/$mode.log"
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

pack_result() {
  local mode="$1"
  if [ -d "$out/$mode.xcresult" ]; then
    ditto -c -k --keepParent "$out/$mode.xcresult" "$out/$mode.xcresult.zip"
    rm -rf "$out/$mode.xcresult"
  fi
}

if [ "$phase" = all ] || [ "$phase" = fixtures ]; then
  reset_simulator
  swift scripts/qa_media.swift "$out/qa-media"
  xcrun simctl addmedia "$udid" "$out/qa-media"/*
  if [ "${PM_QA_CASE:-all}" = vault ]; then
    run_tests fixtures -only-testing:PhotoMaidUITests/VaultDeletionTests
  elif [ "${PM_QA_CASE:-all}" = vault-media ]; then
    run_tests fixtures -only-testing:PhotoMaidUITests/VaultDeletionTests/test10PhotosAndVideosSwipeAndSelection \
      -only-testing:PhotoMaidUITests/VaultDeletionTests/test11ViewerContinuesAfterDeletion \
      -only-testing:PhotoMaidUITests/VaultDeletionTests/test12ViewerControlsPhotoZoomAndVideo
  elif [ "${PM_QA_CASE:-all}" = editor ]; then
    run_tests fixtures -only-testing:PhotoMaidUITests/ScreenshotTests/testZoomedPhotoMarkupAndUndo
  else
    run_tests fixtures -only-testing:PhotoMaidUITests/PhotoMaidUITests -only-testing:PhotoMaidUITests/ScreenshotTests \
      -only-testing:PhotoMaidUITests/VaultDeletionTests
  fi
  pack_result fixtures
  rm -rf "$out/qa-media"
fi

if [ "$phase" = all ] || [ "$phase" = real ] || [ "$phase" = real-start ]; then
  reset_simulator
  xcrun simctl io "$udid" screenshot "$out/simulator-source.png"
  python3 scripts/ci/real_test_media.py "$out/real-media" --screenshot "$out/simulator-source.png"
  find "$out/real-media" -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.mp4' \) -print0 |
    xargs -0 xcrun simctl addmedia "$udid"
  case "${PM_UI_CASE:-all}" in
    all|test60LibraryFiltersSortAndAspect)
      bash scripts/ci/native_screenshot.sh "$udid" "$out/real-start-native-screenshot" ;;
  esac
  xcrun simctl spawn "$udid" log show --last 1s --style compact > "$out/seed.log" || true
fi

if [ "$phase" = real-start ]; then
  run_tests real-start -only-testing:PhotoMaidUITests/RealLibraryTests/test00IntroductionAndFourColdStarts
  xcrun simctl spawn "$udid" log show --last 20m --style compact \
    --predicate 'process == "PhotoMaid"' > "$out/real-start-app.log" || true
  pack_result real-start
  [ "$(cat "$out/real-start.exit")" = 0 ]
  exit
fi

if [ "$phase" = real-case ]; then
  test_case="${5:?Missing real-library test method}"
  [[ "$test_case" =~ ^test[0-9]{2}[A-Za-z0-9]+$ ]]
  test -f "$out/real-start.exit"
  mode="real-$test_case"
  run_tests "$mode" "-only-testing:PhotoMaidUITests/RealLibraryTests/$test_case"
  xcrun simctl spawn "$udid" log show --last 20m --style compact \
    --predicate 'process == "PhotoMaid"' > "$out/$mode-app.log" || true
  if [ "$test_case" = test20FiftyFastSwipesAdAndDirections ] && [ "$(cat "$out/$mode.exit")" = 0 ]; then
    if ! python3 scripts/ci/verify_ad_gesture_log.py "$out/$mode-app.log" > "$out/$mode-ad-timing.txt" 2>&1; then
      cat "$out/$mode-ad-timing.txt"
      echo 1 > "$out/$mode.exit"
    fi
  fi
  pack_result "$mode"
  [ "$(cat "$out/$mode.exit")" = 0 ]
  exit
fi

if [ "$phase" = all ] || [ "$phase" = real ] || [ "$phase" = real-rest ]; then
  if [ "$phase" = real-rest ]; then
    # Keep the same imported library and app data; no fixture launch arguments.
    test -f "$out/real-start.exit"
    run_tests real -only-testing:PhotoMaidUITests/RealLibraryTests \
      -skip-testing:PhotoMaidUITests/RealLibraryTests/test00IntroductionAndFourColdStarts
  else
    run_tests real -only-testing:PhotoMaidUITests/RealLibraryTests
  fi
  xcrun simctl spawn "$udid" log show --last 2h --style compact \
    --predicate 'process == "PhotoMaid"' > "$out/app.log" || true
  pack_result real
fi

[ "$phase" != fixtures ] || { [ "$(cat "$out/fixtures.exit")" = 0 ]; exit; }
if [ "$phase" = real ] || [ "$phase" = real-rest ]; then
  [ "$(cat "$out/real.exit")" = 0 ]
  exit
fi
[ "$(cat "$out/fixtures.exit")" = 0 ] && [ "$(cat "$out/real.exit")" = 0 ]
