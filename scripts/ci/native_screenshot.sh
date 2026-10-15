#!/bin/bash
# Public Simulator menu, equivalent to pressing the iPhone's screenshot buttons.
# Unlike `simctl io screenshot` + addmedia, this creates PhotoKit's screenshot subtype.
set -euo pipefail
udid="$1"
out="$2"
mkdir -p "$out"
roll="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Media/DCIM"
find "$roll" -type f > "$out/camera-roll-before.txt" 2>/dev/null || true
xcrun simctl launch "$udid" com.apple.mobileslideshow
sleep 5
xcrun simctl io "$udid" screenshot "$out/before.png"
# A running Simulator ignores CurrentDeviceUDID. Open the selected Xcode's app afresh.
osascript -e 'tell application "Simulator" to quit'
for attempt in {1..20}; do
  if ! pgrep -x Simulator > /dev/null; then break; fi
  sleep 0.25
done
simulator_app="$(xcode-select -p)/Applications/Simulator.app"
open -n -a "$simulator_app" --args -CurrentDeviceUDID "$udid"
osascript > "$out/menu.log" 2>&1 <<'APPLESCRIPT'
with timeout of 20 seconds
  tell application "Simulator" to activate
  delay 5
  tell application "System Events"
    tell process "Simulator"
      set frontmost to true
      if not enabled of menu item "Trigger Screenshot" of menu "Device" of menu bar 1 then error "Screenshot menu is disabled"
      click menu item "Trigger Screenshot" of menu "Device" of menu bar 1
      delay 8
    end tell
  end tell
end timeout
APPLESCRIPT
xcrun simctl io "$udid" screenshot "$out/after.png"
sleep 8
xcrun simctl io "$udid" screenshot "$out/after-settled.png"
find "$roll" -type f > "$out/camera-roll-after.txt" 2>/dev/null || true
python3 - "$out" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
before = set((out / 'camera-roll-before.txt').read_text().splitlines())
after = set((out / 'camera-roll-after.txt').read_text().splitlines())
added = sorted(after - before)
(out / 'created-files.txt').write_text('\n'.join(added) + '\n')
assert any(pathlib.Path(p).suffix.lower() == '.png' for p in added), 'Native screenshot was not saved'
print('Native screenshot saved through the public Simulator menu')
PY
# Leave the screenshot preview without deleting anything or launching PhotoMaid early.
osascript >> "$out/menu.log" 2>&1 <<'APPLESCRIPT'
tell application "System Events" to tell process "Simulator"
  click menu item "Home" of menu "Device" of menu bar 1
end tell
APPLESCRIPT
