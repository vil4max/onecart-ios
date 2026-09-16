#!/usr/bin/env bash
# Starts booting the CI test simulator in the background and exports its UDID.
#
# Usage: scripts/ci-boot-simulator.sh <device-name> <ios-version>
#
# A fresh hosted runner spends minutes on the first simulator boot. Starting it
# before the cache restore and build lets both happen in parallel; the test step
# then waits with `xcrun simctl bootstatus "$SIM_UDID" -b`.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <device-name> <ios-version>" >&2
  exit 64
fi

udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name, version = sys.argv[1], sys.argv[2]
runtime = "com.apple.CoreSimulator.SimRuntime.iOS-" + version.replace(".", "-")
devices = json.load(sys.stdin)["devices"].get(runtime, [])
print(next((d["udid"] for d in devices if d["name"] == name), ""))
' "$1" "$2")"

if [[ -z "$udid" ]]; then
  echo "no available simulator named '$1' on iOS $2" >&2
  xcrun simctl list devices available >&2
  exit 1
fi

echo "booting $1 (iOS $2): $udid"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "SIM_UDID=$udid" >> "$GITHUB_ENV"
fi
nohup xcrun simctl bootstatus "$udid" -b > "${RUNNER_TEMP:-/tmp}/simulator-boot.log" 2>&1 &
