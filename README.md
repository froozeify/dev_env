# dev_env — Dotfiles & Config Sync

A lightweight, dependency-free system to synchronize development configurations across Ubuntu machines.

## Features

- **Two sync modes**: append (shell configs) and overwrite (JSON, fonts, etc.)
- **Safe by default**: automatic backup before every install
- **Marker-based append**: managed content is clearly delimited, your own additions are preserved
- **Sudo only when needed**: root files use `sudo cp`, user files don't

## Quick Start

```bash
git clone <your-repo-url> ~/dev_env
cd ~/dev_env

# Preview what will happen
make list
make diff

# Install everything (auto-backup runs first)
make install
```

## Sync Modes

### Append mode

Used for files like `.zshrc` where you want to add your custom config without replacing the whole file.

The repo file contains **only the managed content**. On install, it is wrapped in markers:

```bash
# ===== BEGIN DOTFILES SYNC =====
export PATH="$HOME/.local/bin:$PATH"
# ... your managed content ...
# ===== END DOTFILES SYNC =====
```

- **First install**: block is appended at the end of the target file
- **Update**: content between markers is replaced; everything outside is untouched
- **Safe to run multiple times** (idempotent)

To add a file to append mode, list it in `append.conf`:

```
user_home/.zshrc
user_home/.bashrc
```

### Overwrite mode

Used for structured config files (JSON, fonts, etc.) where the whole file should match the repo.

Everything **not listed in `append.conf`** is treated as overwrite.

## Available Commands

| Command                 | Description                              |
|-------------------------|------------------------------------------|
| `make install`          | Backup + sync all files                  |
| `make dry-run`          | Preview what install would do            |
| `make list`             | List files and their sync mode           |
| `make diff`             | Show differences between repo and system |
| `make backup`           | Create a manual backup                   |
| `make clean-backups`    | Delete all backups                       |
| `make keep-backups N=5` | Keep only the 5 most recent backups      |

## Backups

Backups are stored in `~/.dotfiles-backup/` as timestamped archives:

```
~/.dotfiles-backup/
├── backup-2026-03-31_143022.tar.gz
└── backup-2026-03-31_150811.tar.gz
```

```bash
# Create a backup manually
make backup

# Delete all backups
make clean-backups

# Keep only the 3 most recent
make keep-backups N=3
```

You can override the backup directory:
```bash
DOTFILES_BACKUP_DIR=/mnt/external/backups make backup
```

## Environment Variables

| Variable              | Default              | Description              |
|-----------------------|----------------------|--------------------------|
| `DOTFILES_BACKUP_DIR` | `~/.dotfiles-backup` | Where backups are stored |
