# AGENTS.md

Guidelines for AI agents working in this repository.

## What This Repo Does

Synchronizes development configurations (dotfiles, fonts, app settings) across Ubuntu machines via a Makefile + shell
scripts. No external dependencies — pure bash.

## Key Files

| File / Dir                | Purpose                                                              |
|---------------------------|----------------------------------------------------------------------|
| `install.sh`              | Main sync script (backup → copy files → run hooks)                  |
| `backup.sh`               | Timestamped archive of current system files                          |
| `check.sh`                | Verify required and optional tools are installed                     |
| `lib.sh`                  | Shared constants, colors, and helpers sourced by all scripts         |
| `conf/append.conf`        | Lists files synced in append mode (everything else is overwrite)     |
| `conf/tools.conf`         | Lists tools with their check commands and optional/required flag     |
| `conf/hooks.conf`         | Commands run once after install when a matching file was synced      |
| `user_home/`              | Files mapped to `~/`                                                 |
| `root/`                   | Files mapped to `/` (deployed with `sudo`)                           |

## Sync Modes

- **Append** (`conf/append.conf`): only managed content is stored in the repo. Deployed between marker comments in the
  target file. Safe to run multiple times (idempotent).
- **Overwrite** (default): full file replaced on deploy.

## Post-Install Hooks

Defined in `conf/hooks.conf`. Each hook is a shell command triggered when a file matching a path prefix was synced.
Hooks run once regardless of how many matching files were synced (deduplication by command).

```
# Format: path_prefix ::: command
root/usr/share/fonts ::: fc-cache -f
```

> **Note:** hooks run inside the `install.sh` subshell. System commands (e.g. `fc-cache`) work fine.
> Shell reload hooks (`source ~/.bashrc`) apply to that subshell only — they won't affect your current terminal.
> An echo message is printed as a reminder to open a new terminal or source manually.

## Tools Check

Defined in `conf/tools.conf`. Each tool has a name, a shell check command, a description, and an optional flag.

```
# Format: name ::: check_command ::: description [::: optional]
git       ::: command -v git   ::: Version control
phpstorm  ::: command -v phpstorm || test -d "$HOME/.local/share/JetBrains/Toolbox/apps/PhpStorm" ::: PhpStorm IDE ::: optional
```

Missing **required** tools cause `make check` to exit 1 (useful in CI). Missing **optional** tools show with a `~`
indicator but don't fail.

## Common Commands

```bash
make check          # List tracked files then check which tools are installed
make list           # List tracked files and their sync mode
make diff           # Diff repo vs installed files
make install        # Backup + sync everything
make dry-run        # Preview install without changes
make backup         # Manual backup
make clean-backups  # Delete all backups
make keep-backups   # Keep only N most recent backups (make keep-backups N=5)
```

## Adding Files

- Drop files under `user_home/` (maps to `~/`) or `root/` (maps to `/`), preserving the directory structure.
- For append mode, add the relative path to `conf/append.conf` and store only the managed lines in the repo file.
- For new tools, add a line to `conf/tools.conf` — append `::: optional` as a 4th field to mark it non-blocking.
- For post-install actions, add a line to `conf/hooks.conf` with the matching path prefix and the command to run.

## Shared Library (`lib.sh`)

All scripts source `lib.sh` which provides:

- Path constants: `REPO_DIR`, `CONF_DIR`, `USER_HOME_DIR`, `ROOT_DIR`, `APPEND_CONF`, `TOOLS_CONF`, `HOOKS_CONF`
- Color variables: `GREEN`, `RED`, `YELLOW`, `CYAN`, `RESET`, `BOLD`
- `trim varname` — trims whitespace in-place via bash nameref
- `load_append_files` — populates `APPEND_FILES` from `conf/append.conf`
- `is_append rel` — returns true if the relative path is in append mode

## Code Style

- **Keep comments.** Do not strip inline or section comments when refactoring. Comments that explain *why*
  something is done (e.g. why `ENVIRON` is used instead of `awk -v`) are especially important to preserve.
- **Use full flag names** in shell commands where they exist: `--parents`, `--archive`, `--quiet`,
  `--fixed-strings`, `--invert-match`, `--force`, `--recursive`, etc. Short flags are harder to read
  for contributors unfamiliar with every option.
- **Colored output.** All user-facing output in scripts should use the color variables from `lib.sh`.
  Section headers in cyan+bold, success in green, warnings/dry-run in yellow, errors in red.
- **Dev-friendly structure.** Scripts use `# ---` section banners. Keep that convention.
  Functions should have a one-line comment above them explaining purpose unless the name is self-evident.
- **Don't over-abstract.** Three similar lines of code is fine. Only extract a helper when the same
  logic appears in multiple files or the function makes intent significantly clearer.

## Constraints

- No external dependencies (no `yq`, `jq`, `python`, etc.) — bash only.
- `root/` files are deployed with `sudo cp`; everything else runs as the current user.
- A backup is always created before `make install` runs.
