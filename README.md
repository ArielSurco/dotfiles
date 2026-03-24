# Dotfiles

Personal dotfiles — shell aliases and utilities for development workflows.

## Installation

### Homebrew (recommended)

```zsh
brew tap ArielSurco/dotfiles https://github.com/ArielSurco/dotfiles
brew install dotfiles
```

Then run the interactive setup:

```zsh
dotfiles-setup
```

And add this line to your `.zshrc`:

```zsh
source $(brew --prefix)/opt/dotfiles/aliases/init.sh
```

### Manual

```zsh
git clone https://github.com/ArielSurco/dotfiles ~/dotfiles
```

Add this line to your `.zshrc`:

```zsh
source ~/dotfiles/aliases/init.sh
```

Optionally run the setup wizard to choose which alias groups to enable:

```zsh
~/dotfiles/bin/dotfiles-setup
```

## Updating

### Homebrew

```zsh
brew upgrade dotfiles
```

### Manual

```zsh
cd ~/dotfiles && git pull
```

Your configuration and data (`~/.dotfiles-data/`) is preserved across updates.

## Setup

On first load with no configuration, **all alias groups are enabled** (backwards compatible). Run `dotfiles-setup` to selectively enable/disable groups. The configuration is stored in `~/.dotfiles-data/enabled-groups`.

Core utilities (`utils.sh`) are always loaded regardless of configuration.

## Aliases

| Alias | Group | Description | Docs |
|-------|-------|-------------|------|
| `dev` | dev | Configurable project dev launcher — templates, TUI selection, per-project configs | [docs/dev.md](docs/dev.md) |
| `gp` | navigation | Project navigation — register, watch, and jump between project directories | [docs/gp.md](docs/gp.md) |
| `gsync` | git | Git branch sync — update configured branches across projects | [docs/gsync.md](docs/gsync.md) |
| `pf` | kubernetes | Kubernetes port forwarding — forward HAProxy service ports | [docs/pf.md](docs/pf.md) |
| `pod` | kubernetes | Kubernetes pod connector — interactive context, namespace, and pod selection | [docs/pod.md](docs/pod.md) |
| `sentry` | sentry | Sentry issue search — query events by custom tags across projects | [docs/sentry.md](docs/sentry.md) |
| `dbs` | docker | Start local Docker database containers | — |
| `dotalias` | core | Reload all aliases | — |

## Dependencies

- **zsh** — Required (aliases use zsh-specific features)
- **[gum](https://github.com/charmbracelet/gum)** — Recommended, for interactive menus. Install: `brew install gum`
- **[kubectl](https://kubernetes.io/docs/tasks/tools/)** — Required for `pod` and `pf` aliases. Install: `brew install kubectl`
- **[jq](https://jqlang.github.io/jq/)** — Required for `sentry` alias. Install: `brew install jq`

## Running Tests

```
bats tests/
```

Requires [bats-core](https://github.com/bats-core/bats-core): `brew install bats-core`
