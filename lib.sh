#!/usr/bin/env bash
# lib.sh - Shared constants and helpers for dotfiles scripts.
# Source with: source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$REPO_DIR/conf"
USER_HOME_DIR="$REPO_DIR/user_home"
ROOT_DIR="$REPO_DIR/root"
APPEND_CONF="$CONF_DIR/append.conf"
TOOLS_CONF="$CONF_DIR/tools.conf"
HOOKS_CONF="$CONF_DIR/hooks.conf"

MARKER_BEGIN="# ===== BEGIN DOTFILES SYNC ====="
MARKER_END="# ===== END DOTFILES SYNC ====="

# --------------------------------------------------------------------------
# Colors
# --------------------------------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'
BOLD='\033[1m'

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

# Trim leading/trailing whitespace in-place via nameref.
# Usage: trim varname
trim() {
  local -n _trim_ref=$1
  _trim_ref="${_trim_ref#"${_trim_ref%%[![:space:]]*}"}"
  _trim_ref="${_trim_ref%"${_trim_ref##*[![:space:]]}"}"
}

# Populate global APPEND_FILES associative array from append.conf.
load_append_files() {
  declare -gA APPEND_FILES=()
  [[ ! -f "$APPEND_CONF" ]] && return
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -z "$line" ]] && continue
    APPEND_FILES["$line"]=1
  done < "$APPEND_CONF"
}

# Return true if the given relative path (e.g. user_home/.bashrc) is in append mode.
is_append() {
  [[ -n "${APPEND_FILES[$1]+_}" ]]
}
