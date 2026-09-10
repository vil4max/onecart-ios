#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SRC="$ROOT/.githooks/pre-push"
HOOKS_DIR="$(git -C "$ROOT" rev-parse --git-path hooks)"
HOOK_DST="$HOOKS_DIR/pre-push"

if [[ ! -d "$HOOKS_DIR" ]]; then
  echo "Not a git checkout with .git/hooks" >&2
  exit 1
fi

cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST" "$HOOK_SRC" "$ROOT/scripts/smoke-tests.sh"
echo "Installed pre-push hook → .git/hooks/pre-push"
echo "Tag-only pushes and ref deletions skip smoke tests; branch updates run scripts/smoke-tests.sh"
