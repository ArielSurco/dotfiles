[← Back to README](../README.md)

# dev — Configurable Project Dev Launcher

Launch per-project dev environments with reusable named configs and a TUI selector.

## Commands

| Command | Description |
|---------|-------------|
| `dev` | Interactive project selector — choose a project and launch its dev config |
| `dev <project>` | Launch the dev config for a specific project |
| `dev config` | Interactive config management menu |
| `dev config list` | List all named configs with usage counts |
| `dev config create` | Create a new named config via `$EDITOR` |
| `dev config edit` | Edit an existing named config |
| `dev config delete` | Delete a named config (cascades to all projects using it) |
| `dev remove [project]` | Remove a project's dev config |

## Quick Start

```zsh
# Create a reusable named config
dev config create
# → enter name: "ruby-backend"
# → editor opens, write your startup script

# Assign the config to a project
dev api
# → choose "Use existing" → select "ruby-backend"

# Now launch it anytime
dev api
```

## Named Configs

All configs are stored as shell scripts in `~/.dotfiles-data/dev-configs/` as `{name}.sh` files. There is no distinction between "templates" and "custom configs" — every config is a named config that any project can reference.

Example config (`ruby-backend`):

```zsh
# Start Rails server and Sidekiq
bundle exec rails server &
bundle exec sidekiq &
```

## Project Configs

Each project can have one of:

| Type | File | Description |
|------|------|-------------|
| Config ref | `projects/<name>.ref` | Points to a named config — single line with the config name |
| Override | `projects/<name>.sh` | A modified clone where the user changed the content |

## Unconfigured Project Flow

When you run `dev` on a project with no config, you get four options:

1. **Create new config** — enter a name (defaults to project name), open `$EDITOR`, save as named config + `.ref`
2. **Clone & edit** — select an existing config, name the clone, edit it. If unchanged, saved as `.ref` to original; if modified, saved as new named config
3. **Use existing** — select from available named configs, create `.ref`
4. **Cancel**

## Config Deletion

When deleting a config via `dev config delete`, all projects that reference it (`.ref` files) are also removed. The system warns you which projects will be affected before confirming.

## Removing a Project Config

When removing via `dev remove`:

- **Project with `.ref`**: Option to remove just the project reference, or delete the underlying config (with cascade warning for other dependents)
- **Project with override `.sh`**: Option to remove the override

## Project Indicators

In the interactive selector, projects show their config status:

- `api [ruby-backend]` — uses a named config
- `web [custom]` — has an override config
- `admin` — no config (will trigger setup flow)

## Data Files

| Path | Purpose |
|------|---------|
| `~/.dotfiles-data/dev-configs/*.sh` | Named config scripts |
| `~/.dotfiles-data/dev-configs/projects/` | Per-project references (`.ref`) or overrides (`.sh`) |

These are user data files created on first use, not part of the repo.

## Dependencies

- **[gum](https://github.com/charmbracelet/gum)** — Required for interactive menus. Install: `brew install gum`
- Projects must be registered via `gp_set` (see [gp docs](gp.md))
