#!/usr/bin/env bash
# install.sh - Sync dotfiles to the current machine
#
# Usage:
#   ./install.sh          Backup then sync all files
#   ./install.sh --dry-run  Show what would happen without making changes
#   ./install.sh --list   List all tracked files and their sync mode
#   ./install.sh --diff   Show diff between repo and installed files

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPEND_CONF="$REPO_DIR/append.conf"
USER_HOME_DIR="$REPO_DIR/user_home"
ROOT_DIR="$REPO_DIR/root"

MARKER_BEGIN="# ===== BEGIN DOTFILES SYNC ====="
MARKER_END="# ===== END DOTFILES SYNC ====="

# --------------------------------------------------------------------------
# Parse arguments
# --------------------------------------------------------------------------
MODE="install"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=true ;;
    --list)     MODE="list" ;;
    --diff)     MODE="diff" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# --------------------------------------------------------------------------
# Load append-mode file list
# --------------------------------------------------------------------------
declare -A APPEND_FILES
if [[ -f "$APPEND_CONF" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line// /}"
    [[ -z "$line" ]] && continue
    APPEND_FILES["$line"]=1
  done < "$APPEND_CONF"
fi

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
is_append() {
  local rel="$1"   # e.g. user_home/.zshrc or root/usr/share/fonts/...
  [[ -n "${APPEND_FILES[$rel]+_}" ]]
}

sync_append() {
  local repo_file="$1"
  local target="$2"

  local block
  block="$MARKER_BEGIN"$'\n'
  block+="$(cat "$repo_file")"$'\n'
  block+="$MARKER_END"

  if [[ ! -f "$target" ]]; then
    if $DRY_RUN; then echo "  [dry-run] Would create $target and append managed block"; return; fi
    mkdir -p "$(dirname "$target")"
    printf '%s\n' "$block" > "$target"
    echo "  Created $target with managed block"
    return
  fi

  if grep -qF "$MARKER_BEGIN" "$target" 2>/dev/null; then
    # Replace existing block
    local tmp
    tmp=$(mktemp)
    block="$block" awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
      $0 == begin { print ENVIRON["block"]; skip=1; next }
      $0 == end   { skip=0; next }
      !skip        { print }
    ' "$target" > "$tmp"
    if $DRY_RUN; then
      echo "  [dry-run] Would update managed block in $target"
      rm -f "$tmp"
    else
      mv "$tmp" "$target"
      echo "  Updated managed block in $target"
    fi
  else
    # Append new block
    if $DRY_RUN; then echo "  [dry-run] Would append managed block to $target"; return; fi
    printf '\n%s\n' "$block" >> "$target"
    echo "  Appended managed block to $target"
  fi
}

sync_overwrite() {
  local repo_file="$1"
  local target="$2"
  local use_sudo="${3:-false}"

  if $DRY_RUN; then
    echo "  [dry-run] Would overwrite $target"
    return
  fi

  mkdir -p "$(dirname "$target")"
  if $use_sudo; then
    sudo cp -a "$repo_file" "$target"
  else
    cp -a "$repo_file" "$target"
  fi
  echo "  Overwritten $target"
}

# --------------------------------------------------------------------------
# List mode
# --------------------------------------------------------------------------
if [[ "$MODE" == "list" ]]; then
  echo "Tracked files:"
  echo ""

  if [[ -d "$USER_HOME_DIR" ]]; then
    while IFS= read -r repo_file; do
      rel="user_home/${repo_file#$USER_HOME_DIR/}"
      target="$HOME/${repo_file#$USER_HOME_DIR/}"
      if is_append "$rel"; then
        mode="APPEND"
      else
        mode="OVERWRITE"
      fi
      exists="✓"
      [[ ! -e "$target" ]] && exists="✗ (not installed)"
      printf "  %-10s  %s  %s\n" "[$mode]" "$target" "$exists"
    done < <(find "$USER_HOME_DIR" -type f | sort)
  fi

  if [[ -d "$ROOT_DIR" ]]; then
    while IFS= read -r repo_file; do
      rel="root${repo_file#$ROOT_DIR}"
      target="${repo_file#$ROOT_DIR}"
      if is_append "$rel"; then
        mode="APPEND"
      else
        mode="OVERWRITE (sudo)"
      fi
      exists="✓"
      [[ ! -e "$target" ]] && exists="✗ (not installed)"
      printf "  %-10s  %s  %s\n" "[$mode]" "$target" "$exists"
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
      target="$HOME/${repo_file#$USER_HOME_DIR/}"
      rel="user_home/${repo_file#$USER_HOME_DIR/}"

      if [[ ! -e "$target" ]]; then
        echo "=== $target (not installed) ==="
        found_diff=true
        continue
      fi

      if is_append "$rel"; then
        # Compare only the managed block content
        managed=$(sed -n "/$MARKER_BEGIN/,/$MARKER_END/p" "$target" 2>/dev/null \
                  | grep -v "^$MARKER_BEGIN$" | grep -v "^$MARKER_END$" || true)
        if ! diff <(printf '%s\n' "$managed") "$repo_file" > /dev/null 2>&1; then
          echo "=== $target (managed block differs) ==="
          diff <(printf '%s\n' "$managed") "$repo_file" || true
          found_diff=true
        fi
      else
        if ! diff "$repo_file" "$target" > /dev/null 2>&1; then
          echo "=== $target ==="
          diff "$repo_file" "$target" || true
          found_diff=true
        fi
      fi
    done < <(find "$USER_HOME_DIR" -type f | sort)
  fi

  if [[ -d "$ROOT_DIR" ]]; then
    while IFS= read -r repo_file; do
      target="${repo_file#$ROOT_DIR}"
      if [[ ! -e "$target" ]]; then
        echo "=== $target (not installed) ==="
        found_diff=true
        continue
      fi
      if ! diff "$repo_file" "$target" > /dev/null 2>&1; then
        echo "=== $target ==="
        diff "$repo_file" "$target" || true
        found_diff=true
      fi
    done < <(find "$ROOT_DIR" -type f | sort)
  fi

  if ! $found_diff; then
    echo "Everything is up to date."
  fi
  exit 0
fi

# --------------------------------------------------------------------------
# Install mode
# --------------------------------------------------------------------------
echo "=== Dotfiles Sync ==="
echo ""

# Backup first
if ! $DRY_RUN; then
  echo "--- Backup ---"
  bash "$REPO_DIR/backup.sh"
  echo ""
fi

echo "--- Syncing user_home → $HOME ---"
if [[ -d "$USER_HOME_DIR" ]]; then
  while IFS= read -r repo_file; do
    rel="user_home/${repo_file#$USER_HOME_DIR/}"
    target="$HOME/${repo_file#$USER_HOME_DIR/}"

    if is_append "$rel"; then
      sync_append "$repo_file" "$target"
    else
      sync_overwrite "$repo_file" "$target" false
    fi
  done < <(find "$USER_HOME_DIR" -type f | sort)
else
  echo "  (no user_home/ directory found)"
fi

echo ""
echo "--- Syncing root → / (may require sudo) ---"
if [[ -d "$ROOT_DIR" ]]; then
  while IFS= read -r repo_file; do
    rel="root${repo_file#$ROOT_DIR}"
    target="${repo_file#$ROOT_DIR}"

    if is_append "$rel"; then
      sync_append "$repo_file" "$target"
    else
      sync_overwrite "$repo_file" "$target" true
    fi
  done < <(find "$ROOT_DIR" -type f | sort)
else
  echo "  (no root/ directory found)"
fi

echo ""
echo "=== Done ==="

# Refresh font cache if fonts were installed
if [[ -d "$ROOT_DIR/usr/share/fonts" ]] && ! $DRY_RUN; then
  echo "Refreshing font cache..."
  fc-cache -f
fi
