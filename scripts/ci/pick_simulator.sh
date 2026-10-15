#!/bin/bash
# Gibt die UDID des neuesten verfügbaren iPhone-Simulators aus (bevorzugt „iPhone 17“).
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
requested = sys.argv[1].replace(".", "-")
best = None
for runtime, devs in devices.items():
    if "iOS" not in runtime:
        continue
    if requested and not runtime.endswith("iOS-" + requested):
        continue
    version = tuple(int(x) for x in runtime.split("iOS-")[-1].split("-"))
    for dev in devs:
        if not dev["name"].startswith("iPhone"):
            continue
        rank = (version, dev["name"] == "iPhone 17", dev["name"])
        if best is None or rank > best[0]:
            best = (rank, dev["udid"])
if best is None:
    sys.exit("No available iPhone simulator for " + (requested or "the latest runtime"))
print(best[1])
' "${PM_SIM_RUNTIME:-}"
