#!/usr/bin/env bash
# Deletes shut-down "Clone N of <device>" simulators this app's test runs left
# behind (killed or hung runs do not remove them). Only this app's devices are
# touched; other apps' clones and every booted device are left alone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

/usr/bin/python3 "$SCRIPT_DIR/sim-device.py" clean "$(sim_test_name)" "$(sim_name)"
