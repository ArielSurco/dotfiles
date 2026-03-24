[← Back to README](../README.md)

# pf — Kubernetes Port Forwarding

Forward ports from the HAProxy service across clusters with interactive context and port selection.

## Commands

| Command | Description |
|---------|-------------|
| `pf` | Full interactive flow — select context, pick port, connect |
| `pf <context>` | Skip context selection — pick port, connect |
| `pf <context> <port-name>` | Direct connection — no interaction needed |

## Quick Start

```zsh
# Full interactive — select everything step by step
pf

# Provide context, pick port interactively
pf sandbox

# Direct — forward payments port on sandbox
pf sandbox payments-rw
```

## Requirements

| Tool | Required | Install |
|------|----------|---------|
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Yes | `brew install kubectl` |
| [gum](https://github.com/charmbracelet/gum) | Yes | `brew install gum` |

Both tools are required. Without either, `pf` will print an install hint and exit.

## How It Works

1. **Context resolution** — if no context argument is provided, fetches all kubectl contexts and presents a `gum choose` menu
2. **Port discovery** — runs `kubectl describe service haproxy` in the `haproxy` namespace and parses `Port:` lines to extract port names and numbers
3. **Port selection** — if no port name argument is provided, presents discovered ports via `gum choose` in `name (number)` format
4. **Connection** — runs `kubectl port-forward -n haproxy svc/haproxy <port>:<port>` to forward the selected port to localhost

The namespace (`haproxy`) and service (`svc/haproxy`) are hardcoded — this command is purpose-built for HAProxy port forwarding.

## Tab Completion

Both arguments support tab completion:

- **First argument** — completes with kubectl context names (fetched live)
- **Second argument** — completes with cached port names for the given context

Port names are cached to `~/.dotfiles-data/pf-ports-<context>` on every interactive fetch. Tab completion reads from this cache without hitting the cluster, so run `pf <context>` at least once to populate completions for a given context.
