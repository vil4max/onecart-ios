#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$PWD}"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
NAME="$(basename "$REPO_ROOT")"
CURSOR_REPO="${CURSOR_REPO:-$HOME/Developer/GitHub/cursor-agent-kit}"
HARNESS_REPO="${IOS_AGENT_HARNESS_ROOT:-$HOME/Developer/GitHub/ios-agent-harness}"

CONTEXT_DIR="$REPO_ROOT/.cursor"
CONTEXT_FILE="$CONTEXT_DIR/project-context"
AGENTS_FILE="$REPO_ROOT/AGENTS.md"

mkdir -p "$CONTEXT_DIR"

if [[ ! -f "$CONTEXT_FILE" ]]; then
  printf 'personal\n' >"$CONTEXT_FILE"
  echo "created $CONTEXT_FILE"
else
  echo "exists $CONTEXT_FILE"
fi

if [[ ! -f "$AGENTS_FILE" ]]; then
  README_HINT=""
  if [[ -f "$REPO_ROOT/README.md" ]]; then
    README_HINT="See [README.md](README.md)."
  fi
  cat >"$AGENTS_FILE" <<EOF
# ${NAME} — agent notes (thin)

**Project context:** \`personal\` — marker: \`.cursor/project-context\`.

${README_HINT}

## Config

Scheme / simulator / backend: \`runtime.yml\` (see Runtime install).

## Brain (Cursor)

Rules and skills: \`${CURSOR_REPO}/\` — \`./scripts/cursor-skills-rules-toggle.sh on\`.

## Runtime

\`${HARNESS_REPO}/\` — \`just doctor\`, \`just verify\`.

## Notes

- \`.cursor/\` stays local (not in git).
- \`AGENTS.md\` may be committed (thin project facts).
EOF
  echo "created $AGENTS_FILE"
else
  echo "exists $AGENTS_FILE"
fi

echo "done: $REPO_ROOT"
