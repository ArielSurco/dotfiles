[← Back to README](../README.md)

# gp — Project Navigation

Navigate between project directories with Tab completion and an interactive TUI menu.

## Commands

| Command | Description |
|---------|-------------|
| `gp <name>` | Navigate to a registered project (Tab completion) |
| `gp` | Interactive project selector via [gum](https://github.com/charmbracelet/gum) |
| `gp_set <name> [path]` | Register a project. Defaults to current directory if no path given |
| `gp_watch <path>` | Watch a directory — registers all child folders as projects (Tab completes directories) |
| `gp_sync` | Re-scan all watched directories and update projects |
| `gp_rm <name>` | Remove a registered project (Tab completion) |

## Quick Start

```zsh
# Register a project manually
cd ~/projects/my-app
gp_set my-app

# Or watch a folder to register all its children
gp_watch ~/projects

# Navigate
gp my-app

# Interactive menu
gp
```

## Interactive Menu

When running `gp` with no arguments and [gum](https://github.com/charmbracelet/gum) is installed, an interactive menu appears with:

- All registered projects — select one to navigate
- **[Sync projects]** — re-scan watched folders
- **[Delete a project]** — remove a project with confirmation

Without gum, a plain list of projects is printed instead.

## Data Files

| File | Purpose |
|------|---------|
| `~/.gp-projects` | Project registry (`name=path`, one per line) |
| `~/.gp-watches` | Watched directories (one path per line) |

These are user data files created on first use, not part of the repo.
