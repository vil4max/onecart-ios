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

BACKEND="$(select_build_backend)"
echo "test backend: $BACKEND"

case "$BACKEND" in
  xcode_tools)
    exec "$HOST_BUILD_ROOT/build/xcode_tools/test.sh"
    ;;
  xcodebuild_mcp)
    exec "$HOST_BUILD_ROOT/build/mcp/test.sh"
    ;;
  swiftpm)
    exec "$HOST_BUILD_ROOT/build/swiftpm/test.sh"
    ;;
  xcodebuild|*)
    exec "$HOST_BUILD_ROOT/build/xcodebuild/test.sh"
    ;;
esac
