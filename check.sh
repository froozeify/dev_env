#!/usr/bin/env bash
# check.sh - Verify required tools are installed on this machine
#
# Usage:
#   ./check.sh              Check all tools
#   ./check.sh --missing    Show only missing tools
#   ./check.sh --json       Output as JSON (for scripting)

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_CONF="$REPO_DIR/tools.conf"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'
BOLD='\033[1m'

# --------------------------------------------------------------------------
# Parse arguments
# --------------------------------------------------------------------------
MISSING_ONLY=false
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --missing) MISSING_ONLY=true ;;
    --json)    JSON_OUTPUT=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$TOOLS_CONF" ]]; then
  echo "Error: tools.conf not found at $TOOLS_CONF" >&2
  exit 1
fi

# --------------------------------------------------------------------------
# Parse tools.conf
# --------------------------------------------------------------------------
declare -a NAMES CHECKS DESCS
current_group=""

while IFS= read -r raw_line; do
  # Detect group headers (comments starting with # ---)
  if [[ "$raw_line" =~ ^#[[:space:]]*---[[:space:]]*(.+)[[:space:]]*---[[:space:]]*$ ]]; then
    current_group="${BASH_REMATCH[1]}"
    continue
  fi

  # Strip full-line comments and empty lines
  line="${raw_line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"  # ltrim
  line="${line%"${line##*[![:space:]]}"}"  # rtrim
  [[ -z "$line" ]] && continue

  name="${line%%:::*}"
  rest="${line#*:::}"
  check="${rest%%:::*}"
  desc="${rest#*:::}"

  # Trim each field
  name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
  check="${check#"${check%%[![:space:]]*}"}"; check="${check%"${check##*[![:space:]]}"}"
  desc="${desc#"${desc%%[![:space:]]*}"}"; desc="${desc%"${desc##*[![:space:]]}"}"

  [[ -z "$name" || -z "$check" ]] && continue

  NAMES+=("${current_group}::${name}")
  CHECKS+=("$check")
  DESCS+=("$desc")
done < "$TOOLS_CONF"

# --------------------------------------------------------------------------
# Run checks
# --------------------------------------------------------------------------
declare -a INSTALLED MISSING
declare -A GROUP_RESULTS  # group -> "ok" or "missing"

total=${#NAMES[@]}
ok_count=0
missing_count=0

if $JSON_OUTPUT; then
  printf '[\n'
  first=true
fi

prev_group=""

for i in "${!NAMES[@]}"; do
  group="${NAMES[$i]%%::*}"
  name="${NAMES[$i]##*::}"
  check="${CHECKS[$i]}"
  desc="${DESCS[$i]}"

  if eval "$check" > /dev/null 2>&1; then
    status="installed"
    ok_count=$((ok_count + 1))
    INSTALLED+=("$name")
  else
    status="missing"
    missing_count=$((missing_count + 1))
    MISSING+=("$name")
  fi

  if $JSON_OUTPUT; then
    $first || printf ',\n'
    first=false
    printf '  {"name": "%s", "group": "%s", "status": "%s", "description": "%s"}' \
      "$name" "$group" "$status" "$desc"
    continue
  fi

  if $MISSING_ONLY && [[ "$status" == "installed" ]]; then
    continue
  fi

  # Print group header when it changes
  if [[ "$group" != "$prev_group" ]]; then
    [[ -n "$prev_group" ]] && echo ""
    printf "${CYAN}${BOLD}%s${RESET}\n" "$group"
    prev_group="$group"
  fi

  if [[ "$status" == "installed" ]]; then
    printf "  ${GREEN}✓${RESET}  %-22s  %s\n" "$name" "$desc"
  else
    printf "  ${RED}✗${RESET}  %-22s  ${YELLOW}%s${RESET}\n" "$name" "$desc"
  fi
done

if $JSON_OUTPUT; then
  printf '\n]\n'
  exit 0
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "──────────────────────────────────────"

if [[ $missing_count -eq 0 ]]; then
  printf "${GREEN}${BOLD}All $total tools are installed.${RESET}\n"
else
  printf "${BOLD}%d/%d tools installed.${RESET}" "$ok_count" "$total"
  printf "  ${RED}Missing: %s${RESET}\n" "$(IFS=', '; echo "${MISSING[*]}")"
fi

# Exit 1 if anything is missing (useful in CI or scripting)
[[ $missing_count -eq 0 ]]
