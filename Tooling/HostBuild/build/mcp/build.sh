#!/usr/bin/env bash
set -euo pipefail
echo "XcodeBuildMCP execute adapter is optional and not auto-selected in 0.1." >&2
echo "Set backend.prefer: xcodebuild_mcp only when the provider is healthy, or use just build (xcodebuild)." >&2
exit 1
