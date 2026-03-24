# Dotfiles

Personal dotfiles monorepo — shell aliases and AI tool configuration.

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

Optionally run the setup wizard to choose what to configure:

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

The setup wizard (`dotfiles-setup`) works in two steps:

1. **Domain selection** — choose which domains to configure: `aliases`, `ai`, or both
2. **Per-domain config** — each domain runs its own setup (alias group selection, AI target assembly, etc.)

Flags to skip domain selection: `--aliases`, `--ai`, `--all`.

On first load with no configuration, **all alias groups are enabled** (backwards compatible). Core utilities (`utils.sh`) are always loaded regardless of configuration.

## AI Tools

The `ai/` directory contains a shared AI personality, coding skills, and tool-specific configs.

### What's included

- **Shared persona** (`ai/rules/persona.md`) — single source of truth for personality, rules, and coding standards
- **Skills** (`ai/skills/`) — 12 skill directories with specialized coding patterns, plus `_shared/` conventions
- **Engram protocol** (`ai/parts/engram-protocol.md`) — persistent memory across sessions
- **SDD orchestrator** (`ai/parts/sdd-orchestrator.md`) — Spec-Driven Development workflow and Agent Teams coordination

### Supported tools

| Tool | Generated config | Symlinked to |
|------|-----------------|--------------|
| Claude Code | `ai/targets/claude.md` | `~/.claude/CLAUDE.md` |
| Cursor | `ai/targets/cursor.mdc` | `~/.cursor/rules/gentle-ai.mdc` |

The AI setup assembles each target by concatenating the shared persona with tool-specific parts, then symlinks skills into `~/.claude/skills/`.

### Adding support for other tools (Gemini, Windsurf, etc.)

The shared persona works with any AI tool. To add a new target:

1. Use `ai/rules/persona.md` directly — symlink or copy it to the tool's config location
2. Or create a new target in `ai/targets/` that combines persona with tool-specific parts

### Extending with custom skills

Two options:

1. **Add skills to `~/.claude/skills/`** — the setup won't touch directories it doesn't own
2. **Fork the repo** and add skill directories to `ai/skills/`

## Aliases

| Alias | Group | Description | Docs |
|-------|-------|-------------|------|
| `dev` | dev | Configurable project dev launcher — templates, TUI selection, per-project configs | [aliases/docs/dev.md](aliases/docs/dev.md) |
| `gp` | navigation | Project navigation — register, watch, and jump between project directories | [aliases/docs/gp.md](aliases/docs/gp.md) |
| `gsync` | git | Git branch sync — update configured branches across projects | [aliases/docs/gsync.md](aliases/docs/gsync.md) |
| `pf` | kubernetes | Kubernetes port forwarding — forward HAProxy service ports | [aliases/docs/pf.md](aliases/docs/pf.md) |
| `pod` | kubernetes | Kubernetes pod connector — interactive context, namespace, and pod selection | [aliases/docs/pod.md](aliases/docs/pod.md) |
| `sentry` | sentry | Sentry issue search — query events by custom tags across projects | [aliases/docs/sentry.md](aliases/docs/sentry.md) |
| `dbs` | docker | Start local Docker database containers | — |
| `dotalias` | core | Reload all aliases | — |

## Dependencies

- **zsh** — Required (aliases use zsh-specific features)
- **[gum](https://github.com/charmbracelet/gum)** — Recommended, for interactive menus. Install: `brew install gum`
- **[kubectl](https://kubernetes.io/docs/tasks/tools/)** — Required for `pod` and `pf` aliases. Install: `brew install kubectl`
- **[jq](https://jqlang.github.io/jq/)** — Required for `sentry` alias. Install: `brew install jq`

## Running Tests

```
bats aliases/tests/
```

Requires [bats-core](https://github.com/bats-core/bats-core): `brew install bats-core`
