#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
# shellcheck source=capabilities.sh
source "$SCRIPT_DIR/capabilities.sh"

if ! cfg_bool tests true; then
  echo "tests skipped (runtime.yml tests: false)"
  exit 0
fi

[[ -n "$BACKEND_ROOT" ]] || { echo "backend root missing — expected Tooling/backend or ./backend" >&2; exit 1; }

BACKEND="$(select_build_backend)"
echo "test backend: $BACKEND"

run_tests() {
  case "$BACKEND" in
    xcode_tools)
      "$BACKEND_ROOT/build/xcode_tools/test.sh"
      ;;
    xcodebuild_mcp)
      "$BACKEND_ROOT/build/mcp/test.sh"
      ;;
    swiftpm)
      "$BACKEND_ROOT/build/swiftpm/test.sh"
      ;;
    xcodebuild|*)
      "$BACKEND_ROOT/build/xcodebuild/test.sh"
      ;;
  esac
}

# Pre-boot the configured simulator so the test runner does not fail to launch
# with a transient Mach error (-308, "server died") on a cold/Shutdown simulator.
boot_simulator() {
  local name id
  name="$(sim_name)"
  id="$(
    xcrun simctl list devices available -j 2>/dev/null \
      | /usr/bin/python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for devices in data.get('devices', {}).values():
    for d in devices:
        if d.get('name') == name and d.get('isAvailable', True):
            print(d['udid'])
            raise SystemExit(0)
" "$name" 2>/dev/null || true
  )"
  if [[ -n "$id" ]]; then
    # -b boots if needed and blocks until the simulator is ready.
    xcrun simctl bootstatus "$id" -b 2>/dev/null || xcrun simctl boot "$id" 2>/dev/null || true
  fi
}

boot_simulator

# Retry once: a cold simulator can fail to launch the test runner on the first try.
if run_tests; then
  exit 0
fi

echo "test run failed; retrying once after simulator pre-boot" >&2
sleep 3
boot_simulator
run_tests
