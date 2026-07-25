#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

"$SCRIPT_DIR/format.sh"
"$SCRIPT_DIR/lint.sh"
"$SCRIPT_DIR/build.sh"
"$SCRIPT_DIR/test.sh"

if cfg_bool todo_scan false; then
  if have rg; then
    if rg -n 'TODO\(|FIXME\(|#warning' --glob '*.swift' "$(project_root)" ; then
      echo "todo_scan found markers" >&2
      exit 1
    fi
  fi
fi

echo "verify OK (DoD)"
