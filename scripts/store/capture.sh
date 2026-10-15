#!/bin/bash
set -euo pipefail
udid="$1"; derived="$2"; out="$3"
mkdir -p "$out"
python3 scripts/store/record_controller.py "$udid" "$out" > "$out/recorder.log" 2>&1 &
recorder=$!
trap 'kill "$recorder" 2>/dev/null || true; wait "$recorder" 2>/dev/null || true' EXIT
cases=(-only-testing:PhotoMaidUITests/AppStoreCaptureTests)
if [ "$CAPTURE_MODE" = screenshots ]; then
  cases=(-only-testing:PhotoMaidUITests/AppStoreCaptureTests/test00EveryPageInDarkMode)
fi
# Preview retries retain the actual screenshot-run app data only within this job; never fake vault state.
if [ "$CAPTURE_MODE" = previews ]; then
  echo 'A fresh simulator needs the full capture to set up the real vault.' >&2
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
xcrun xcresulttool get test-results summary --path "$out/capture.xcresult" > "$out/summary.json" || true
xcrun xcresulttool get test-results tests --path "$out/capture.xcresult" > "$out/tests.json" || true
xcrun simctl spawn "$udid" log show --last 90m --style compact --predicate 'process == "PhotoMaid"' > "$out/app.log" || true
if [ "$status" != 0 ]; then tail -100 "$out/tests.log"; fi
exit "$status"
