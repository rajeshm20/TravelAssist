#!/usr/bin/env bash
set -euo pipefail

PROJECT="TravelAssist.xcodeproj"
SCHEME="TravelAssist"

pick_destination() {
  local sim_json
  sim_json="$(xcrun simctl list devices available -j)"

  python3 -c '
import json
import re
import sys

data = json.load(sys.stdin)
devices = data.get("devices", {})

def parse_runtime(runtime_id):
    match = re.search(r"iOS-(\d+)-(\d+)", runtime_id)
    if not match:
        return None
    return (int(match.group(1)), int(match.group(2)))

best = None

for runtime_id, runtime_devices in devices.items():
    runtime_version = parse_runtime(runtime_id)

    if runtime_version is None:
        continue

    for device in runtime_devices:
        if not device.get("isAvailable", False):
            continue

        name = device.get("name", "")

        if not name.startswith("iPhone"):
            continue

        os_string = f"{runtime_version[0]}.{runtime_version[1]}"
        candidate = (runtime_version, name, os_string)

        if best is None or candidate[0] > best[0]:
            best = candidate

if best is None:
    print("platform=iOS Simulator,name=iPhone 16")
else:
    print(f"platform=iOS Simulator,name={best[1]},OS={best[2]}")
' <<<"$sim_json"
}

DESTINATION="$(pick_destination)"

echo "Using destination: ${DESTINATION}"

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination "${DESTINATION}" \
  -sdk iphonesimulator \
  clean test
