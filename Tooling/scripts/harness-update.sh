#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

HARNESS_ROOT="${IOS_AGENT_HARNESS_ROOT:-$HOME/Developer/GitHub/ios-agent-harness}"
if [[ ! -d "$HARNESS_ROOT/scripts" ]]; then
  echo "harness root not found: $HARNESS_ROOT (set IOS_AGENT_HARNESS_ROOT)" >&2
  exit 1
fi

CURRENT="0.0.0"
if [[ -f "$APP_ROOT/Tooling/.harness-version" ]]; then
  CURRENT="$(tr -d '[:space:]' <"$APP_ROOT/Tooling/.harness-version")"
elif [[ -f "$APP_ROOT/.harness-version" ]]; then
  CURRENT="$(tr -d '[:space:]' <"$APP_ROOT/.harness-version")"
fi
LATEST="$(tr -d '[:space:]' <"$HARNESS_ROOT/HARNESS_VERSION")"

echo "Current $CURRENT"
echo "Latest  $LATEST"

if [[ "$CURRENT" == "$LATEST" ]]; then
  echo "Already up to date."
  exit 0
fi

echo "Harness outdated. Updating slice…"
exec "$HARNESS_ROOT/scripts/install.sh" "$APP_ROOT" --personal --force
