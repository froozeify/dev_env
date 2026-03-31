#!/usr/bin/env bash
# backup.sh - Backup files that would be modified by install.sh
#
# Usage:
#   ./backup.sh               Create a timestamped backup archive
#   ./backup.sh --clean       Delete all backups
#   ./backup.sh --clean --keep N  Keep the N most recent backups

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"
APPEND_CONF="$REPO_DIR/append.conf"
USER_HOME_DIR="$REPO_DIR/user_home"
ROOT_DIR="$REPO_DIR/root"

# --------------------------------------------------------------------------
# Parse arguments
# --------------------------------------------------------------------------
CLEAN=false
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) CLEAN=true; shift ;;
    --keep)  KEEP="${2:?'--keep requires a number'}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --------------------------------------------------------------------------
# Clean mode
# --------------------------------------------------------------------------
if $CLEAN; then
  if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "No backup directory found at $BACKUP_DIR"
    exit 0
  fi

  mapfile -t archives < <(find "$BACKUP_DIR" -maxdepth 1 -name 'backup-*.tar.gz' | sort)
  total=${#archives[@]}

  if [[ $total -eq 0 ]]; then
    echo "No backups found in $BACKUP_DIR"
    exit 0
  fi

  if [[ $KEEP -gt 0 ]]; then
    if [[ $total -le $KEEP ]]; then
      echo "Only $total backup(s) found, keeping all (--keep $KEEP)"
      exit 0
    fi
    to_delete=("${archives[@]:0:$((total - KEEP))}")
    echo "Keeping $KEEP most recent backup(s), deleting $((total - KEEP)):"
  else
    to_delete=("${archives[@]}")
    echo "Deleting all $total backup(s):"
  fi

  for f in "${to_delete[@]}"; do
    echo "  rm $f"
    rm -f "$f"
  done
  echo "Done."
  exit 0
fi

# --------------------------------------------------------------------------
# Backup mode
# --------------------------------------------------------------------------
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

# Load append-mode file list
declare -A APPEND_FILES
if [[ -f "$APPEND_CONF" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"   # strip inline comments
    line="${line// /}"   # strip spaces
    [[ -z "$line" ]] && continue
    APPEND_FILES["$line"]=1
  done < "$APPEND_CONF"
fi

backed_up=0

# Backup user_home files
if [[ -d "$USER_HOME_DIR" ]]; then
  while IFS= read -r repo_file; do
    rel="${repo_file#$USER_HOME_DIR/}"
    target="$HOME/$rel"
    if [[ -e "$target" ]]; then
      dest="$STAGING/user_home/$rel"
      mkdir -p "$(dirname "$dest")"
      cp -a "$target" "$dest"
      backed_up=$((backed_up + 1))
    fi
  done < <(find "$USER_HOME_DIR" -type f)
fi

# Backup root files
if [[ -d "$ROOT_DIR" ]]; then
  while IFS= read -r repo_file; do
    rel="${repo_file#$ROOT_DIR}"
    target="$rel"
    if [[ -e "$target" ]]; then
      dest="$STAGING/root/$rel"
      mkdir -p "$(dirname "$dest")"
      cp -a "$target" "$dest"
      backed_up=$((backed_up + 1))
    fi
  done < <(find "$ROOT_DIR" -type f)
fi

if [[ $backed_up -eq 0 ]]; then
  echo "Nothing to back up (no target files exist yet)."
  exit 0
fi

ARCHIVE="$BACKUP_DIR/backup-${TIMESTAMP}.tar.gz"
tar -czf "$ARCHIVE" -C "$STAGING" .
echo "Backed up $backed_up file(s) → $ARCHIVE"
