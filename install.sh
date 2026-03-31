#!/usr/bin/env bash
# install.sh - Sync dotfiles to the current machine.
#
# Usage:
#   ./install.sh            Backup then sync all files
#   ./install.sh --dry-run  Show what would happen without making changes
#   ./install.sh --list     List all tracked files and their sync mode
#   ./install.sh --diff     Show diff between repo and installed files

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# --------------------------------------------------------------------------
# Parse arguments
# --------------------------------------------------------------------------
MODE="install"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --list)    MODE="list" ;;
    --diff)    MODE="diff" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

load_append_files

# --------------------------------------------------------------------------
# Hooks
# --------------------------------------------------------------------------
declare -a HOOK_PATTERNS=() HOOK_COMMANDS=()
declare -A TRIGGERED_HOOKS=()  # keyed by command for deduplication

load_hooks() {
  [[ ! -f "$HOOKS_CONF" ]] && return
  while IFS= read -r raw_line; do
    local line="${raw_line%%#*}"
    trim line
    [[ -z "$line" ]] && continue

    local pattern="${line%%:::*}"; trim pattern
    local command="${line#*:::}";  trim command
    [[ -z "$pattern" || -z "$command" ]] && continue

    HOOK_PATTERNS+=("$pattern")
    HOOK_COMMANDS+=("$command")
  done < "$HOOKS_CONF"
}

# Mark any hooks whose pattern is a prefix of the given relative path
trigger_hooks() {
  local rel="$1"
  for i in "${!HOOK_PATTERNS[@]}"; do
    local pattern="${HOOK_PATTERNS[$i]}"
    if [[ "$rel" == "$pattern" || "$rel" == "$pattern"* ]]; then
      TRIGGERED_HOOKS["${HOOK_COMMANDS[$i]}"]=1
    fi
  done
}

# Run (or preview) all triggered hooks, each exactly once
run_triggered_hooks() {
  [[ ${#TRIGGERED_HOOKS[@]} -eq 0 ]] && return

  printf "\n${CYAN}${BOLD}--- Post-install hooks ---${RESET}\n"
  for cmd in "${!TRIGGERED_HOOKS[@]}"; do
    if $DRY_RUN; then
      printf "  ${YELLOW}[dry-run]${RESET} Would run: $cmd\n"
    else
      printf "  ${CYAN}→${RESET} $cmd\n"
      eval "$cmd" || printf "  ${YELLOW}(hook exited with error, continuing)${RESET}\n"
    fi
  done
}

load_hooks

# --------------------------------------------------------------------------
# Sync helpers
# --------------------------------------------------------------------------
sync_append() {
  local repo_file="$1" target="$2"

  # Build the full managed block that will be injected into the target file
  local block
  block="${MARKER_BEGIN}"$'\n'"$(cat "$repo_file")"$'\n'"${MARKER_END}"

  # Target doesn't exist yet — create it with just the managed block
  if [[ ! -f "$target" ]]; then
    $DRY_RUN && { printf "  ${YELLOW}[dry-run]${RESET} Would create $target\n"; return; }
    mkdir --parents "$(dirname "$target")"
    printf '%s\n' "$block" > "$target"
    printf "  ${GREEN}✓${RESET} Created $target\n"
    return
  fi

  if grep --quiet --fixed-strings "$MARKER_BEGIN" "$target"; then
    # Managed block already exists — check if it differs before doing any work
    local managed
    managed=$(sed --quiet "/$MARKER_BEGIN/,/$MARKER_END/p" "$target" 2>/dev/null \
              | grep --invert-match "^$MARKER_BEGIN$" \
              | grep --invert-match "^$MARKER_END$" || true)
    if diff <(printf '%s\n' "$managed") "$repo_file" > /dev/null 2>&1; then
      return 1  # already up to date, nothing to do
    fi

    if $DRY_RUN; then
      printf "  ${YELLOW}[dry-run]${RESET} Would update managed block in $target\n"
      return
    fi

    # Replace block in-place using a temp file.
    # Block is passed via ENVIRON instead of awk -v to prevent awk from
    # interpreting escape sequences (e.g. \033 → ESC).
    local tmp
    tmp=$(mktemp --suffix=.dotfiles)
    block="$block" awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
      $0 == begin { print ENVIRON["block"]; skip=1; next }
      $0 == end   { skip=0; next }
      !skip        { print }
    ' "$target" > "$tmp"
    mv "$tmp" "$target"
    printf "  ${GREEN}✓${RESET} Updated $target\n"
  else
    # No managed block yet — append one at the end of the file
    $DRY_RUN && { printf "  ${YELLOW}[dry-run]${RESET} Would append to $target\n"; return; }
    printf '\n%s\n' "$block" >> "$target"
    printf "  ${GREEN}✓${RESET} Appended to $target\n"
  fi
}

sync_overwrite() {
  local repo_file="$1" target="$2" use_sudo="${3:-false}"

  # Skip if already identical
  if [[ -f "$target" ]] && diff "$repo_file" "$target" > /dev/null 2>&1; then
    return 1  # already up to date, nothing to do
  fi

  $DRY_RUN && { printf "  ${YELLOW}[dry-run]${RESET} Would overwrite $target\n"; return; }
  mkdir --parents "$(dirname "$target")"
  if $use_sudo; then
    sudo cp --archive "$repo_file" "$target"
  else
    cp --archive "$repo_file" "$target"
  fi
  printf "  ${GREEN}✓${RESET} Overwritten $target\n"
}

# Dispatch to sync_append or sync_overwrite, then trigger matching hooks.
# Hooks only fire when the file was changed (or would be changed in dry-run).
sync_file() {
  local repo_file="$1" rel="$2" target="$3" use_sudo="${4:-false}"
  local changed=false
  if is_append "$rel"; then
    sync_append "$repo_file" "$target" && changed=true
  else
    sync_overwrite "$repo_file" "$target" "$use_sudo" && changed=true
  fi
  if $changed; then trigger_hooks "$rel"; fi
}

# --------------------------------------------------------------------------
# List mode
# --------------------------------------------------------------------------
if [[ "$MODE" == "list" ]]; then
  printf "${BOLD}Tracked files:${RESET}\n\n"

  if [[ -d "$USER_HOME_DIR" ]]; then
    while IFS= read -r repo_file; do
      rel="user_home/${repo_file#$USER_HOME_DIR/}"
      target="$HOME/${repo_file#$USER_HOME_DIR/}"
      is_append "$rel" && mode="APPEND" || mode="OVERWRITE"
      [[ -e "$target" ]] \
        && printf "  ${CYAN}%-16s${RESET}  %s  ${GREEN}✓${RESET}\n" "[$mode]" "$target" \
        || printf "  ${CYAN}%-16s${RESET}  %s  ${RED}✗ (not installed)${RESET}\n" "[$mode]" "$target"
    done < <(find "$USER_HOME_DIR" -type f | sort)
  fi

  if [[ -d "$ROOT_DIR" ]]; then
    while IFS= read -r repo_file; do
      rel="root${repo_file#$ROOT_DIR}"
      target="${repo_file#$ROOT_DIR}"
      is_append "$rel" && mode="APPEND" || mode="OVERWRITE (sudo)"
      [[ -e "$target" ]] \
        && printf "  ${CYAN}%-16s${RESET}  %s  ${GREEN}✓${RESET}\n" "[$mode]" "$target" \
        || printf "  ${CYAN}%-16s${RESET}  %s  ${RED}✗ (not installed)${RESET}\n" "[$mode]" "$target"
    done < <(find "$ROOT_DIR" -type f | sort)
  fi

  exit 0
fi

# --------------------------------------------------------------------------
# Diff mode
# --------------------------------------------------------------------------
if [[ "$MODE" == "diff" ]]; then
  found_diff=false

  if [[ -d "$USER_HOME_DIR" ]]; then
    while IFS= read -r repo_file; do
      rel="user_home/${repo_file#$USER_HOME_DIR/}"
      target="$HOME/${repo_file#$USER_HOME_DIR/}"

      if [[ ! -e "$target" ]]; then
        printf "${CYAN}${BOLD}=== $target${RESET} ${RED}(not installed)${RESET}\n"
        found_diff=true
        continue
      fi

      if is_append "$rel"; then
        # Extract only the content between the markers, strip the marker lines themselves
        managed=$(sed --quiet "/$MARKER_BEGIN/,/$MARKER_END/p" "$target" 2>/dev/null \
                  | grep --invert-match "^$MARKER_BEGIN$" \
                  | grep --invert-match "^$MARKER_END$" || true)
        if ! diff <(printf '%s\n' "$managed") "$repo_file" > /dev/null 2>&1; then
          printf "${CYAN}${BOLD}=== $target${RESET} ${YELLOW}(managed block differs)${RESET}\n"
          diff <(printf '%s\n' "$managed") "$repo_file" || true
          found_diff=true
        fi
      else
        if ! diff "$repo_file" "$target" > /dev/null 2>&1; then
          printf "${CYAN}${BOLD}=== $target${RESET}\n"
          diff "$repo_file" "$target" || true
          found_diff=true
        fi
      fi
    done < <(find "$USER_HOME_DIR" -type f | sort)
  fi

  if [[ -d "$ROOT_DIR" ]]; then
    while IFS= read -r repo_file; do
      rel="root${repo_file#$ROOT_DIR}"
      target="${repo_file#$ROOT_DIR}"

      if [[ ! -e "$target" ]]; then
        printf "${CYAN}${BOLD}=== $target${RESET} ${RED}(not installed)${RESET}\n"
        found_diff=true
        continue
      fi

      if ! diff "$repo_file" "$target" > /dev/null 2>&1; then
        printf "${CYAN}${BOLD}=== $target${RESET}\n"
        diff "$repo_file" "$target" || true
        found_diff=true
      fi
    done < <(find "$ROOT_DIR" -type f | sort)
  fi

  $found_diff || printf "${GREEN}Everything is up to date.${RESET}\n"
  exit 0
fi

# --------------------------------------------------------------------------
# Install mode
# --------------------------------------------------------------------------
printf "${BOLD}=== Dotfiles Sync ===${RESET}\n\n"

if ! $DRY_RUN; then
  printf "${CYAN}${BOLD}--- Backup ---${RESET}\n"
  bash "$REPO_DIR/backup.sh"
  echo ""
fi

printf "${CYAN}${BOLD}--- Syncing user_home → $HOME ---${RESET}\n"
if [[ -d "$USER_HOME_DIR" ]]; then
  while IFS= read -r repo_file; do
    rel="user_home/${repo_file#$USER_HOME_DIR/}"
    target="$HOME/${repo_file#$USER_HOME_DIR/}"
    sync_file "$repo_file" "$rel" "$target"
  done < <(find "$USER_HOME_DIR" -type f | sort)
else
  printf "  ${YELLOW}(no user_home/ directory found)${RESET}\n"
fi

echo ""
printf "${CYAN}${BOLD}--- Syncing root → / (may require sudo) ---${RESET}\n"
if [[ -d "$ROOT_DIR" ]]; then
  while IFS= read -r repo_file; do
    rel="root${repo_file#$ROOT_DIR}"
    target="${repo_file#$ROOT_DIR}"
    sync_file "$repo_file" "$rel" "$target" true
  done < <(find "$ROOT_DIR" -type f | sort)
else
  printf "  ${YELLOW}(no root/ directory found)${RESET}\n"
fi

run_triggered_hooks

echo ""
printf "${GREEN}${BOLD}=== Done ===${RESET}\n"
