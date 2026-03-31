#!/usr/bin/env bash
# backup.sh - Backup files that would be modified by install.sh.
#
# Usage:
#   ./backup.sh                   Create a timestamped backup archive
#   ./backup.sh --clean           Delete all backups
#   ./backup.sh --clean --keep N  Keep the N most recent backups

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BACKUP_DIR="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"

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
    printf "${YELLOW}No backup directory found at $BACKUP_DIR${RESET}\n"
    exit 0
  fi

  mapfile -t archives < <(find "$BACKUP_DIR" -maxdepth 1 -name 'backup-*.tar.gz' | sort)
  total=${#archives[@]}

  if [[ $total -eq 0 ]]; then
    printf "${YELLOW}No backups found in $BACKUP_DIR${RESET}\n"
    exit 0
  fi

  if [[ $KEEP -gt 0 ]]; then
    if [[ $total -le $KEEP ]]; then
      printf "${GREEN}Only $total backup(s) found, keeping all (--keep $KEEP)${RESET}\n"
      exit 0
    fi
    to_delete=("${archives[@]:0:$((total - KEEP))}")
    printf "${CYAN}Keeping $KEEP most recent backup(s), deleting $((total - KEEP)):${RESET}\n"
  else
    to_delete=("${archives[@]}")
    printf "${CYAN}Deleting all $total backup(s):${RESET}\n"
  fi

  for f in "${to_delete[@]}"; do
    printf "  ${RED}rm${RESET} $f\n"
    rm --force "$f"
  done
  printf "${GREEN}Done.${RESET}\n"
  exit 0
fi

# --------------------------------------------------------------------------
# Backup mode
# --------------------------------------------------------------------------
mkdir --parents "$BACKUP_DIR"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
STAGING=$(mktemp --directory)
trap 'rm --recursive --force "$STAGING"' EXIT

backed_up=0

# Copy each tracked user_home file to the staging area, preserving relative paths
if [[ -d "$USER_HOME_DIR" ]]; then
  while IFS= read -r repo_file; do
    target="$HOME/${repo_file#$USER_HOME_DIR/}"
    if [[ -e "$target" ]]; then
      dest="$STAGING/user_home/${repo_file#$USER_HOME_DIR/}"
      mkdir --parents "$(dirname "$dest")"
      cp --archive "$target" "$dest"
      backed_up=$((backed_up + 1))
    fi
  done < <(find "$USER_HOME_DIR" -type f)
fi

# Copy each tracked root file to the staging area, preserving absolute paths under root/
if [[ -d "$ROOT_DIR" ]]; then
  while IFS= read -r repo_file; do
    target="${repo_file#$ROOT_DIR}"
    if [[ -e "$target" ]]; then
      dest="$STAGING/root/$target"
      mkdir --parents "$(dirname "$dest")"
      cp --archive "$target" "$dest"
      backed_up=$((backed_up + 1))
    fi
  done < <(find "$ROOT_DIR" -type f)
fi

if [[ $backed_up -eq 0 ]]; then
  printf "${YELLOW}Nothing to back up (no target files exist yet).${RESET}\n"
  exit 0
fi

ARCHIVE="$BACKUP_DIR/backup-${TIMESTAMP}.tar.gz"
tar --create --gzip --file "$ARCHIVE" --directory "$STAGING" .
printf "${GREEN}Backed up $backed_up file(s) → $ARCHIVE${RESET}\n"
