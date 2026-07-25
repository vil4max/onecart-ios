#!/usr/bin/env bash
set -euo pipefail

SCRIPT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Tooling/scripts → repo root is ../..
if [[ "$(basename "$(dirname "$SCRIPT_HOME")")" == "Tooling" ]]; then
  ROOT="$(cd "$SCRIPT_HOME/../.." && pwd)"
else
  ROOT="$(cd "$SCRIPT_HOME/.." && pwd)"
fi
export RUNTIME_ROOT="${RUNTIME_ROOT:-$ROOT}"
export TOOLING_ROOT="$ROOT/Tooling"
export HOST_BUILD_ROOT="$TOOLING_ROOT/HostBuild"

have() { command -v "$1" >/dev/null 2>&1; }

runtime_config_path() {
  if [[ -f "$TOOLING_ROOT/runtime.yml" ]]; then
    echo "$TOOLING_ROOT/runtime.yml"
  elif [[ -f "$PWD/runtime.yml" ]]; then
    echo "$PWD/runtime.yml"
  elif [[ -f "$RUNTIME_ROOT/templates/runtime.yml" ]]; then
    echo "$RUNTIME_ROOT/templates/runtime.yml"
  else
    echo ""
  fi
}

runtime_local_path() {
  if [[ -f "$TOOLING_ROOT/runtime.local.yml" ]]; then
    echo "$TOOLING_ROOT/runtime.local.yml"
  elif [[ -f "$PWD/runtime.local.yml" ]]; then
    echo "$PWD/runtime.local.yml"
  else
    echo ""
  fi
}

cfg_get() {
  local key="$1"
  local default="${2:-}"
  local file local_file
  file="$(runtime_config_path)"
  if [[ -z "$file" ]]; then
    echo "$default"
    return 0
  fi
  if have yq; then
    local v
    v="$(yq -r ".$key // \"\"" "$file" 2>/dev/null || true)"
    local_file="$(runtime_local_path)"
    if [[ -n "$local_file" ]]; then
      local lv
      lv="$(yq -r ".$key // \"\"" "$local_file" 2>/dev/null || true)"
      if [[ -n "$lv" && "$lv" != "null" ]]; then
        v="$lv"
      fi
    fi
    if [[ -z "$v" || "$v" == "null" ]]; then
      echo "$default"
    else
      echo "$v"
    fi
  else
    echo "$default"
  fi
}

cfg_bool() {
  local key="$1"
  local default="${2:-true}"
  local v
  v="$(cfg_get "$key" "$default")"
  case "$v" in
    true|True|TRUE|yes|1) return 0 ;;
    *) return 1 ;;
  esac
}

project_root() {
  echo "${PROJECT_ROOT:-$PWD}"
}

find_xcodeproj() {
  local root
  root="$(project_root)"
  local explicit
  explicit="$(cfg_get project "")"
  if [[ -n "$explicit" && -e "$root/$explicit" ]]; then
    echo "$root/$explicit"
    return 0
  fi
  local found
  found="$(find "$root" -maxdepth 2 -name '*.xcodeproj' ! -path '*/.*' 2>/dev/null | head -n 1 || true)"
  echo "$found"
}

find_xcworkspace() {
  local root
  root="$(project_root)"
  local explicit
  explicit="$(cfg_get workspace "")"
  if [[ -n "$explicit" && -e "$root/$explicit" ]]; then
    echo "$root/$explicit"
    return 0
  fi
  local found
  found="$(find "$root" -maxdepth 2 -name '*.xcworkspace' ! -path '*/.*' ! -path '*.xcodeproj/*' 2>/dev/null | head -n 1 || true)"
  echo "$found"
}

scheme_name() {
  local s
  s="$(cfg_get scheme "")"
  if [[ -n "$s" ]]; then
    echo "$s"
    return 0
  fi
  local proj
  proj="$(find_xcodeproj)"
  if [[ -n "$proj" ]]; then
    basename "$proj" .xcodeproj
    return 0
  fi
  echo ""
}

sim_name() {
  cfg_get "simulator.name" "iPhone 17"
}

destination_spec() {
  local name
  name="$(sim_name)"
  echo "platform=iOS Simulator,name=${name}"
}

harness_version() {
  if [[ -f "$RUNTIME_ROOT/HARNESS_VERSION" ]]; then
    tr -d '[:space:]' <"$RUNTIME_ROOT/HARNESS_VERSION"
  elif [[ -f "$TOOLING_ROOT/.harness-version" ]]; then
    tr -d '[:space:]' <"$TOOLING_ROOT/.harness-version"
  elif [[ -f "$PWD/.harness-version" ]]; then
    tr -d '[:space:]' <"$PWD/.harness-version"
  else
    echo "0.0.0"
  fi
}
