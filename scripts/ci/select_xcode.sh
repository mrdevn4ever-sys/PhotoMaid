#!/bin/bash
# Wählt das neueste stabile Xcode 27 auf dem GA-Runner (keine Beta/RC).
set -euo pipefail
ls -d /Applications/Xcode*.app
XCODE=$(ls -d /Applications/Xcode_27*.app 2>/dev/null | grep -viE 'beta|rc|release_candidate' | sort -V | tail -1 || true)
[ -n "$XCODE" ] || { echo '::error::Kein stabiles Xcode 27 installiert.'; exit 1; }
sudo xcode-select -s "$XCODE"
VERSION=$(xcodebuild -version)
printf '%s\n' "$VERSION"
XCODE_VERSION=${VERSION%%$'\n'*}
if ! [[ "$XCODE_VERSION" =~ ^Xcode[[:space:]]27(\.[0-9]+)*$ ]]; then
  echo "::error::Stabiles Xcode 27 erforderlich: $XCODE ($VERSION)"
  exit 1
fi
xcodebuild -showsdks | grep -iE "ios|simulator"
for platform in iphoneos iphonesimulator; do
  SDK=$(xcrun --sdk "$platform" --show-sdk-version)
  if [ "${SDK%%.*}" != 27 ]; then
    echo "::error::$platform-SDK $SDK ist nicht 27 – Runner-Image prüfen."
    exit 1
  fi
done
