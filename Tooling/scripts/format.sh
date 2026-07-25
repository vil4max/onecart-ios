#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if ! cfg_bool format true; then
  echo "format skipped (Tooling/runtime.yml format: false)"
  exit 0
fi

if ! have swiftformat; then
  echo "swiftformat not installed — brew bundle --file=Tooling/Brewfile" >&2
  exit 1
fi

ROOT="$(project_root)"
CONF="$TOOLING_ROOT/.swiftformat"
[[ -f "$CONF" ]] || CONF="$RUNTIME_ROOT/templates/swiftformat"
swiftformat "$ROOT" --config "$CONF"
