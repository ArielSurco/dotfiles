# Dotfiles

Personal dotfiles — shell aliases and utilities.

## Setup

Add this line to your `.zshrc`:

```zsh
source ~/dotfiles/aliases/init.sh
```

The barrel file auto-sources every alias script in the directory. Adjust the path if you cloned the repo elsewhere.

## Aliases

| Alias | Description | Docs |
|-------|-------------|------|
| `gp` | Project navigation — register, watch, and jump between project directories | [docs/gp.md](docs/gp.md) |
| `gsync` | Git branch sync — update configured branches across projects | [docs/gsync.md](docs/gsync.md) |
| `pf` | Kubernetes port forwarding — forward HAProxy service ports | [docs/pf.md](docs/pf.md) |
| `pod` | Kubernetes pod connector — interactive context, namespace, and pod selection | [docs/pod.md](docs/pod.md) |
| `dbs` | Start local Docker database containers | — |
| `dotalias` | Reload all aliases | — |

## Dependencies

- **zsh** — Required (aliases use zsh-specific features)
- **[gum](https://github.com/charmbracelet/gum)** — Optional, for interactive menus. Install: `brew install gum`
- **[kubectl](https://kubernetes.io/docs/tasks/tools/)** — Required for `pod` alias. Install: `brew install kubectl`

## Running Tests

```
bats tests/
```

Requires [bats-core](https://github.com/bats-core/bats-core): `brew install bats-core`
