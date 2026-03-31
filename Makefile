.PHONY: install backup clean-backups list diff check check-missing help

SHELL := /bin/bash

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: ## Backup then sync all dotfiles to this machine
	@bash install.sh

dry-run: ## Show what install would do without making changes
	@bash install.sh --dry-run

backup: ## Create a timestamped backup of all tracked files
	@bash backup.sh

clean-backups: ## Delete all backups
	@bash backup.sh --clean

keep-backups: ## Keep only the 5 most recent backups (make keep-backups N=5)
	@bash backup.sh --clean --keep $${N:-5}

list: ## List all tracked files and their sync mode
	@bash install.sh --list

diff: ## Show differences between repo and installed files
	@bash install.sh --diff

check: ## Check which required tools are installed
	@bash check.sh

check-missing: ## Show only missing tools
	@bash check.sh --missing
