[← Back to README](../README.md)

# gsync — Git Branch Sync

Keep configured branches up to date across your registered projects. Fetches from all remotes and fast-forwards branches that are behind, with interactive prompts for diverged branches.

## Commands

| Command | Description |
|---------|-------------|
| `gsync [project]` | Sync branches in a project (defaults to current directory) |
| `gsync_set <branch...>` | Add branches to the sync list |
| `gsync_rm [branch]` | Remove a branch from the sync list (interactive via [gum](https://github.com/charmbracelet/gum) if no arg) |
| `gsync_list` | Show currently configured branches |

## Quick Start

```zsh
# Sync the current project (must be a git repo or registered with gp)
gsync

# Sync a registered project by name
gsync my-app

# Configure which branches to sync
gsync_set develop staging
gsync_list

# Remove a branch from the sync list
gsync_rm staging
```

## Sync Flow

When you run `gsync`, the following happens:

1. **Resolve project** — finds the directory via `gp` project registry, or uses the current directory if it's a git repo
2. **Load branch config** — reads `~/.gsync-branches` (defaults to `main` and `master` if no config)
3. **Fetch** — runs `git fetch --all --prune`
4. **Dirty tree check** — if there are uncommitted changes, prompts to stash (requires gum) or skips
5. **Per-branch sync**:
   - **Up to date** — nothing to do
   - **Fast-forwardable** — updates automatically (`git pull --ff-only` for current branch, `git update-ref` for others)
   - **Diverged** — prompts for confirmation before reset (requires gum), otherwise skips
6. **Restore stash** — if changes were stashed in step 4, pops them back

## Safety

All destructive operations require explicit confirmation through [gum](https://github.com/charmbracelet/gum):

- Stashing uncommitted changes before sync
- Resetting a diverged branch to match origin
- Force-updating a non-current branch that diverged

Without gum installed, diverged branches and dirty trees are skipped with a message — nothing destructive happens automatically.

## Config

By default, gsync tracks `main` and `master`. Customize with:

```zsh
# Add branches
gsync_set develop release

# Remove a branch
gsync_rm release

# See current config
gsync_list
```

Branch names are deduplicated — adding the same branch twice has no effect.

## Data Files

| File | Purpose |
|------|---------|
| `~/.gsync-branches` | Branch list to sync (one per line) |

This is a user data file created on first use, not part of the repo. If the file doesn't exist or is empty, gsync defaults to syncing `main` and `master`.
