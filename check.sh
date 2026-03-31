#!/usr/bin/env bash
# check.sh - Verify required and optional tools are installed on this machine.
#
# Usage:
#   ./check.sh              Check all tools
#   ./check.sh --missing    Show only missing tools
#   ./check.sh --json       Output as JSON (for scripting)

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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
# Parse tools.conf into parallel arrays
# --------------------------------------------------------------------------
declare -a NAMES CHECKS DESCS OPTIONALS
current_group=""

while IFS= read -r raw_line; do
  # Group header: # --- Group Name ---
  if [[ "$raw_line" =~ ^#[[:space:]]*---[[:space:]]*(.+)[[:space:]]*---[[:space:]]*$ ]]; then
    current_group="${BASH_REMATCH[1]}"
    continue
  fi

  # Strip inline comments and skip blank lines
  line="${raw_line%%#*}"
  trim line
  [[ -z "$line" ]] && continue

  name="${line%%:::*}";  trim name
  rest="${line#*:::}"
  check="${rest%%:::*}"; trim check
  rest="${rest#*:::}"
  desc="${rest%%:::*}";  trim desc
  rest="${rest#*:::}"
  flag="${rest%%:::*}";  trim flag

  [[ -z "$name" || -z "$check" ]] && continue

  NAMES+=("${current_group}::${name}")
  CHECKS+=("$check")
  DESCS+=("$desc")
  [[ "$flag" == "optional" ]] && OPTIONALS+=(true) || OPTIONALS+=(false)
done < "$TOOLS_CONF"

# --------------------------------------------------------------------------
# Run checks
# --------------------------------------------------------------------------
declare -a INSTALLED MISSING_REQUIRED MISSING_OPTIONAL

ok_count=0
missing_required_count=0
missing_optional_count=0
prev_group=""

$JSON_OUTPUT && printf '[\n' && json_first=true

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
    ${json_first} || printf ',\n'
    json_first=false
    printf '  {"name": "%s", "group": "%s", "status": "%s", "optional": %s, "description": "%s"}' \
      "$name" "$group" "$status" "$optional" "$desc"
    continue
  fi

  $MISSING_ONLY && [[ "$status" == "installed" ]] && continue

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
total=${#NAMES[@]}
missing_count=$((missing_required_count + missing_optional_count))

echo ""
echo "──────────────────────────────────────"

if [[ $missing_count -eq 0 ]]; then
  printf "${GREEN}${BOLD}All $total tools are installed.${RESET}\n"
else
  printf "${BOLD}%d/%d tools installed.${RESET}\n" "$ok_count" "$total"
  [[ $missing_required_count -gt 0 ]] && \
    printf "  ${RED}Missing (required): %s${RESET}\n" "$(IFS=', '; echo "${MISSING_REQUIRED[*]}")"
  [[ $missing_optional_count -gt 0 ]] && \
    printf "  ${YELLOW}Missing (optional): %s${RESET}\n" "$(IFS=', '; echo "${MISSING_OPTIONAL[*]}")"
fi

# Exit 1 only if required tools are missing (useful in CI or scripting)
[[ $missing_required_count -eq 0 ]]
