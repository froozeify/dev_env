# AGENTS.md

Guidelines for AI agents working in this repository.

## What This Repo Does

Synchronizes development configurations (dotfiles, fonts, app settings) across Ubuntu machines via a Makefile + shell
scripts. No external dependencies — pure bash.

## Key Files

| File          | Purpose                                                          |
|---------------|------------------------------------------------------------------|
| `install.sh`  | Main sync script (backup → copy files)                           |
| `backup.sh`   | Timestamped archive of current system files                      |
| `check.sh`    | Verify required tools are installed                              |
| `append.conf` | Lists files synced in append mode (everything else is overwrite) |
| `tools.conf`  | Lists required tools with their check commands                   |
| `user_home/`  | Files mapped to `~/`                                             |
| `root/`       | Files mapped to `/` (deployed with `sudo`)                       |

## Sync Modes

- **Append** (`append.conf`): only managed content is stored in the repo. Deployed between marker comments in the target
  file. Safe to run multiple times.
- **Overwrite** (default): full file replaced on deploy.

## Common Commands

```bash
make check          # Check which tools are installed
make list           # List tracked files and their sync mode
make diff           # Diff repo vs installed files
make install        # Backup + sync everything
make dry-run        # Preview install without changes
make backup         # Manual backup
make clean-backups  # Delete all backups
```

## Adding Files

- Drop files under `user_home/` (maps to `~/`) or `root/` (maps to `/`), preserving the directory structure.
- For append mode, add the path to `append.conf` and store only the managed lines in the repo file.
- For new required tools, add a line to `tools.conf` using the `name ::: check_command ::: description` format.

## Constraints

- No external dependencies (no `yq`, `jq`, `python`, etc.) — bash only.
- `root/` files are deployed with `sudo cp`; everything else runs as the current user.
- A backup is always created before `make install` runs.
