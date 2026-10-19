#!/bin/bash
# Disposable native simulators only. No signing/upload, personal photos or deletion requests.
set -euo pipefail
phone="$1"
derived="$2"
out="$3"
phase="${4:-all}"
case "$phase" in all|iphone|expanded-window) ;; *) exit 2 ;; esac
mkdir -p "$out"
test_target=PhotoMaidUITests/PhotoGameVisualTests
test_targets=("-only-testing:$test_target")
if [ "${PM_GAME_SUITE:-all}" = snake ]; then
  test_targets=("-only-testing:$test_target/test20SnakeControlsFoodHighscoreAndPause"
                "-only-testing:$test_target/test40LargeTextAndArabic"
                "-only-testing:$test_target/test60SnakeRealtimeDriverAndPause")
elif [ "${PM_GAME_SUITE:-all}" != all ]; then
  exit 2
fi
if [ -n "${PM_GAME_CASE:-}" ]; then
  if [ "$PM_GAME_CASE" = setup ]; then
    test_targets=("-only-testing:$test_target/test05SimpleSetupCloudAndManualPhotoChoice"
                  "-only-testing:$test_target/test40LargeTextAndArabic")
  elif [ "$PM_GAME_CASE" = snake-cloud ]; then
    test_targets=("-only-testing:$test_target/test05SimpleSetupCloudAndManualPhotoChoice"
                  "-only-testing:$test_target/test20SnakeControlsFoodHighscoreAndPause"
                  "-only-testing:$test_target/test60SnakeRealtimeDriverAndPause")
  elif [ "$PM_GAME_CASE" = blocks ]; then
    test_targets=("-only-testing:PhotoMaidUITests/PhotoBlocksVisualTests"
                  "-only-testing:$test_target/test05SimpleSetupCloudAndManualPhotoChoice")
  elif [ "$PM_GAME_CASE" = blocks-only ]; then
    test_targets=("-only-testing:PhotoMaidUITests/PhotoBlocksVisualTests")
  elif [ "$PM_GAME_CASE" = feed ]; then
    test_targets=("-only-testing:$test_target/test70UnavailableVideosCanBePassed"
                  "-only-testing:$test_target/test80VideoPlaysWithoutPoster"
                  "-only-testing:$test_target/test85VideoPosterAllowsDecisionsBeforePlayback"
                  "-only-testing:$test_target/test90LoadingPhotoCanBePassed")
  else
    [[ "$PM_GAME_CASE" =~ ^test[0-9]{2}[A-Za-z0-9]+$ ]]
    test_target="$test_target/$PM_GAME_CASE"
    test_targets=("-only-testing:$test_target")
  fi
fi
if [ ! -d "$out/media" ]; then swift scripts/qa_game_media.swift "$out/media"; fi
# The full suite includes feed video regressions too; all selected cases need their real media.
if { [ -z "${PM_GAME_CASE:-}" ] || [ "$PM_GAME_CASE" = feed ]; } && [ ! -f "$out/media/QA_FEED_01.mp4" ]; then
  swift scripts/qa_feed_video.swift "$out/media"
fi
xcodebuild -version > "$out/xcode-version.txt"
xcrun --sdk iphonesimulator --show-sdk-version > "$out/sdk-version.txt"
run_device() {
  local udid="$1" name="$2"
  if [ "$name" = iphone ] && [ "${PM_GAME_USE_PREBOOTED_PHONE:-0}" = 1 ] && [ "${GITHUB_ACTIONS:-}" = true ]; then
    # This opt-in is only for the fresh disposable Actions runner after its in-memory unit tests.
    xcrun simctl terminate "$udid" com.mrdevn4ever.photomaid 2>/dev/null || true
    xcrun simctl uninstall "$udid" com.mrdevn4ever.photomaid 2>/dev/null || true
  else
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    xcrun simctl erase "$udid"
    xcrun simctl boot "$udid"
  fi
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override --time '9:41' --batteryState charged --batteryLevel 100
  xcrun simctl install "$udid" "$derived/Build/Products/Debug-iphonesimulator/PhotoMaid.app"
  xcrun simctl privacy "$udid" grant photos com.mrdevn4ever.photomaid
  xcrun simctl addmedia "$udid" "$out/media"/*
  set +e
  xcodebuild -project PhotoMaid.xcodeproj -scheme PhotoMaid -destination "id=$udid" \
    -derivedDataPath "$derived" -resultBundlePath "$out/$name.xcresult" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 300 \
    "${test_targets[@]}" -skipPackagePluginValidation -skipMacroValidation \
    TARGETED_DEVICE_FAMILY=1,2 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES \
    test-without-building 2>&1 | tee "$out/$name.log" | grep -E 'Test (Case|Suite)|error:|failed|passed|\*\* TEST'
  local status=${PIPESTATUS[0]}
  set -e
  echo "$status" > "$out/$name.exit"
  xcrun simctl spawn "$udid" log show --last 20m --style compact --predicate 'process == "PhotoMaid"' > "$out/$name-app.log" 2>&1 || true
  mkdir -p "$out/$name-diagnostics"
  for diagnostic in "$HOME"/Library/Logs/DiagnosticReports/PhotoMaid*.ips; do
    [ ! -f "$diagnostic" ] || cp "$diagnostic" "$out/$name-diagnostics/"
  done
  xcrun xcresulttool export attachments --path "$out/$name.xcresult" --output-path "$out/$name-attachments" || true
  # Preserve native crash reports before removing the result bundle, including the
  # simulator-side reports that are not in the host's ~/Library/Logs directory.
  if [ "$status" != 0 ]; then
    xcrun xcresulttool export diagnostics --path "$out/$name.xcresult" --output-path "$out/$name-diagnostics" || true
    find "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Logs" \
      -type f -name 'PhotoMaid*.ips' -exec cp {} "$out/$name-diagnostics/" \; 2>/dev/null || true
  fi
  xcrun xcresulttool get test-results summary --path "$out/$name.xcresult" > "$out/$name-summary.json" || true
  rm -rf "$out/$name.xcresult"
  xcrun simctl shutdown "$udid" || true
}
if [ "$phase" != expanded-window ]; then run_device "$phone" iphone; fi
if [ "$phase" = iphone ]; then test "$(cat "$out/iphone.exit")" = 0; exit; fi
# Use an actual Duo profile whenever the selected Xcode provides one, otherwise an explicit generic wide-window check.
wide=$(python3 - <<'PY'
import json,subprocess
r=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices']
for runtime,devices in r.items():
    if 'iOS' not in runtime: continue
    duo=next((d for d in devices if 'Duo' in d['name']),None)
    pad=next((d for d in devices if 'iPad mini' in d['name']),None)
    if duo or pad:
        print((duo or pad)['udid']);break
PY
)
if [ -z "$wide" ]; then
  echo 'No expanded-window simulator available' >&2
  exit 1
fi
xcrun simctl list devices available > "$out/simulator-inventory.txt"
xcodebuild -version > "$out/xcode-version.txt"
xcrun --sdk iphonesimulator --show-sdk-version > "$out/sdk-version.txt"
printf '%s\n' 'Expanded-window fallback is not fold/unfold verification. Native Duo requires Xcode/iOS 27.1 SDK and its device profile.' > "$out/duo-validation-scope.txt"
run_device "$wide" expanded-window
rm -rf "$out/media"
if [ "$phase" = all ]; then test "$(cat "$out/iphone.exit")" = 0; fi
test "$(cat "$out/expanded-window.exit")" = 0
