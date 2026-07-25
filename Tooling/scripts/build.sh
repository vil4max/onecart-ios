#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
# shellcheck source=capabilities.sh
source "$SCRIPT_DIR/capabilities.sh"

BACKEND="$(select_build_backend)"
echo "build backend: $BACKEND"

case "$BACKEND" in
  xcode_tools)
    exec "$HOST_BUILD_ROOT/build/xcode_tools/build.sh"
    ;;
  xcodebuild_mcp)
    exec "$HOST_BUILD_ROOT/build/mcp/build.sh"
    ;;
  swiftpm)
    exec "$HOST_BUILD_ROOT/build/swiftpm/build.sh"
    ;;
  xcodebuild|*)
    exec "$HOST_BUILD_ROOT/build/xcodebuild/build.sh"
    ;;
esac
