#!/bin/bash
# Wählt das neueste stabile Xcode auf dem macOS-Runner (keine Beta/RC) und protokolliert SDKs.
set -euo pipefail
ls -d /Applications/Xcode*.app
XCODE=$(ls -d /Applications/Xcode_*.app 2>/dev/null | grep -viE 'beta|rc|release_candidate' | sort -V | tail -1 || true)
[ -z "$XCODE" ] && XCODE=/Applications/Xcode.app
sudo xcode-select -s "$XCODE"
xcodebuild -version
xcodebuild -showsdks | grep -iE "ios|simulator"
SDK=$(xcrun --sdk iphoneos --show-sdk-version)
if [ "${SDK%%.*}" -lt 26 ]; then
  echo "::error::iOS-SDK $SDK ist älter als 26 – Liquid-Glass-APIs fehlen. Runner-Image prüfen."
  exit 1
fi
