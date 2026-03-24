[← Back to README](../README.md)

# pod — Kubernetes Pod Connector

Connect to any running pod across clusters with interactive context, namespace, and pod selection.

## Commands

| Command | Description |
|---------|-------------|
| `pod` | Full interactive flow — select context, enter namespace, pick pod, connect |
| `pod <context>` | Skip context selection — enter namespace, pick pod, connect |
| `pod <context> <namespace>` | Skip to pod selection — pick pod, connect |

## Quick Start

```zsh
# Full interactive — select everything step by step
pod

# Provide context, enter namespace interactively
pod prod-us

# Provide both, jump straight to pod selection
pod prod-us monitoring
```

## Requirements

| Tool | Required | Install |
|------|----------|---------|
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Yes | `brew install kubectl` |
| [gum](https://github.com/charmbracelet/gum) | Yes | `brew install gum` |

Both tools are required. Without either, `pod` will print an install hint and exit.

## Usage

### Full interactive (no arguments)

1. Fetches all kubectl contexts and presents a selection menu
2. Prompts for a namespace (free text input)
3. Lists pods in that namespace and presents a selection menu
4. Connects via `kubectl exec -it <pod> -- bash`

### With context provided

Skips step 1 — uses the provided context directly.

### With context and namespace provided

Skips steps 1 and 2 — goes straight to pod selection.

### Tab Completion

The first argument tab-completes kubectl context names.
