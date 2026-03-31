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
declare -a NAMES CHECKS DESCS OPTIONALS
current_group=""

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; echo "$s"; }

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

  name="$(trim "${line%%:::*}")"
  rest="${line#*:::}"
  check="$(trim "${rest%%:::*}")"
  rest="${rest#*:::}"
  desc="$(trim "${rest%%:::*}")"
  rest="${rest#*:::}"
  flag="$(trim "$rest")"

  [[ -z "$name" || -z "$check" ]] && continue

  optional=false
  [[ "$flag" == "optional" ]] && optional=true

  NAMES+=("${current_group}::${name}")
  CHECKS+=("$check")
  DESCS+=("$desc")
  OPTIONALS+=("$optional")
done < "$TOOLS_CONF"

# --------------------------------------------------------------------------
# Run checks
# --------------------------------------------------------------------------
declare -a INSTALLED MISSING_REQUIRED MISSING_OPTIONAL

total=${#NAMES[@]}
ok_count=0
missing_required_count=0
missing_optional_count=0

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
  optional="${OPTIONALS[$i]}"

  if eval "$check" > /dev/null 2>&1; then
    status="installed"
    ok_count=$((ok_count + 1))
    INSTALLED+=("$name")
  else
    status="missing"
    if $optional; then
      missing_optional_count=$((missing_optional_count + 1))
      MISSING_OPTIONAL+=("$name")
    else
      missing_required_count=$((missing_required_count + 1))
      MISSING_REQUIRED+=("$name")
    fi
  fi

  if $JSON_OUTPUT; then
    $first || printf ',\n'
    first=false
    printf '  {"name": "%s", "group": "%s", "status": "%s", "optional": %s, "description": "%s"}' \
      "$name" "$group" "$status" "$optional" "$desc"
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
  elif $optional; then
    printf "  ${YELLOW}~${RESET}  %-22s  %s ${YELLOW}(optional)${RESET}\n" "$name" "$desc"
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

missing_count=$((missing_required_count + missing_optional_count))

if [[ $missing_count -eq 0 ]]; then
  printf "${GREEN}${BOLD}All $total tools are installed.${RESET}\n"
else
  printf "${BOLD}%d/%d tools installed.${RESET}\n" "$ok_count" "$total"
  if [[ $missing_required_count -gt 0 ]]; then
    printf "  ${RED}Missing (required): %s${RESET}\n" "$(IFS=', '; echo "${MISSING_REQUIRED[*]}")"
  fi
  if [[ $missing_optional_count -gt 0 ]]; then
    printf "  ${YELLOW}Missing (optional): %s${RESET}\n" "$(IFS=', '; echo "${MISSING_OPTIONAL[*]}")"
  fi
fi

# Exit 1 only if required tools are missing (useful in CI or scripting)
[[ $missing_required_count -eq 0 ]]
