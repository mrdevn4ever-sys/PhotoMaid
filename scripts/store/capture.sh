#!/bin/bash
set -euo pipefail
udid="$1"; derived="$2"; out="$3"
mkdir -p "$out"
python3 scripts/store/record_controller.py "$udid" "$out" > "$out/recorder.log" 2>&1 &
recorder=$!
trap 'kill "$recorder" 2>/dev/null || true; wait "$recorder" 2>/dev/null || true' EXIT
cases=(-only-testing:PhotoMaidUITests/AppStoreCaptureTests/test00EveryPageInDarkMode
       -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test01DetailPagesInDarkMode
       -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test10AppPreviewReview
       -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test20AppPreviewStudio
       -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test30AppPreviewVault)
if [ "$CAPTURE_MODE" = screenshots ]; then
  cases=(-only-testing:PhotoMaidUITests/AppStoreCaptureTests/test00EveryPageInDarkMode
         -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test01DetailPagesInDarkMode)
elif [ "$CAPTURE_MODE" = previews ]; then
  cases=(-only-testing:PhotoMaidUITests/AppStoreCaptureTests/test05PrepareMediaForPreviews
         -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test10AppPreviewReview
         -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test20AppPreviewStudio
         -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test30AppPreviewVault)
elif [ "$CAPTURE_MODE" = refresh ]; then
  cases=(-only-testing:PhotoMaidUITests/AppStoreCaptureTests/test06CurrentStoreScreenshots
         -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test10AppPreviewReview
         -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test20AppPreviewStudio
         -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test30AppPreviewVault
         -only-testing:PhotoMaidUITests/AppStoreCaptureTests/test40AppPreviewPhotoGames)
elif [ "$CAPTURE_MODE" = refresh-screenshots ]; then
  cases=(-only-testing:PhotoMaidUITests/AppStoreCaptureTests/test06CurrentStoreScreenshots)
fi
set +e
TEST_RUNNER_STORE_CAPTURE_LOCALE="$CAPTURE_LOCALE" TEST_RUNNER_STORE_CAPTURE_DIR="$out" xcodebuild \
  -project PhotoMaid.xcodeproj -scheme PhotoMaid -destination "id=$udid" -derivedDataPath "$derived" \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -enableCodeCoverage NO -resultBundlePath "$out/capture.xcresult" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 2700 -maximum-test-execution-time-allowance 3600 \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES \
  -skipPackagePluginValidation -skipMacroValidation "${cases[@]}" test-without-building > "$out/tests.log" 2>&1
status=$?
set -e
container=$(xcrun simctl get_app_container "$udid" com.mrdevn4ever.photomaid data)
[ ! -f "$container/Documents/store-library.json" ] || cp "$container/Documents/store-library.json" "$out/library.json"
xcrun xcresulttool get test-results summary --path "$out/capture.xcresult" > "$out/summary.json" || true
xcrun xcresulttool get test-results tests --path "$out/capture.xcresult" > "$out/tests.json" || true
xcrun simctl spawn "$udid" log show --last 90m --style compact --predicate 'process == "PhotoMaid"' > "$out/app.log" || true
if [ "$status" != 0 ]; then
  mkdir -p "$out/diagnostics/crashes"
  for report in "$HOME/Library/Logs/DiagnosticReports"/PhotoMaid*.ips; do
    [ ! -f "$report" ] || cp "$report" "$out/diagnostics/crashes/"
  done
  xcrun xcresulttool export attachments --path "$out/capture.xcresult" --output-path "$out/diagnostics" || true
  tail -100 "$out/tests.log"
fi
exit "$status"
